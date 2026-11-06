module common.eviction;

import core.stdc.math : coshf;
import base.array : Array;
import base.clock : nowMilliseconds;
import base.flags : Bits;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : higherOf;
import common.graph : Graph, ParentList;
import common.neighbors : chunkNeighborSlot;
import common.node : Chunk, ChunkSlot, ChunkState;
import common.traversal : NearbyNode, NearbyScratch;
import common.worldgen.blueprint : Blueprint;
import common.worldgen.horospheres : releaseIdleHorospheres;
import common.worldgen.store : dropTile, forgetTile, isTileGone, isTilePinned, unpin;
import geometry.cube : DIRECTIONS;
import geometry.honeycomb : CORNER_COUNT, CUBE_RADIUS, Corner, cubeCenter;
import geometry.lorentz : Point;

enum uint SLOTS_PER_CLOCK_CHECK = 256;
enum uint SWEEP_CYCLE_FRAMES = 120;
enum uint SWEEP_LEAST_SLOTS = 1024;
enum double SWEEP_MOST_MILLISECONDS = 3.0;
enum float KEEP_RADIUS = 3.0f;
enum float DROP_RADIUS = 3.5f;
enum uint TILE_IDLE_SWEEPS = 60;
enum uint TILE_CYCLE_FRAMES = 30;
enum uint TILES_PER_CLOCK_CHECK = 64;

struct Evictor {
    Array!uint stack;
    Bits recent;
    uint cursor;
    uint tileCursor;
    uint forgetCursor;
    uint seenLive;
    uint seenNodes;
    uint evicted;
    uint dropped;
    uint droppedTiles;
    uint forgottenTiles;

    void sweep(ref Graph graph, ref const NearbyScratch published, const(NearbyScratch)* building, Point!float camera, ref Array!Unloaded unloaded, double start) {
        Near near = Near(&published, building);
        recent.cover(graph.slotCount);
        double deadline = start + SWEEP_MOST_MILLISECONDS;
        dropIdleTiles(graph, near, deadline);
        forgetGoneTiles(graph);
        float dropThreshold = coshf(DROP_RADIUS + CUBE_RADIUS);
        uint wanted = higherOf(graph.slotCount / SWEEP_CYCLE_FRAMES, SWEEP_LEAST_SLOTS);
        uint owed = graph.madeNodes - seenNodes;
        seenNodes = graph.madeNodes;
        uint before = evicted;
        uint examined = 0;
        uint limit = wanted;
        while (examined < limit) {
            if (cursor >= graph.slotCount) {
                cursor = 0;
                graph.releaseIdleHorospheres();
            }
            uint slot = cursor;
            cursor += 1;
            examined += 1;
            if (examined % SLOTS_PER_CLOCK_CHECK == 0 && evicted - before >= owed) {
                double now = nowMilliseconds();
                if (now >= deadline) {
                    limit = examined;
                }
            }
            if (graph.isLive(slot)) {
                if (recent.has(slot)) {
                    recent.clear(slot);
                } else if (near.contains(slot)) {
                    recent.set(slot);
                    MaybeIndex!uint index = published.indexOf(slot);
                    if (index.exists && graph.chunks.has(slot)) {
                        dropped += graph.dropFarChunks(published.nodes.ptr[index.value], camera, dropThreshold);
                    }
                } else if (graph.isEvictable(slot)) {
                    evictFrom(graph, slot, near, unloaded);
                } else {
                    graph.unloadNode(slot, unloaded);
                }
            }
        }
        graph.discardFreed();
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
                if (!recent.has(link.slot) && !near.contains(link.slot) && graph.isEvictable(link.slot)) {
                    stack.append(link.slot);
                }
            }
        }
    }

    void dropIdleTiles(ref Graph graph, Near near, double deadline) {
        Blueprint* blueprint = &graph.structures.blueprint;
        blueprint.sweep += 1;
        uint owed = blueprint.madeLive - seenLive;
        seenLive = blueprint.madeLive;
        size_t count = blueprint.liveTiles.length / TILE_CYCLE_FRAMES + 1;
        size_t examined = 0;
        while (examined < count) {
            if (tileCursor >= blueprint.liveTiles.length) {
                tileCursor = 0;
            }
            if (tileCursor < blueprint.liveTiles.length) {
                uint tile = blueprint.liveTiles.ptr[tileCursor];
                if (graph.isTileIdle(tile, tileCursor, near)) {
                    graph.dropTile(tile);
                    droppedTiles += 1;
                    if (owed > 0) {
                        owed -= 1;
                    }
                    if (graph.isTileGone(tile)) {
                        graph.forgetTile(tile);
                        forgottenTiles += 1;
                    }
                } else {
                    tileCursor += 1;
                }
            }
            examined += 1;
            if (examined % TILES_PER_CLOCK_CHECK == 0 && owed == 0) {
                double now = nowMilliseconds();
                if (now >= deadline) {
                    return;
                }
            }
        }
    }

    void forgetGoneTiles(ref Graph graph) {
        Blueprint* blueprint = &graph.structures.blueprint;
        size_t count = blueprint.droppedTiles.length / SWEEP_CYCLE_FRAMES + 1;
        foreach (examined; 0 .. count) {
            if (forgetCursor >= blueprint.droppedTiles.length) {
                forgetCursor = 0;
            }
            if (forgetCursor < blueprint.droppedTiles.length) {
                uint tile = blueprint.droppedTiles.ptr[forgetCursor];
                if (graph.isTileGone(tile)) {
                    graph.forgetTile(tile);
                    forgottenTiles += 1;
                } else {
                    forgetCursor += 1;
                }
            }
        }
    }

    void release() {
        stack.release();
        recent.release();
    }
}

