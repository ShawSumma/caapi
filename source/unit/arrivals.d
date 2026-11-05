module unit.arrivals;

import base.hashmap : FIBONACCI_MULTIPLIER;
import base.maybe : Maybe;
import base.parallel : Executor;
import client.arrivals : Integrator;
import client.tasks : GenKind, GenResult;
import common.graph : Graph, ROOT_NODE;
import common.neighbors : chunkNeighborSlot, needsMesh;
import common.node : Chunk, ChunkSlot, ChunkState, Materials, Voxels, cellCount;
import common.worldgen.generation : GeneratedVoxels, Worldgen;
import geometry.cube : DIRECTIONS;
import geometry.honeycomb : CORNER_COUNT, FACE_COUNT, Face;
import plugins.api.api : Material;

enum ubyte DIMENSION = 4;
enum ulong MIX = 0xBF58476D1CE4E5B9;
enum size_t KINDS = 4;
enum size_t VOID_ODDS = 3;
enum size_t BATCH_STRIDE = 3;

GeneratedVoxels madeVoxels(size_t chunk) {
    if (chunk % KINDS == 0) {
        return GeneratedVoxels(Voxels.filled(Material.granite), Materials.resolved);
    } else if (chunk % KINDS == 1) {
        return GeneratedVoxels(Voxels.filled(Material.none), Materials.resolved);
    } else {
        Voxels voxels = Voxels.filled(Material.granite);
        Material[] cells = voxels.toDense(DIMENSION);
        foreach (cell; 0 .. cellCount(DIMENSION)) {
            if (((chunk * FIBONACCI_MULTIPLIER + cell) * MIX >> 32) % VOID_ODDS == 0) {
                cells[cell] = Material.none;
            }
        }
        return GeneratedVoxels(voxels, Materials.resolved);
    }
}

bool isArrivedIn(ChunkSlot chunk, size_t batch) {
    return (cast(size_t) chunk.slot * CORNER_COUNT + chunk.corner) / BATCH_STRIDE % 2 == batch;
}

bool isBesideArrivalIn(ref const Graph graph, ChunkSlot chunk, size_t batch) {
    foreach (direction; DIRECTIONS) {
        Maybe!ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
        if (neighbor.exists && isArrivedIn(neighbor.value, batch)) {
            return true;
        }
    }
    return false;
}

unittest {
    Graph graph = Graph.make(DIMENSION, Worldgen.makeTerrain());
    uint root = graph.slotOf(ROOT_NODE).value;
    foreach (face; 0 .. FACE_COUNT) {
        graph.ensureNeighborSlot(root, cast(Face) face);
    }
    size_t chunkCount = cast(size_t) graph.slotCount * CORNER_COUNT;
    size_t first = 0;
    while (!isArrivedIn(ChunkSlot.fromIndex(first), 0) || !graph.isBesideArrivalIn(ChunkSlot.fromIndex(first), 1)) {
        first += 1;
    }
    ChunkSlot dropped = ChunkSlot.fromIndex(first);
    Integrator integrator = Integrator.make(1);
    foreach (batch; 0 .. 2) {
        foreach (index; 0 .. chunkCount) {
            ChunkSlot chunk = ChunkSlot.fromIndex(index);
            if (isArrivedIn(chunk, batch)) {
                graph.chunks.writable(chunk).state = ChunkState.generating;
                integrator.arrivals.append(GenResult(madeVoxels(index), chunk, GenKind.fresh));
            }
        }
        integrator.run(graph, Executor(null));
        if (batch == 0) {
            Chunk* chunk = graph.chunks.existing(dropped);
            chunk.releaseVoxels();
            chunk.state = ChunkState.dropped;
        }
    }
    foreach (index; 0 .. chunkCount) {
        ChunkSlot chunk = ChunkSlot.fromIndex(index);
        assert(!graph.needsMesh(chunk) || graph.chunks.at(chunk).isQueued);
    }
    assert(graph.chunks.at(dropped).state == ChunkState.generating && graph.chunks.restores.length == 1);
    integrator.release();
    graph.release();
}
