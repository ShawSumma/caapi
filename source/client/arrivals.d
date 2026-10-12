module client.arrivals;

import core.atomic : atomicLoad, cas;
import core.stdc.stdlib : calloc, free;
import base.array : Array;
import base.parallel : Executor, ParallelJob;
import client.tasks : GenResult;
import common.graph : Graph, NODE_HASH_MULTIPLIER, NO_SLOT, ROOT_NODE;
import common.material : Material;
import common.neighbors : chunkNeighborSlot, isBorderingVoid, isPredictionContradicted, needsMesh, touchChunksAround;
import common.node : Chunk, ChunkSlot, ChunkState, Voxels, cellCount;
import common.worldgen.generation : ChunkParams, GeneratedVoxels, Worldgen;
import geometry.cube : DIRECTIONS;
import geometry.honeycomb : CORNER_COUNT, FACE_COUNT, Face;

struct IntegrationOutput {
    Array!ChunkSlot restored;
    Array!ChunkSlot holders;
    Array!ChunkSlot changed;
    Array!ChunkSlot exposed;

    void clear() {
        restored.clear();
        holders.clear();
        changed.clear();
        exposed.clear();
    }

    void release() {
        restored.release();
        holders.release();
        changed.release();
        exposed.release();
    }
}

struct IntegrationJob {
    Graph* graph;
    GenResult* arrivals;
    IntegrationOutput* outputs;
}

// Arrived chunks are stored on every thread in one pass, and in a second pass, which sees them all populated, each
// works out what its arrival changes around it. A neighbor several arrivals share is claimed with an atomic swap of
// one of its fields so exactly one thread takes it; what the main thread must still do lands in per-thread lists.
struct Integrator {
    Array!GenResult arrivals;
    IntegrationOutput* outputs;
    uint participants;

    static Integrator make(uint participants) {
        Integrator integrator;
        integrator.participants = participants;
        integrator.outputs = cast(IntegrationOutput*) calloc(participants, IntegrationOutput.sizeof);
        return integrator;
    }

    void run(ref Graph graph, Executor executor) {
        if (arrivals.length > 0) {
            join(graph, executor);
        }
    }

    void join(ref Graph graph, Executor executor) {
        IntegrationJob context = IntegrationJob(&graph, arrivals.ptr, outputs);
        runPass(executor, &storeArrival, &context, arrivals.length);
        runPass(executor, &settleArrival, &context, arrivals.length);
        foreach (worker; 0 .. participants) {
            graph.chunks.restores.appendAll(outputs[worker].restored.slice());
            graph.chunks.changed.appendAll(outputs[worker].changed.slice());
        }
        foreach (worker; 0 .. participants) {
            foreach (holder; outputs[worker].holders.slice()) {
                graph.markChanged(holder);
            }
            foreach (exposed; outputs[worker].exposed.slice()) {
                graph.resolveIfExposed(exposed);
            }
            outputs[worker].clear();
        }
        arrivals.clear();
    }

    void release() {
        foreach (arrival; arrivals.slice()) {
            arrival.generated.voxels.release();
        }
        foreach (worker; 0 .. participants) {
            outputs[worker].release();
        }
        free(outputs);
        outputs = null;
        arrivals.release();
    }
}

void runPass(Executor executor, void function(void* context, size_t item, uint worker) pass, IntegrationJob* context, size_t count) {
    ParallelJob job = ParallelJob(pass, context, double.infinity, count);
    executor.run(&job);
}

void storeArrival(void* context, size_t item, uint worker) {
    IntegrationJob* job = cast(IntegrationJob*) context;
    GenResult arrival = job.arrivals[item];
    Chunk* chunk = job.graph.chunks.existing(arrival.chunk);
    chunk.voxels = arrival.generated.voxels;
    chunk.hasDeferredMaterials = arrival.generated.hasDeferredMaterials;
    chunk.state = ChunkState.populated;
}

void settleArrival(void* context, size_t item, uint worker) {
    IntegrationJob* job = cast(IntegrationJob*) context;
    settle(*job.graph, job.arrivals[item], job.outputs[worker]);
}

// A new chunk is meshed, and so are the neighbors whose faces against it change; a dropped neighbor is made again so
// the new chunk's border is never meshed against nothing. A restored chunk holds what it held before, so the meshes
// around it still hold. Wherever a chunk with stand-in materials now borders an empty cell, it is resolved.
void settle(ref Graph graph, GenResult arrival, ref IntegrationOutput output) {
    const(Chunk)* chunk = graph.chunks.at(arrival.chunk);
    if (!arrival.isRestoring) {
        queueMesh(graph, arrival.chunk, output);
        if ((*chunk).isPredictionContradicted()) {
            graph.touchChunksAround(arrival.chunk, output.holders);
        }
    }
    if (chunk.hasDeferredMaterials && graph.isBorderingVoid(arrival.chunk)) {
        output.exposed.append(arrival.chunk);
    }
    foreach (direction; DIRECTIONS) {
        ChunkSlot neighbor = graph.chunkNeighborSlot(arrival.chunk, direction);
        if (neighbor.slot != NO_SLOT && graph.chunks.has(neighbor.slot)) {
            Chunk* other = graph.chunks.existing(neighbor);
            if (!arrival.isRestoring && cas(cast(shared(ChunkState)*) &other.state, ChunkState.dropped, ChunkState.generating)) {
                output.restored.append(neighbor);
            } else if (atomicLoad(*cast(shared(ChunkState)*) &other.state) == ChunkState.populated) {
                if (!arrival.isRestoring) {
                    queueMesh(graph, neighbor, output);
                }
                if (other.hasDeferredMaterials && graph.isBorderingVoid(neighbor)) {
                    output.exposed.append(neighbor);
                }
            }
        }
    }
}

