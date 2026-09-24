module client.worldgen_driver;

import core.stdc.math : coshf;
import core.stdc.stdlib : calloc, free;
import core.sys.posix.pthread : pthread_cond_broadcast, pthread_cond_destroy, pthread_cond_init, pthread_cond_t, pthread_cond_wait, pthread_create, pthread_join, pthread_mutex_destroy, pthread_mutex_init, pthread_mutex_lock, pthread_mutex_t, pthread_mutex_unlock, pthread_t;
import core.sys.posix.unistd : _SC_NPROCESSORS_ONLN, sysconf;
import common.array : Array;
import common.dodeca : CHUNK_BOUNDING_SPHERE_RADIUS, VERTEX_COUNT, Vertex, vertexAdjacentVertices, vertexCanonicalSides, vertexChunkBoundingSphereCenter;
import common.graph : Graph, NO_NODE, NO_SLOT;
import common.margins : fixMargins;
import common.math : MIsometry, MPoint;
import common.node : Chunk, ChunkId, ChunkState, VoxelData;
import common.traversal : NearbyNode;
import common.voxel_math : CHUNK_DIRECTIONS, ChunkDirection, CoordSign;
import common.worldgen.generation : ChunkParams, createChunkParams, generateVoxels;

enum uint MAX_WORKERS = 8;
enum uint RESERVED_CORES = 2;
enum uint DONE_FOREVER = uint.max;
enum uint MAX_SCAN_NODES_PER_FRAME = 4096;
enum uint MAX_REQUESTS_PER_FRAME = 32;
enum uint MAX_IN_FLIGHT = 128;

struct GenRequest {
    ChunkParams params;
    ChunkId chunk;
}

struct GenResult {
    VoxelData voxels;
    ChunkId chunk;
}

struct GenQueue {
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    Array!GenRequest pending;
    Array!GenResult done;
    size_t pendingHead;
    bool stopping;
}

struct WorldgenDriver {
    pthread_t[MAX_WORKERS] workers;
    Array!GenRequest requests;
    Array!GenResult results;
    Array!uint doneVersion;
    GenQueue* queue;
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
            pthread_cond_wait(&queue.condition, &queue.mutex);
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
            VoxelData voxels = generateVoxels(&request.params);
            pthread_mutex_lock(&queue.mutex);
            queue.done.append(GenResult(voxels, request.chunk));
            pthread_cond_broadcast(&queue.condition);
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
    pthread_cond_init(&driver.queue.condition, null);
    long cores = sysconf(_SC_NPROCESSORS_ONLN);
    uint threadCount = 1;
    if (cores > RESERVED_CORES) {
        threadCount = cast(uint)(cores - RESERVED_CORES);
    }
    if (threadCount > MAX_WORKERS) {
        threadCount = MAX_WORKERS;
    }
    foreach (i; 0 .. threadCount) {
        pthread_create(&driver.workers[i], null, &workerMain, driver.queue);
    }
    driver.workerCount = threadCount;
    return driver;
}

void driveWorldgen(WorldgenDriver* driver, const(NearbyNode)[] nearby, MIsometry!float cameraLocal, float distance, Graph* graph, uint nearbyVersion) {
    integrateWorldgen(driver, graph, false);
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
    uint requestBudget = MAX_IN_FLIGHT - driver.inFlight;
    if (requestBudget > MAX_REQUESTS_PER_FRAME) {
        requestBudget = MAX_REQUESTS_PER_FRAME;
    }
    uint scanned = 0;
    size_t index = driver.scanCursor;
    bool budgetLeft = true;
    while (budgetLeft && index < nearby.length && scanned < MAX_SCAN_NODES_PER_FRAME) {
        NearbyNode nearbyNode = nearby[index];
        if (nearbyNode.slot != NO_SLOT && driver.doneVersion.ptr[nearbyNode.slot] != DONE_FOREVER && driver.doneVersion.ptr[nearbyNode.slot] != nearbyVersion) {
            scanned += 1;
            uint freshOutOfRange = 0;
            foreach (vertexIndex; 0 .. VERTEX_COUNT) {
                Vertex vertex = cast(Vertex) vertexIndex;
                Chunk* chunk = &graph.nodeAt(nearbyNode.slot).chunks[vertex];
                if (budgetLeft && chunk.state == ChunkState.Fresh) {
                    MPoint!float chunkCenter = nearbyNode.transform * vertexChunkBoundingSphereCenter(vertex);
                    if (-startPoint.mip(chunkCenter.vec) > threshold) {
                        freshOutOfRange += 1;
                    } else if (driver.requests.length >= requestBudget) {
                        budgetLeft = false;
                    } else {
                        ChunkId chunkId = ChunkId(nearbyNode.id, vertex);
                        driver.requests.append(GenRequest(createChunkParams(graph, chunkId, driver.flatWorldgen), chunkId));
                        chunk.state = ChunkState.Generating;
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
        pthread_cond_broadcast(&driver.queue.condition);
        pthread_mutex_unlock(&driver.queue.mutex);
    }
}

void settleWorldgen(WorldgenDriver* driver, Graph* graph) {
    while (driver.inFlight > 0) {
        integrateWorldgen(driver, graph, true);
    }
}

void integrateWorldgen(WorldgenDriver* driver, Graph* graph, bool wait) {
    driver.results.clear();
    pthread_mutex_lock(&driver.queue.mutex);
    while (wait && driver.queue.done.length == 0) {
        pthread_cond_wait(&driver.queue.condition, &driver.queue.mutex);
    }
    foreach (result; driver.queue.done.slice()) {
        driver.results.append(result);
    }
    driver.queue.done.clear();
    pthread_mutex_unlock(&driver.queue.mutex);
    foreach (result; driver.results.slice()) {
        driver.inFlight -= 1;
        populateChunk(graph, result.chunk, result.voxels);
    }
}

void releaseWorldgenDriver(WorldgenDriver* driver) {
    pthread_mutex_lock(&driver.queue.mutex);
    driver.queue.stopping = true;
    pthread_cond_broadcast(&driver.queue.condition);
    pthread_mutex_unlock(&driver.queue.mutex);
    foreach (i; 0 .. driver.workerCount) {
        pthread_join(driver.workers[i], null);
    }
    driver.workerCount = 0;
    foreach (result; driver.queue.done.slice()) {
        result.voxels.release();
    }
    driver.queue.pending.release();
    driver.queue.done.release();
    pthread_cond_destroy(&driver.queue.condition);
    pthread_mutex_destroy(&driver.queue.mutex);
    free(driver.queue);
    driver.queue = null;
    driver.requests.release();
    driver.results.release();
    driver.doneVersion.release();
}

void populateChunk(Graph* graph, ChunkId chunk, VoxelData voxels) {
    Chunk* target = &graph.nodeOf(chunk.node).chunks[chunk.vertex];
    target.voxels = voxels;
    foreach (direction; CHUNK_DIRECTIONS) {
        ChunkId neighborChunk = getChunkNeighbor(graph, chunk, direction);
        if (neighborChunk.node != NO_NODE) {
            Chunk* neighbor = &graph.nodeOf(neighborChunk.node).chunks[neighborChunk.vertex];
            if (neighbor.state == ChunkState.Populated) {
                fixMargins(graph.layout.dimension, chunk.vertex, &target.voxels, direction, &neighbor.voxels);
                neighbor.generation += 1;
            }
        }
    }
    target.state = ChunkState.Populated;
    target.generation += 1;
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
