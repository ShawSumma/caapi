module client.worldgen_driver;

import core.stdc.math : coshf;
import core.stdc.stdlib : calloc, free;
import core.sys.posix.pthread : pthread_cond_broadcast, pthread_cond_destroy, pthread_cond_init, pthread_cond_signal, pthread_cond_t, pthread_cond_wait, pthread_create, pthread_join, pthread_mutex_destroy, pthread_mutex_init, pthread_mutex_lock, pthread_mutex_t, pthread_mutex_unlock, pthread_t;
import core.sys.posix.time : CLOCK_MONOTONIC, clock_gettime, timespec;
import core.sys.posix.unistd : _SC_NPROCESSORS_ONLN, sysconf;
import common.array : Array;
import common.chunk_neighbors : chunkNeighborSlot, contradictsPrediction, touchChunksAround;
import common.dodeca : CHUNK_BOUNDING_SPHERE_RADIUS, VERTEX_COUNT, Vertex, vertexAdjacentVertices, vertexCanonicalSides, vertexChunkBoundingSphereCenter;
import common.graph : Graph, NO_NODE, NO_SLOT;
import common.margins : fixMargins, marginFacesHaveVoid;
import common.math : MIsometry, MPoint;
import common.node : Chunk, ChunkId, ChunkSlot, ChunkState;
import common.traversal : NO_DEADLINE, NearbyNode;
import common.voxel_math : CHUNK_DIRECTIONS, ChunkDirection, CoordSign;
import common.worldgen.generation : ChunkParams, GeneratedVoxels, createChunkParams, generateVoxels, predictOccupancy;

enum uint RESERVED_CORES = 2;
enum uint DONE_FOREVER = uint.max;
enum uint MAX_SCAN_NODES_PER_FRAME = 4096;
enum uint IN_FLIGHT_PER_WORKER = 256;
enum double WORLDGEN_BUDGET_MILLISECONDS = 6.0;
enum double NANOSECONDS_PER_MILLISECOND = 1e6;
enum double MILLISECONDS_PER_SECOND = 1e3;

struct GenRequest {
    ChunkParams params;
    ChunkSlot chunk;
}

struct GenResult {
    GeneratedVoxels generated;
    ChunkSlot chunk;
}

struct GenQueue {
    pthread_mutex_t mutex;
    pthread_cond_t workAvailable;
    pthread_cond_t resultsReady;
    Array!GenRequest pending;
    Array!GenResult done;
    size_t pendingHead;
    bool stopping;
}

struct WorldgenDriver {
    Array!pthread_t workers;
    Array!GenRequest requests;
    Array!GenResult results;
    Array!uint doneVersion;
    GenQueue* queue;
    size_t resultsHead;
    uint workerCount;
    uint inFlight;
    uint scanCursor;
    uint scanVersion;
    bool flatWorldgen;
}

extern (C) void* workerMain(void* argument) {
    GenQueue* queue = cast(GenQueue*) argument;
    bool running = true;
    while (running) {
        pthread_mutex_lock(&queue.mutex);
        while (queue.pendingHead >= queue.pending.length && !queue.stopping) {
            pthread_cond_wait(&queue.workAvailable, &queue.mutex);
        }
        bool hasRequest = queue.pendingHead < queue.pending.length;
        GenRequest request;
        if (hasRequest) {
            request = queue.pending.ptr[queue.pendingHead];
            queue.pendingHead += 1;
            if (queue.pendingHead >= queue.pending.length) {
                queue.pending.clear();
                queue.pendingHead = 0;
            }
        }
        pthread_mutex_unlock(&queue.mutex);
        if (hasRequest) {
            GeneratedVoxels generated = generateVoxels(&request.params);
            pthread_mutex_lock(&queue.mutex);
            queue.done.append(GenResult(generated, request.chunk));
            pthread_cond_signal(&queue.resultsReady);
            pthread_mutex_unlock(&queue.mutex);
        } else {
            running = false;
        }
    }
    return null;
}

WorldgenDriver createWorldgenDriver(bool flatWorldgen) {
    WorldgenDriver driver;
    driver.flatWorldgen = flatWorldgen;
    driver.queue = cast(GenQueue*) calloc(1, GenQueue.sizeof);
    pthread_mutex_init(&driver.queue.mutex, null);
    pthread_cond_init(&driver.queue.workAvailable, null);
    pthread_cond_init(&driver.queue.resultsReady, null);
    long cores = sysconf(_SC_NPROCESSORS_ONLN);
    uint threadCount = 1;
    if (cores > RESERVED_CORES) {
        threadCount = cast(uint)(cores - RESERVED_CORES);
    }
    driver.workers.resize(threadCount);
    foreach (i; 0 .. threadCount) {
        pthread_create(&driver.workers.ptr[i], null, &workerMain, driver.queue);
    }
    driver.workerCount = threadCount;
    return driver;
}