// Whichever thread first marks a chunk queued queues it.
void queueMesh(ref Graph graph, ChunkSlot target, ref IntegrationOutput output) {
    if (graph.needsMesh(target) && cas(cast(shared(bool)*) &graph.chunks.existing(target).isQueued, false, true)) {
        output.changed.append(target);
    }
}

void generateNow(ref Graph graph, ChunkSlot chunk) {
    if (graph.chunks.at(chunk).state == ChunkState.fresh) {
        ChunkParams params = ChunkParams.make(graph.view, chunk.slot, chunk.corner);
        graph.chunks.writable(chunk).predicted = params.predictOccupancy();
        graph.populateChunk(chunk, params.generateVoxels());
    }
}

void populateChunk(ref Graph graph, ChunkSlot chunk, GeneratedVoxels generated) {
    Integrator integrator = Integrator.make(1);
    integrator.arrivals.append(GenResult(generated, chunk, false));
    integrator.run(graph, Executor(null));
    integrator.release();
}

void resolveIfExposed(ref Graph graph, ChunkSlot chunk) {
    if (graph.chunks.at(chunk).hasDeferredMaterials && graph.isBorderingVoid(chunk)) {
        graph.resolveMaterials(chunk);
    }
}

// Faces on a chunk's border are drawn by whichever side is see-through, so new materials there change the
// neighbors' meshes as well as its own.
void resolveMaterials(ref Graph graph, ChunkSlot chunk) {
    ChunkParams params = ChunkParams.make(graph.view, chunk.slot, chunk.corner);
    params.isResolvingMaterials = true;
    GeneratedVoxels generated = params.generateVoxels();
    Chunk* target = graph.chunks.existing(chunk);
    target.voxels.release();
    target.voxels = generated.voxels;
    target.hasDeferredMaterials = false;
    graph.markChanged(chunk);
    foreach (direction; DIRECTIONS) {
        ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
        if (neighbor.slot != NO_SLOT && graph.chunks.at(neighbor).state == ChunkState.populated) {
            graph.markChanged(neighbor);
        }
    }
}

enum ubyte TEST_DIMENSION = 4;
enum ulong TEST_MIX = 0xBF58476D1CE4E5B9;
enum size_t TEST_KINDS = 4;
enum size_t TEST_VOID_ODDS = 3;
enum size_t TEST_BATCH_STRIDE = 3;

GeneratedVoxels testVoxels(size_t chunk) {
    if (chunk % TEST_KINDS == 0) {
        return GeneratedVoxels(Voxels.filled(Material.granite), false);
    } else if (chunk % TEST_KINDS == 1) {
        return GeneratedVoxels(Voxels.filled(Material.none), false);
    } else {
        Voxels voxels = Voxels.filled(Material.granite);
        Material[] cells = voxels.toDense(TEST_DIMENSION);
        foreach (cell; 0 .. cellCount(TEST_DIMENSION)) {
            if (((chunk * NODE_HASH_MULTIPLIER + cell) * TEST_MIX >> 32) % TEST_VOID_ODDS == 0) {
                cells[cell] = Material.none;
            }
        }
        return GeneratedVoxels(voxels, false);
    }
}

bool isArrivedIn(ChunkSlot chunk, size_t batch) {
    return (cast(size_t) chunk.slot * CORNER_COUNT + chunk.corner) / TEST_BATCH_STRIDE % 2 == batch;
}

bool isBesideArrivalIn(ref const Graph graph, ChunkSlot chunk, size_t batch) {
    bool isBeside = false;
    foreach (direction; DIRECTIONS) {
        ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
        isBeside = isBeside || (neighbor.slot != NO_SLOT && isArrivedIn(neighbor, batch));
    }
    return isBeside;
}

// Every chunk that shows faces must be waiting to be meshed, and a dropped chunk beside a new one must be coming back.
unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.makeTerrain());
    uint root = graph.slotOf(ROOT_NODE);
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
                integrator.arrivals.append(GenResult(testVoxels(index), chunk, false));
            }
        }
        integrator.run(graph, Executor(null));
        if (batch == 0) {
            Chunk* chunk = graph.chunks.existing(dropped);
            chunk.voxels.release();
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
