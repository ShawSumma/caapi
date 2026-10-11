module common.eviction;

import common.array : Array;
import common.dodeca : VERTEX_COUNT;
import common.graph : Graph, NO_NODE, NO_SLOT, Node, NodeId, ROOT_NODE, slabRun;
import common.hashmap : keepWhere, visitEntries;
import common.node : Chunk, ChunkSlot, ChunkState;
import common.slab : Slab;
import common.traversal : NearbyNode;
import common.worldgen.sky : PLANET, SkyChoice, World, WorldRef, worldAt, worldsAt;
import common.worldgen.structure : ClaimKey;

enum ubyte EVICTED = 0;
enum ubyte HELD = 1;
enum ubyte NEAR = 2;

void evictOutside(ref Graph graph, const(NearbyNode)[] published, const(NearbyNode)[] building, ref Array!uint unloaded) {
    Keeper keeper = Keeper.make(graph);
    foreach (node; published) {
        keeper.hold(graph, node.slot, NEAR);
    }
    foreach (node; building) {
        keeper.hold(graph, node.slot, NEAR);
    }
    keeper.holdStructures(graph);
    keeper.holdWorlds(graph);
    keeper.evictWorlds(graph);
    WorldCompaction worlds;
    foreach (slot; 0 .. graph.nodeCount) {
        Node* node = graph.nodeAt(slot);
        if (node.id == NO_NODE) {
            continue;
        } else if (keeper.marks.ptr[slot] == EVICTED) {
            graph.evictNode(slot, unloaded);
        } else {
            if (keeper.marks.ptr[slot] == HELD) {
                graph.unloadNode(slot, unloaded);
            }
            foreach (ref neighbor; node.neighbors) {
                if (neighbor != NO_SLOT && keeper.marks.ptr[neighbor] == EVICTED) {
                    neighbor = NO_SLOT;
                }
            }
            worlds.keep(graph, node);
        }
    }
    worlds.finish(graph);
    keepWhere!((ref Array!ubyte kept, NodeId id, uint slot) => kept.ptr[slot] != EVICTED)(graph.slots, keeper.marks);
    keepWhere!((ref Array!ubyte kept, ClaimKey key, SkyChoice choice) => kept.ptr[key.slot] != EVICTED)(graph.skies.choices, keeper.marks);
    graph.keepQueuedChanges();
    keeper.release();
}

struct Keeper {
    Array!ubyte marks;
    Array!uint stack;
    Array!uint marked;
    Array!bool keptWorlds;
    Array!uint worldQueue;

    static Keeper make(ref const Graph graph) {
        Keeper keeper;
        keeper.marks.resize(graph.nodeCount);
        keeper.keptWorlds.resize(graph.skies.worlds.length);
        return keeper;
    }

    void hold(ref const Graph graph, uint slot, ubyte mark) {
        if (graph.isLive(slot) && marks.ptr[slot] == EVICTED) {
            marks.ptr[slot] = mark;
            stack.append(slot);
        }
    }

    void holdStructures(ref Graph graph) {
        hold(graph, graph.slotOf(ROOT_NODE), HELD);
        hold(graph, graph.anchorSlot, HELD);
        foreach (slot; 0 .. graph.nodeCount) {
            if (graph.isLive(slot) && graph.isPinned(slot)) {
                hold(graph, slot, HELD);
            }
        }
        foreach (line; graph.blueprint.lines.slice()) {
            hold(graph, line.node, HELD);
        }
        foreach (stop; graph.blueprint.route.slice()) {
            hold(graph, stop.site.node, HELD);
        }
        if (graph.blueprint.hasEntrance) {
            hold(graph, graph.blueprint.entrance.site.node, HELD);
        }
        Array!uint slots;
        visitEntries!((ref Array!uint found, ClaimKey key, bool isClaimed) { found.append(key.slot); })(graph.blueprint.claims, slots);
        visitEntries!((ref Array!uint found, ClaimKey key, SkyChoice choice) { found.append(key.slot); })(graph.skies.forced, slots);
        if (graph.grower.hold !is null) {
            graph.grower.hold(graph.grower.context, slots);
        }
        foreach (slot; slots.slice()) {
            hold(graph, slot, HELD);
        }
        slots.release();
    }

    void holdWorlds(ref Graph graph) {
        foreach (index, world; graph.skies.worlds.slice()) {
            if (world.isKnown && world.isTiled) {
                keepWorld(cast(uint) index + 1);
            }
        }
        Array!ClaimKey forced;
        visitEntries!((ref Array!ClaimKey found, ClaimKey key, SkyChoice choice) { found.append(key); })(graph.skies.forced, forced);
        foreach (key; forced.slice()) {
            const(uint)* world = graph.skies.worldOf.find(key);
            if (world !is null) {
                keepWorld(*world);
            }
        }
        forced.release();
        size_t scanned = 0;
        do {
            holdAncestors(graph);
            foreach (slot; marked.slice()[scanned .. $]) {
                foreach (near; graph.worldsAt(slot)) {
                    keepWorld(near.world);
                }
            }
            scanned = marked.length;
            while (worldQueue.length > 0) {
                World world = graph.worldAt(worldQueue.ptr[worldQueue.length - 1]);
                worldQueue.length -= 1;
                keepWorld(world.parent);
                hold(graph, world.foot.node, HELD);
                hold(graph, world.footNode, HELD);
                hold(graph, world.vertex.slot, HELD);
            }
        } while (stack.length > 0);
    }

