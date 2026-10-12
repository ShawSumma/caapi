module common.eviction;

import core.stdc.math : coshf;
import common.array : Array;
import common.clock : nowMilliseconds;
import common.coords : CHUNK_DIRECTIONS;
import common.dodeca : CHUNK_BOUNDING_SPHERE_RADIUS, VERTEX_COUNT, Vertex, chunkBoundingSphereCenter;
import common.graph : Graph, NO_SLOT, Node, ParentList;
import common.math : MPoint;
import common.neighbors : chunkNeighborSlot;
import common.node : Chunk, ChunkSlot, ChunkState;
import common.traversal : NOT_COLLECTED, NearbyNode, NearbyScratch;
import common.worldgen.blueprint : TileRecord;
import common.worldgen.sky : releaseIdleWorlds, worldsAt;
import common.worldgen.structure : ClaimKey, SitePart;

enum uint SLOTS_PER_CLOCK_CHECK = 256;
enum uint SWEEP_CYCLE_FRAMES = 120;
enum double SWEEP_LEAST_MILLISECONDS = 1.0;
enum double SWEEP_MOST_MILLISECONDS = 3.0;
enum float KEEP_RADIUS = 3.0f;
enum float DROP_RADIUS = 3.5f;
enum double TILE_IDLE_TRAVEL = 3.0;

struct Evictor {
    Array!uint stack;
    uint cursor;
    uint tileCursor;
    uint evicted;
    uint dropped;
    uint droppedTiles;

    void sweep(ref Graph graph, ref const NearbyScratch published, const(NearbyScratch)* building, MPoint!float camera, ref Array!Unloaded unloaded, double start) {
        Near near = Near(&published, building);
        dropIdleTiles(graph, near);
        float dropThreshold = coshf(DROP_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS);
        uint wanted = graph.nodeCount / SWEEP_CYCLE_FRAMES;
        uint examined = 0;
        bool isDone = false;
        while (examined < graph.nodeCount && !isDone) {
            if (cursor >= graph.nodeCount) {
                cursor = 0;
                graph.releaseIdleWorlds();
            }
            uint slot = cursor;
            cursor += 1;
            examined += 1;
            if (examined % SLOTS_PER_CLOCK_CHECK == 0) {
                double spent = nowMilliseconds() - start;
                isDone = spent >= SWEEP_MOST_MILLISECONDS || (examined >= wanted && spent >= SWEEP_LEAST_MILLISECONDS);
            }
            Node* node = graph.nodeAt(slot);
            if (!graph.isLive(slot)) {
                continue;
            } else if (node.isRecent) {
                node.isRecent = false;
            } else if (near.contains(slot)) {
                node.isRecent = true;
                uint index = published.indexOf(slot);
                if (index != NOT_COLLECTED && graph.hasChunks(slot)) {
                    dropped += graph.dropFarChunks(published.nodes.ptr[index], camera, dropThreshold);
                }
            } else if (graph.isEvictable(slot)) {
                evictFrom(graph, slot, near, unloaded);
            } else {
                graph.unloadNode(slot, unloaded);
            }
        }
    }

    void evictFrom(ref Graph graph, uint slot, Near near, ref Array!Unloaded unloaded) {
        stack.append(slot);
        while (stack.length > 0) {
            uint current = stack.ptr[stack.length - 1];
            stack.length -= 1;
            ParentList parents = graph.parents(current);
            graph.evictNode(current, unloaded);
            evicted += 1;
            foreach (link; parents.links[0 .. parents.count]) {
                Node* parent = graph.nodeAt(link.slot);
                parent.neighbors[link.side] = NO_SLOT;
                parent.liveChildren -= 1;
                if (!parent.isRecent && !near.contains(link.slot) && graph.isEvictable(link.slot)) {
                    stack.append(link.slot);
                }
            }
        }
    }

    // A tile's brushes are only read when a building is planned, which paints dropped tiles again first, so tiles
    // nothing has asked for since the camera moved on are dropped unless their face is still in view.
    void dropIdleTiles(ref Graph graph, Near near) {
        size_t count = graph.blueprint.tiles.length / SWEEP_CYCLE_FRAMES + 1;
        foreach (_; 0 .. count) {
            if (tileCursor >= graph.blueprint.tiles.length) {
                tileCursor = 0;
            }
            if (tileCursor < graph.blueprint.tiles.length) {
                const(TileRecord)* record = &graph.blueprint.tiles.ptr[tileCursor];
                if (!record.isDropped && graph.blueprint.travel - record.lastUse > TILE_IDLE_TRAVEL) {
                    uint face = graph.slotOf(record.face);
                    if (face == NO_SLOT || !near.contains(face)) {
                        graph.blueprint.dropTile(tileCursor);
                        droppedTiles += 1;
                    }
                }
                tileCursor += 1;
            }
        }
    }

    void release() {
        stack.release();
    }
}

struct Near {
    const(NearbyScratch)* published;
    const(NearbyScratch)* building;