void driveWorldgen(WorldgenDriver* driver, const(NearbyNode)[] nearby, MIsometry!float cameraLocal, float distance, Graph* graph, uint nearbyVersion, bool unbudgeted) {
    double start = nowMilliseconds();
    double deadline = start + WORLDGEN_BUDGET_MILLISECONDS;
    if (unbudgeted) {
        deadline = NO_DEADLINE;
    }
    integrateWorldgen(driver, graph, false, deadline);
    float threshold = coshf(distance + CHUNK_BOUNDING_SPHERE_RADIUS);
    MPoint!float startPoint = cameraLocal * MPoint!float.origin();
    driver.requests.clear();
    if (driver.doneVersion.length < graph.nodeCount) {
        driver.doneVersion.resize(graph.nodeCount);
    }
    if (driver.scanVersion != nearbyVersion) {
        driver.scanVersion = nearbyVersion;
        driver.scanCursor = 0;
    }
    uint requestBudget = 0;
    if (unbudgeted) {
        requestBudget = uint.max;
    } else if (driver.inFlight < driver.workerCount * IN_FLIGHT_PER_WORKER) {
        requestBudget = driver.workerCount * IN_FLIGHT_PER_WORKER - driver.inFlight;
    }
    uint scanned = 0;
    size_t index = driver.scanCursor;
    bool budgetLeft = true;
    while (budgetLeft && index < nearby.length && scanned < MAX_SCAN_NODES_PER_FRAME) {
        budgetLeft = nowMilliseconds() < deadline;
        NearbyNode nearbyNode = nearby[index];
        if (budgetLeft && nearbyNode.slot != NO_SLOT && driver.doneVersion.ptr[nearbyNode.slot] != DONE_FOREVER && driver.doneVersion.ptr[nearbyNode.slot] != nearbyVersion) {
            scanned += 1;
            uint freshOutOfRange = 0;
            foreach (vertexIndex; 0 .. VERTEX_COUNT) {
                Vertex vertex = cast(Vertex) vertexIndex;
                Chunk* chunk = &graph.nodeAt(nearbyNode.slot).chunks[vertex];
                if (budgetLeft && chunk.state == ChunkState.Fresh) {
                    MPoint!float chunkCenter = nearbyNode.transform * vertexChunkBoundingSphereCenter(vertex);
                    if (-startPoint.mip(chunkCenter.vec) > threshold) {
                        freshOutOfRange += 1;
                    } else if (driver.requests.length >= requestBudget || nowMilliseconds() >= deadline) {
                        budgetLeft = false;
                    } else {
                        ChunkParams params = createChunkParams(graph, nearbyNode.slot, vertex, driver.flatWorldgen);
                        driver.requests.append(GenRequest(params, ChunkSlot(nearbyNode.slot, vertex)));
                        chunk.state = ChunkState.Generating;
                        chunk.predicted = predictOccupancy(&params);
                    }
                }
            }
            if (budgetLeft && freshOutOfRange == 0) {
                driver.doneVersion.ptr[nearbyNode.slot] = DONE_FOREVER;
            } else if (budgetLeft) {
                driver.doneVersion.ptr[nearbyNode.slot] = nearbyVersion;
            }
        }
        if (budgetLeft) {
            index += 1;
        }
    }
    driver.scanCursor = cast(uint) index;
    if (driver.requests.length > 0) {
        driver.inFlight += cast(uint) driver.requests.length;
        pthread_mutex_lock(&driver.queue.mutex);
        foreach (request; driver.requests.slice()) {
            driver.queue.pending.append(request);
        }
        pthread_cond_broadcast(&driver.queue.workAvailable);
        pthread_mutex_unlock(&driver.queue.mutex);
    }
}

void settleWorldgen(WorldgenDriver* driver, Graph* graph) {
    while (driver.inFlight > 0) {
        integrateWorldgen(driver, graph, true, 0);
    }
}

void integrateWorldgen(WorldgenDriver* driver, Graph* graph, bool wait, double deadline) {
    pthread_mutex_lock(&driver.queue.mutex);
    while (wait && driver.queue.done.length == 0 && driver.resultsHead == driver.results.length) {
        pthread_cond_wait(&driver.queue.resultsReady, &driver.queue.mutex);
    }
    foreach (result; driver.queue.done.slice()) {
        driver.results.append(result);
    }
    driver.queue.done.clear();
    pthread_mutex_unlock(&driver.queue.mutex);
    while (driver.resultsHead < driver.results.length && (wait || nowMilliseconds() < deadline)) {
        GenResult result = driver.results.ptr[driver.resultsHead];
        driver.resultsHead += 1;
        driver.inFlight -= 1;
        populateChunk(graph, result.chunk, result.generated);
    }
    if (driver.resultsHead == driver.results.length) {
        driver.results.clear();
        driver.resultsHead = 0;
    }
}