    void keepWorld(uint world) {
        if (world != PLANET && !keptWorlds.ptr[world - 1]) {
            keptWorlds.ptr[world - 1] = true;
            worldQueue.append(world);
        }
    }

    void holdAncestors(ref const Graph graph) {
        while (stack.length > 0) {
            uint slot = stack.ptr[stack.length - 1];
            stack.length -= 1;
            marked.append(slot);
            const(Node)* node = graph.nodeAt(slot);
            foreach (neighbor; node.neighbors) {
                if (neighbor != NO_SLOT && graph.nodeAt(neighbor).depth < node.depth) {
                    hold(graph, neighbor, HELD);
                }
            }
        }
    }

    void evictWorlds(ref Graph graph) {
        foreach (index, ref world; graph.skies.worlds.slice()) {
            if (world.isKnown && !keptWorlds.ptr[index]) {
                world = World.init;
                graph.skies.freeWorlds.append(cast(uint) index + 1);
            }
        }
        keepWhere!((ref Array!bool kept, ClaimKey key, uint world) => kept.ptr[world - 1])(graph.skies.worldOf, keptWorlds);
    }

    void release() {
        marks.release();
        stack.release();
        marked.release();
        keptWorlds.release();
        worldQueue.release();
    }
}

bool isPinned(ref const Graph graph, uint slot) {
    const(Node)* node = graph.nodeAt(slot);
    return node.touchLength > 0 || node.pendingHead != 0 || node.isTiled || node.isBuildingQueued || (node.hasChunks && graph.hasPinnedChunk(slot));
}

bool hasPinnedChunk(ref const Graph graph, uint slot) {
    uint vertex = 0;
    while (vertex < VERTEX_COUNT && !isPinnedChunk(graph.chunkAt(ChunkSlot.fromIndex(cast(size_t) slot * VERTEX_COUNT + vertex)))) {
        vertex += 1;
    }
    return vertex < VERTEX_COUNT;
}

bool isPinnedChunk(const(Chunk)* chunk) {
    return chunk.state == ChunkState.generating || chunk.isEdited;
}

void unloadNode(ref Graph graph, uint slot, ref Array!uint unloaded) {
    Node* node = graph.nodeAt(slot);
    bool isHeld = false;
    if (node.hasChunks) {
        bool isReleased = false;
        foreach (vertex; 0 .. VERTEX_COUNT) {
            Chunk* chunk = graph.chunks.at(cast(size_t) slot * VERTEX_COUNT + vertex);
            if (chunk.state == ChunkState.populated && !chunk.isEdited) {
                chunk.voxels.release();
                *chunk = Chunk.init;
                isReleased = true;
            }
            isHeld = isHeld || chunk.state != ChunkState.fresh;
        }
        node.hasChunks = isHeld;
        if (isReleased) {
            unloaded.append(slot);
        }
    }
    if (node.hasBuilding && !isHeld) {
        node.building.release();
        node.hasBuilding = false;
    }
}

void evictNode(ref Graph graph, uint slot, ref Array!uint unloaded) {
    Node* node = graph.nodeAt(slot);
    if (node.hasChunks) {
        foreach (vertex; 0 .. VERTEX_COUNT) {
            Chunk* chunk = graph.chunks.at(cast(size_t) slot * VERTEX_COUNT + vertex);
            chunk.voxels.release();
            *chunk = Chunk.init;
        }
        unloaded.append(slot);
    }
    if (node.hasBuilding) {
        node.building.release();
    }
    *node = Node.init;
    graph.freeSlots.append(slot);
    graph.liveCount -= 1;
}

struct WorldCompaction {
    Slab!WorldRef kept;
    uint count;

    void keep(ref const Graph graph, Node* node) {
        if (node.worldCount > 0) {
            uint start = slabRun(count, node.worldCount);
            kept.ensure(start + node.worldCount);
            foreach (index; 0 .. node.worldCount) {
                *kept.at(start + index) = *graph.worldRefs.at(node.worldStart + index);
            }
            node.worldStart = start;
            count = start + node.worldCount;
        }
    }

    void finish(ref Graph graph) {
        graph.worldRefs.release();
        graph.worldRefs = kept;
        graph.worldRefCount = count;
    }
}

void keepQueuedChanges(ref Graph graph) {
    size_t kept = 0;
    foreach (index; graph.changedHead .. graph.changedChunks.length) {
        ChunkSlot chunk = graph.changedChunks.ptr[index];
        if (graph.chunkAt(chunk).isQueued) {
            graph.changedChunks.ptr[kept] = chunk;
            kept += 1;
        }
    }
    graph.changedChunks.length = kept;
    graph.changedHead = 0;
}