    bool contains(uint slot) const {
        return published.indexOf(slot) != NOT_COLLECTED || (building !is null && building.indexOf(slot) != NOT_COLLECTED);
    }
}

uint dropFarChunks(ref Graph graph, NearbyNode node, MPoint!float camera, float threshold) {
    uint count = 0;
    foreach (vertexIndex; 0 .. VERTEX_COUNT) {
        Vertex vertex = cast(Vertex) vertexIndex;
        ChunkSlot chunk = ChunkSlot(node.slot, vertex);
        const(Chunk)* current = graph.chunkAt(chunk);
        if (current.state == ChunkState.populated && !current.voxels.isSolid() && !current.isEdited && !current.isQueued && -camera.mip((node.transform * vertex.chunkBoundingSphereCenter).vec) > threshold && graph.areFaceNeighborsSettled(chunk)) {
            Chunk* target = graph.chunkFor(chunk);
            target.voxels.release();
            target.state = ChunkState.dropped;
            count += 1;
        }
    }
    return count;
}

bool areFaceNeighborsSettled(ref const Graph graph, ChunkSlot chunk) {
    uint direction = 0;
    while (direction < CHUNK_DIRECTIONS.length && graph.isSettled(graph.chunkNeighborSlot(chunk, CHUNK_DIRECTIONS[direction]))) {
        direction += 1;
    }
    return direction == CHUNK_DIRECTIONS.length;
}

bool isSettled(ref const Graph graph, ChunkSlot chunk) {
    if (chunk.slot == NO_SLOT) {
        return false;
    } else {
        ChunkState state = graph.chunkAt(chunk).state;
        return state == ChunkState.populated || state == ChunkState.dropped;
    }
}

bool isEvictable(ref const Graph graph, uint slot) {
    const(Node)* node = graph.nodeAt(slot);
    return node.liveChildren == 0 && node.references == 0 && !graph.isPinned(slot);
}

bool isPinned(ref const Graph graph, uint slot) {
    return graph.nodeAt(slot).isBuildingQueued || (graph.hasChunks(slot) && graph.hasPinnedChunk(slot));
}

bool hasPinnedChunk(ref const Graph graph, uint slot) {
    uint vertex = 0;
    while (vertex < VERTEX_COUNT && !isPinnedChunk(graph.chunkAt(ChunkSlot(slot, cast(Vertex) vertex)))) {
        vertex += 1;
    }
    return vertex < VERTEX_COUNT;
}

bool isPinnedChunk(const(Chunk)* chunk) {
    return chunk.state == ChunkState.generating || chunk.isEdited;
}

struct Unloaded {
    uint slot;
    uint block;
}

void unloadNode(ref Graph graph, uint slot, ref Array!Unloaded unloaded) {
    bool isHeld = false;
    if (graph.hasChunks(slot)) {
        bool isReleased = false;
        foreach (vertex; 0 .. VERTEX_COUNT) {
            Chunk* chunk = graph.chunkFor(ChunkSlot(slot, cast(Vertex) vertex));
            if ((chunk.state == ChunkState.populated || chunk.state == ChunkState.dropped) && !chunk.isEdited) {
                chunk.voxels.release();
                *chunk = Chunk.init;
                isReleased = true;
            }
            isHeld = isHeld || chunk.state != ChunkState.fresh;
        }
        if (isReleased) {
            unloaded.append(Unloaded(slot, graph.nodeAt(slot).chunkBlock));
        }
        if (!isHeld) {
            graph.releaseChunks(slot);
        } else if (isReleased) {
            foreach (vertex; 0 .. VERTEX_COUNT) {
                if (graph.chunkAt(ChunkSlot(slot, cast(Vertex) vertex)).state == ChunkState.populated) {
                    graph.markChanged(ChunkSlot(slot, cast(Vertex) vertex));
                }
            }
        }
    }
    Node* node = graph.nodeAt(slot);
    if (node.hasBuilding && !isHeld) {
        node.building.release();
        node.hasBuilding = false;
    }
}

void evictNode(ref Graph graph, uint slot, ref Array!Unloaded unloaded) {
    Node* node = graph.nodeAt(slot);
    if (graph.hasChunks(slot)) {
        unloaded.append(Unloaded(slot, node.chunkBlock));
        graph.releaseChunks(slot);
    }
    if (node.hasBuilding) {
        node.building.release();
    }
    foreach (near; graph.worldsAt(slot)) {
        graph.skies.worlds.ptr[near.world - 1].users -= 1;
    }
    graph.releaseWorlds(node.worldStart, node.worldCount);
    graph.releaseTouches(node.touchStart, node.touchLength);
    if (node.hasChoices) {
        foreach (vertex; 0 .. VERTEX_COUNT) {
            graph.skies.choices.remove(ClaimKey(slot, cast(Vertex) vertex, SitePart.vertex));
        }
    }
    graph.slots.remove(node.id);
    *node = Node.init;
    graph.freeSlots.append(slot);
    graph.liveCount -= 1;
}