double nowMilliseconds() {
    timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec * MILLISECONDS_PER_SECOND + now.tv_nsec / NANOSECONDS_PER_MILLISECOND;
}

void releaseWorldgenDriver(WorldgenDriver* driver) {
    pthread_mutex_lock(&driver.queue.mutex);
    driver.queue.stopping = true;
    pthread_cond_broadcast(&driver.queue.workAvailable);
    pthread_mutex_unlock(&driver.queue.mutex);
    foreach (i; 0 .. driver.workerCount) {
        pthread_join(driver.workers.ptr[i], null);
    }
    driver.workerCount = 0;
    driver.workers.release();
    foreach (result; driver.queue.done.slice()) {
        result.generated.voxels.release();
    }
    foreach (result; driver.results.slice()[driver.resultsHead .. $]) {
        result.generated.voxels.release();
    }
    driver.queue.pending.release();
    driver.queue.done.release();
    pthread_cond_destroy(&driver.queue.workAvailable);
    pthread_cond_destroy(&driver.queue.resultsReady);
    pthread_mutex_destroy(&driver.queue.mutex);
    free(driver.queue);
    driver.queue = null;
    driver.requests.release();
    driver.results.release();
    driver.doneVersion.release();
}

void generateNow(Graph* graph, ChunkSlot chunk, bool flat) {
    if (chunkAt(graph, chunk).state == ChunkState.Fresh) {
        ChunkParams params = createChunkParams(graph, chunk.slot, chunk.vertex, flat);
        chunkAt(graph, chunk).predicted = predictOccupancy(&params);
        populateChunk(graph, chunk, generateVoxels(&params));
    }
}

Chunk* chunkAt(Graph* graph, ChunkSlot chunk) {
    return &graph.nodeAt(chunk.slot).chunks[chunk.vertex];
}

Chunk* populatedNeighbor(Graph* graph, ChunkSlot chunk, ChunkDirection direction) {
    ChunkSlot neighbor = chunkNeighborSlot(graph, chunk, direction);
    Chunk* result = null;
    if (neighbor.slot != NO_SLOT && chunkAt(graph, neighbor).state == ChunkState.Populated) {
        result = chunkAt(graph, neighbor);
    }
    return result;
}

void populateChunk(Graph* graph, ChunkSlot chunk, GeneratedVoxels generated) {
    Chunk* target = chunkAt(graph, chunk);
    target.voxels = generated.voxels;
    target.materialsDeferred = generated.materialsDeferred;
    bool contradicts = contradictsPrediction(target);
    connectMargins(graph, chunk);
    target.state = ChunkState.Populated;
    if (contradicts) {
        touchChunksAround(graph, chunk);
    }
    resolveIfExposed(graph, chunk);
    foreach (direction; CHUNK_DIRECTIONS) {
        if (populatedNeighbor(graph, chunk, direction) !is null) {
            resolveIfExposed(graph, chunkNeighborSlot(graph, chunk, direction));
        }
    }
}

void connectMargins(Graph* graph, ChunkSlot chunk) {
    Chunk* target = chunkAt(graph, chunk);
    foreach (direction; CHUNK_DIRECTIONS) {
        Chunk* neighbor = populatedNeighbor(graph, chunk, direction);
        if (neighbor !is null) {
            fixMargins(graph.layout.dimension, chunk.vertex, &target.voxels, direction, &neighbor.voxels);
            graph.markChanged(chunkNeighborSlot(graph, chunk, direction));
        }
    }
    graph.markChanged(chunk);
}

void resolveIfExposed(Graph* graph, ChunkSlot chunk) {
    Chunk* target = chunkAt(graph, chunk);
    if (target.materialsDeferred && marginFacesHaveVoid(graph.layout.dimension, &target.voxels)) {
        resolveMaterials(graph, chunk);
    }
}

void resolveMaterials(Graph* graph, ChunkSlot chunk) {
    ChunkParams params = createChunkParams(graph, chunk.slot, chunk.vertex, false);
    params.resolveMaterials = true;
    GeneratedVoxels generated = generateVoxels(&params);
    Chunk* target = chunkAt(graph, chunk);
    target.voxels.release();
    target.voxels = generated.voxels;
    target.materialsDeferred = false;
    connectMargins(graph, chunk);
}

ChunkId getChunkNeighbor(const(Graph)* graph, ChunkId chunk, ChunkDirection direction) {
    ChunkId result;
    if (direction.sign == CoordSign.Plus) {
        result = ChunkId(chunk.node, vertexAdjacentVertices(chunk.vertex)[direction.axis]);
    } else {
        result = ChunkId(graph.neighbor(chunk.node, vertexCanonicalSides(chunk.vertex)[direction.axis]), chunk.vertex);
    }
    return result;
}