bool isTileIdle(ref const Graph graph, uint tile, uint listed, Near near) {
    const(Blueprint)* blueprint = &graph.structures.blueprint;
    if (blueprint.sweep - blueprint.liveUses.ptr[listed] > TILE_IDLE_SWEEPS && !graph.isTilePinned(tile)) {
        MaybeIndex!uint face = graph.slotOf(blueprint.tiles.ptr[tile].face);
        return !face.exists || !near.contains(face.value);
    } else {
        return false;
    }
}

struct Near {
    const(NearbyScratch)* published;
    const(NearbyScratch)* building;

    bool contains(uint slot) const {
        return published.indexOf(slot).exists || (building !is null && building.indexOf(slot).exists);
    }
}

uint dropFarChunks(ref Graph graph, NearbyNode node, Point!float camera, float threshold) {
    uint count = 0;
    foreach (index; 0 .. CORNER_COUNT) {
        Corner corner = cast(Corner) index;
        ChunkSlot chunk = ChunkSlot(node.slot, corner);
        const(Chunk)* current = graph.chunks.at(chunk);
        if (current.state == ChunkState.populated && !current.voxels.isUniform() && !current.isQueued && camera.coshDistance(node.transform * corner.cubeCenter) > threshold && graph.areFaceNeighborsSettled(chunk)) {
            Chunk* target = graph.chunks.existing(chunk);
            target.releaseVoxels();
            target.state = ChunkState.dropped;
            count += 1;
        }
    }
    return count;
}

bool areFaceNeighborsSettled(ref const Graph graph, ChunkSlot chunk) {
    uint direction = 0;
    while (direction < DIRECTIONS.length && graph.isSettled(graph.chunkNeighborSlot(chunk, DIRECTIONS[direction]))) {
        direction += 1;
    }
    return direction == DIRECTIONS.length;
}

bool isSettled(ref const Graph graph, Maybe!ChunkSlot chunk) {
    if (chunk.exists) {
        ChunkState state = graph.chunks.at(chunk.value).state;
        return state == ChunkState.populated || state == ChunkState.dropped;
    } else {
        return false;
    }
}

bool isEvictable(ref const Graph graph, uint slot) {
    return graph.nodeAt(slot).liveChildren == 0 && graph.nodeAt(slot).references == 0 && !graph.isPinned(slot);
}

bool isPinned(ref const Graph graph, uint slot) {
    return graph.structures.at(slot).isBuildingQueued || (graph.chunks.has(slot) && graph.hasPinnedChunk(slot));
}

bool hasPinnedChunk(ref const Graph graph, uint slot) {
    uint corner = 0;
    while (corner < CORNER_COUNT && !isPinnedChunk(graph.chunks.at(ChunkSlot(slot, cast(Corner) corner)))) {
        corner += 1;
    }
    return corner < CORNER_COUNT;
}

bool isPinnedChunk(const(Chunk)* chunk) {
    return chunk.state == ChunkState.generating;
}

struct Unloaded {
    uint slot;
    MaybeIndex!uint block;
}

void unloadNode(ref Graph graph, uint slot, ref Array!Unloaded unloaded) {
    uint held = 0;
    if (graph.chunks.has(slot)) {
        uint released = 0;
        foreach (corner; 0 .. CORNER_COUNT) {
            Chunk* chunk = graph.chunks.existing(ChunkSlot(slot, cast(Corner) corner));
            if (chunk.state == ChunkState.populated || chunk.state == ChunkState.dropped) {
                chunk.releaseVoxels();
                *chunk = Chunk.init;
                released += 1;
            }
            if (chunk.state != ChunkState.fresh) {
                held += 1;
            }
        }
        if (released > 0) {
            unloaded.append(Unloaded(slot, graph.chunks.blockOf(slot)));
        }
        if (held == 0) {
            graph.chunks.releaseBlock(slot);
        } else if (released > 0) {
            foreach (corner; 0 .. CORNER_COUNT) {
                if (graph.chunks.at(ChunkSlot(slot, cast(Corner) corner)).state == ChunkState.populated) {
                    graph.markChanged(ChunkSlot(slot, cast(Corner) corner));
                }
            }
        }
    }
    if (held == 0) {
        graph.structures.releaseBuilding(slot);
        graph.horospheres.forget(slot);
    }
    graph.unpin(slot);
}

void evictNode(ref Graph graph, uint slot, ref Array!Unloaded unloaded) {
    unloaded.append(Unloaded(slot, graph.chunks.blockOf(slot)));
    if (graph.chunks.has(slot)) {
        graph.chunks.releaseBlock(slot);
    }
    graph.unpin(slot);
    graph.structures.forget(slot);
    graph.horospheres.forget(slot);
    graph.removeNode(slot);
}
