module common.eviction;

import core.stdc.math : coshf;
import base.array : Array;
import base.clock : nowMilliseconds;
import common.graph : Graph, NO_SLOT, ParentList;
import common.neighbors : chunkNeighborSlot;
import common.node : Chunk, ChunkSlot, ChunkState;
import common.traversal : NOT_COLLECTED, NearbyNode, NearbyScratch;
import common.worldgen.blueprint : TileRecord;
import common.worldgen.sky : releaseIdleWorlds;
import geometry.cube : DIRECTIONS;
import geometry.honeycomb : CORNER_COUNT, CUBE_RADIUS, Corner, cubeCenter;
import geometry.lorentz : Point;

enum uint SLOTS_PER_CLOCK_CHECK = 256;
enum uint SWEEP_CYCLE_FRAMES = 120;
enum double SWEEP_MOST_MILLISECONDS = 3.0;
enum float KEEP_RADIUS = 3.0f;
enum float DROP_RADIUS = 3.5f;
enum double TILE_IDLE_TRAVEL = 12.0;

struct Evictor {
    Array!uint stack;
    Array!bool isRecent;
    uint cursor;
    uint tileCursor;
    uint evicted;
    uint dropped;
    uint droppedTiles;

    void sweep(ref Graph graph, ref const NearbyScratch published, const(NearbyScratch)* building, Point!float camera, ref Array!Unloaded unloaded, double start) {
        Near near = Near(&published, building);
        if (isRecent.length < graph.slotCount) {
            isRecent.resize(graph.slotCount);
        }
        dropIdleTiles(graph, near);
        float dropThreshold = coshf(DROP_RADIUS + CUBE_RADIUS);
        uint wanted = graph.slotCount / SWEEP_CYCLE_FRAMES;
        uint examined = 0;
        bool isDone = false;
        while (examined < graph.slotCount && !isDone) {
            if (cursor >= graph.slotCount) {
                cursor = 0;
                graph.releaseIdleWorlds();
            }
            uint slot = cursor;
            cursor += 1;
            examined += 1;
            if (examined % SLOTS_PER_CLOCK_CHECK == 0) {
                isDone = examined >= wanted || nowMilliseconds() - start >= SWEEP_MOST_MILLISECONDS;
            }
            if (!graph.isLive(slot)) {
                continue;
            } else if (isRecent.ptr[slot]) {
                isRecent.ptr[slot] = false;
            } else if (near.contains(slot)) {
                isRecent.ptr[slot] = true;
                uint index = published.indexOf(slot);
                if (index != NOT_COLLECTED && graph.chunks.has(slot)) {
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
                if (!isRecent.ptr[link.slot] && !near.contains(link.slot) && graph.isEvictable(link.slot)) {
                    stack.append(link.slot);
                }
            }
        }
    }

    void dropIdleTiles(ref Graph graph, Near near) {
        size_t count = graph.structures.blueprint.tiles.length / SWEEP_CYCLE_FRAMES + 1;
        foreach (_; 0 .. count) {
            if (tileCursor >= graph.structures.blueprint.tiles.length) {
                tileCursor = 0;
            }
            if (tileCursor < graph.structures.blueprint.tiles.length) {
                const(TileRecord)* record = &graph.structures.blueprint.tiles.ptr[tileCursor];
                if (!record.isDropped && graph.structures.blueprint.travel - record.lastUse > TILE_IDLE_TRAVEL) {
                    uint face = graph.slotOf(record.face);
                    if (face == NO_SLOT || !near.contains(face)) {
                        graph.structures.blueprint.dropTile(tileCursor);
                        droppedTiles += 1;
                    }
                }
                tileCursor += 1;
            }
        }
    }

    void release() {
        stack.release();
        isRecent.release();
    }
}

struct Near {
    const(NearbyScratch)* published;
    const(NearbyScratch)* building;

    bool contains(uint slot) const {
        return published.indexOf(slot) != NOT_COLLECTED || (building !is null && building.indexOf(slot) != NOT_COLLECTED);
    }
}

uint dropFarChunks(ref Graph graph, NearbyNode node, Point!float camera, float threshold) {
    uint count = 0;
    foreach (index; 0 .. CORNER_COUNT) {
        Corner corner = cast(Corner) index;
        ChunkSlot chunk = ChunkSlot(node.slot, corner);
        const(Chunk)* current = graph.chunks.at(chunk);
        if (current.state == ChunkState.populated && !current.voxels.isUniform() && !current.isEdited && !current.isQueued && camera.coshDistance(node.transform * corner.cubeCenter) > threshold && graph.areFaceNeighborsSettled(chunk)) {
            Chunk* target = graph.chunks.existing(chunk);
            target.voxels.release();
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

bool isSettled(ref const Graph graph, ChunkSlot chunk) {
    if (chunk.slot == NO_SLOT) {
        return false;
    } else {
        ChunkState state = graph.chunks.at(chunk).state;
        return state == ChunkState.populated || state == ChunkState.dropped;
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
    return chunk.state == ChunkState.generating || chunk.isEdited;
}

struct Unloaded {
    uint slot;
    uint block;
}

void unloadNode(ref Graph graph, uint slot, ref Array!Unloaded unloaded) {
    bool isHeld = false;
    if (graph.chunks.has(slot)) {
        bool isReleased = false;
        foreach (corner; 0 .. CORNER_COUNT) {
            Chunk* chunk = graph.chunks.existing(ChunkSlot(slot, cast(Corner) corner));
            if ((chunk.state == ChunkState.populated || chunk.state == ChunkState.dropped) && !chunk.isEdited) {
                chunk.voxels.release();
                *chunk = Chunk.init;
                isReleased = true;
            }
            isHeld = isHeld || chunk.state != ChunkState.fresh;
        }
        if (isReleased) {
            unloaded.append(Unloaded(slot, graph.chunks.blockOf(slot)));
        }
        if (!isHeld) {
            graph.chunks.releaseBlock(slot);
        } else if (isReleased) {
            foreach (corner; 0 .. CORNER_COUNT) {
                if (graph.chunks.at(ChunkSlot(slot, cast(Corner) corner)).state == ChunkState.populated) {
                    graph.markChanged(ChunkSlot(slot, cast(Corner) corner));
                }
            }
        }
    }
    if (!isHeld) {
        graph.structures.releaseBuilding(slot);
    }
}

void evictNode(ref Graph graph, uint slot, ref Array!Unloaded unloaded) {
    if (graph.chunks.has(slot)) {
        unloaded.append(Unloaded(slot, graph.chunks.blockOf(slot)));
        graph.chunks.releaseBlock(slot);
    }
    graph.structures.forget(slot);
    graph.skies.forget(slot);
    graph.removeNode(slot);
}
