module client.arrivals;

import core.stdc.stdlib : calloc, free;
import base.array : Array;
import base.parallel : Executor, ParallelJob;
import client.tasks : GenKind, GenResult;
import common.graph : Graph, NO_SLOT;
import common.neighbors : chunkNeighborSlot, isBorderingVoid, isPredictionContradicted, needsMesh, touchChunksAround;
import common.node : Chunk, ChunkSlot, ChunkState, Materials;
import common.worldgen.generation : ChunkParams, GeneratedVoxels, MaterialPass;
import geometry.cube : DIRECTIONS;

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
    chunk.materials = arrival.generated.materials;
    chunk.state = ChunkState.populated;
}

void settleArrival(void* context, size_t item, uint worker) {
    IntegrationJob* job = cast(IntegrationJob*) context;
    settle(*job.graph, job.arrivals[item], job.outputs[worker]);
}

void settle(ref Graph graph, GenResult arrival, ref IntegrationOutput output) {
    const(Chunk)* chunk = graph.chunks.at(arrival.chunk);
    if (arrival.kind == GenKind.fresh) {
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
            if (arrival.kind == GenKind.fresh && other.casState(ChunkState.dropped, ChunkState.generating)) {
                output.restored.append(neighbor);
            } else if (other.loadState() == ChunkState.populated) {
                if (arrival.kind == GenKind.fresh) {
                    queueMesh(graph, neighbor, output);
                }
                if (other.hasDeferredMaterials && graph.isBorderingVoid(neighbor)) {
                    output.exposed.append(neighbor);
                }
            }
        }
    }
}

void queueMesh(ref Graph graph, ChunkSlot target, ref IntegrationOutput output) {
    if (graph.needsMesh(target) && graph.chunks.existing(target).claimQueued()) {
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
    integrator.arrivals.append(GenResult(generated, chunk, GenKind.fresh));
    integrator.run(graph, Executor(null));
    integrator.release();
}

void resolveIfExposed(ref Graph graph, ChunkSlot chunk) {
    if (graph.chunks.at(chunk).hasDeferredMaterials && graph.isBorderingVoid(chunk)) {
        graph.resolveMaterials(chunk);
    }
}

void resolveMaterials(ref Graph graph, ChunkSlot chunk) {
    ChunkParams params = ChunkParams.make(graph.view, chunk.slot, chunk.corner);
    params.materials = MaterialPass.resolving;
    GeneratedVoxels generated = params.generateVoxels();
    Chunk* target = graph.chunks.existing(chunk);
    target.releaseVoxels();
    target.voxels = generated.voxels;
    target.materials = Materials.resolved;
    graph.markChanged(chunk);
    foreach (direction; DIRECTIONS) {
        ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
        if (neighbor.slot != NO_SLOT && graph.chunks.at(neighbor).state == ChunkState.populated) {
            graph.markChanged(neighbor);
        }
    }
}
