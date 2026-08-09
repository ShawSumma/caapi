module client.worldgen_driver;

import core.stdc.stdlib : calloc, free;
import core.sys.posix.pthread : pthread_cond_broadcast, pthread_cond_init;
import core.sys.posix.pthread : pthread_cond_t, pthread_cond_wait;
import core.sys.posix.pthread : pthread_create, pthread_detach;
import core.sys.posix.pthread : pthread_mutex_init, pthread_mutex_lock;
import core.sys.posix.pthread : pthread_mutex_t, pthread_mutex_unlock;
import core.sys.posix.pthread : pthread_t;
import core.sys.posix.unistd : _SC_NPROCESSORS_ONLN, sysconf;
import common.array : Array, freeSlice;
import common.hash_map : HashMap;
import common.dodeca : Vertex, CHUNK_BOUNDING_SPHERE_RADIUS;
import common.dodeca : vertexChunkBoundingSphereCenter;
import common.dodeca : vertexCanonicalSides, vertexAdjacentVertices;
import common.graph : Graph, NodeId, NO_SLOT;
import common.math : MPoint, MIsometry, cosh;
import common.node : Chunk, ChunkId, ChunkState, Node, VoxelData;
import common.traversal : NearbyNode;
import common.worldgen : ChunkParams, ChunkIncidentEnviroFactors, generateVoxels;
import common.worldgen : chunkRngSeed, generateTreesAfterTerrain;
import common.worldgen : producesSolidChunk, solidChunkMaterial;
import common.world : Material;
import common.margins : fixMargins, initializeMargins;
import bindings.vk : VkDevice, VkQueue;
import client.graphics.voxels.worldgen_gpu : WorldgenGpu, WorldgenParamsGPU;
import common.voxel_math : ChunkDirection, CoordSign;

struct GenRequest {
    ChunkId chunk;
    ChunkParams params;
}

struct GenResult {
    ChunkId chunk;
    VoxelData voxels;
}

// Work queue shared with the generation worker threads. generateVoxels is a
// pure function of ChunkParams, so workers never touch the graph: the main
// thread builds params (which may grow the graph) and integrates results.
//
// Raw pthreads rather than core.thread so this survives a betterC build.
struct GenQueue {
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    Array!GenRequest pending;
    size_t pendingHead;
    Array!GenResult done;
    bool stopping;

    void lock() {
        pthread_mutex_lock(&mutex);
    }

    void unlock() {
        pthread_mutex_unlock(&mutex);
    }
}

extern(C) void* workerMain(void* arg) {
    workerLoop(cast(GenQueue*) arg);
    return null;
}

void workerLoop(GenQueue* queue) {
    while (true) {
        GenRequest req;
        queue.lock();
        while (queue.pendingHead >= queue.pending.length() && !queue.stopping) {
            pthread_cond_wait(&queue.cond, &queue.mutex);
        }
        if (queue.pendingHead >= queue.pending.length()) {
            queue.unlock();
            return;
        }
        req = queue.pending[queue.pendingHead];
        queue.pendingHead = queue.pendingHead + 1;
        if (queue.pendingHead >= queue.pending.length()) {
            queue.pending.clear();
            queue.pendingHead = 0;
        }
        queue.unlock();

        VoxelData voxels = generateVoxels(req.params);

        queue.lock();
        queue.done.push(GenResult(req.chunk, voxels));
        queue.unlock();
    }
}

struct WorldgenDriver {
    HashMap!(ChunkId, VoxelData) preloadedVoxelData;

    GenQueue* queue;
    Array!pthread_t workers;
    bool flatWorldgen;
    uint inFlight;
    Array!GenRequest requestBuf;
    Array!GenResult resultBuf;

    // Per-slot scan skip state. DONE_FOREVER: node has no Fresh chunks left
    // (Fresh never comes back, so this is permanent). Otherwise it holds the
    // nearby-set version at which the node had only out-of-range Fresh chunks
    // — valid to skip until the next recollect moves the range.
    Array!uint doneVersion;
    enum uint DONE_FOREVER = uint.max;

    // Scan state: after a nearby-set rebuild every boundary node needs a
    // rescan; doing all ~30k in one frame is a visible hitch, so the scan
    // resumes from a cursor with a per-frame node budget instead.
    uint scanCursor;
    uint scanVersion;
    enum uint MAX_SCAN_NODES_PER_FRAME = 16384;
    // A worker generates a chunk in ~0.03ms, so eight of them can absorb far
    // more than the old 32/frame: that cap fed them ~4k chunks/sec at 120fps
    // while they could take an order of magnitude more. Integration on the
    // main thread is ~0.002ms per chunk, so a full batch costs well under a
    // millisecond.
    enum uint MAX_REQUESTS_PER_FRAME = 512;

    // Enough to keep every worker busy between frames without flooding the
    // queue with chunks the camera may move away from.
    enum uint MAX_IN_FLIGHT = 2048;

    static WorldgenDriver create() {
        WorldgenDriver w;
        w.queue = cast(GenQueue*) calloc(1, GenQueue.sizeof);
        assert(w.queue !is null, "worldgen queue allocation failed");
        *w.queue = GenQueue.init;
        pthread_mutex_init(&w.queue.mutex, null);
        pthread_cond_init(&w.queue.cond, null);

        long cpus = sysconf(_SC_NPROCESSORS_ONLN);
        uint threadCount = 1;
        if (cpus > 2) {
            threadCount = cast(uint)(cpus - 2);
        }
        if (threadCount > 8) {
            threadCount = 8;
        }
        foreach (i; 0 .. threadCount) {
            pthread_t tid;
            if (pthread_create(&tid, null, &workerMain, cast(void*) w.queue) != 0) {
                continue;
            }
            pthread_detach(tid);
            w.workers.push(tid);
        }
        return w;
    }

    // When set, chunks are generated by the GPU instead of the worker pool.
    // Owned by the renderer; null means the CPU path.
    WorldgenGpu* gpu;
    VkDevice gpuDevice;
    VkQueue gpuQueue;
    // Carries the params the GPU was actually given. Rebuilding them at
    // collection time would read a graph that has grown since, yielding
    // different enviro factors than the ones the batch was generated from.
    Array!GenRequest gpuBatch;

    // Collects the results of a finished GPU batch. Trees and margins stay on
    // the host, matching generateVoxels exactly (see --gpucheck).
    void collectGpuBatch(ref Graph graph, ubyte chunkSize) {
        if (gpu is null || !gpu.batchReady(gpuDevice)) {
            return;
        }
        size_t padded = cast(size_t) chunkSize + 2;
        size_t voxelCount = padded * padded * padded;
        foreach (i; 0 .. gpuBatch.length()) {
            ChunkId chunkId = gpuBatch[i].chunk;
            ChunkParams cp = gpuBatch[i].params;

            // The GPU always writes a dense grid, but the renderer skips solid
            // chunks entirely, so chunks the CPU would have left solid must be
            // handed over solid or they each burn a slot for nothing.
            VoxelData voxels;
            if (producesSolidChunk(cp)) {
                voxels = VoxelData.solid(solidChunkMaterial(cp));
            } else {
                voxels = VoxelData.solid(Material.Void);
                Material[] dense = voxels.dataMut(chunkSize);
                const(uint)[] raw = gpu.chunkVoxels(cast(uint) i);
                foreach (v; 0 .. voxelCount) {
                    dense[v] = cast(Material) raw[v];
                }
                generateTreesAfterTerrain(cp, voxels);
                initializeMargins(chunkSize, voxels);
            }
            populateChunk(graph, chunkId, voxels, chunkSize);
        }
        inFlight = inFlight - cast(uint) gpuBatch.length();
        gpuBatch.clear();
    }

    void drive(
        const(NearbyNode)[] nearby,
        MIsometry!float camLocal,
        float distance,
        ref Graph graph,
        ubyte chunkSize,
        uint nearbyVersion,
    ) {
        collectGpuBatch(graph, chunkSize);

        // Integrate whatever the workers finished since last frame.
        resultBuf.clear();
        queue.lock();
        if (queue.done.length() > 0) {
            resultBuf.appendFrom(queue.done);
            queue.done.clear();
        }
        queue.unlock();

        foreach (i; 0 .. resultBuf.length()) {
            inFlight = inFlight - 1;
            populateChunk(graph, resultBuf[i].chunk, resultBuf[i].voxels, chunkSize);
        }

        // With a batch already in flight there is nowhere to put new requests.
        // This has to bail before the scan, not after: the scan flips chunks
        // to Generating as it selects them, and a request dropped after that
        // strands the chunk in Generating forever.
        if (gpu !is null && gpu.inFlight) {
            return;
        }

        // Queue fresh chunks in range, nearest-first (BFS order of `nearby`).
        float threshold = cosh(distance + CHUNK_BOUNDING_SPHERE_RADIUS);
        MPoint!float startP = camLocal * MPoint!float.origin();
        requestBuf.clear();

        if (doneVersion.length() < graph.slotCount()) {
            doneVersion.resize(graph.slotCount());
        }
        if (scanVersion != nearbyVersion) {
            scanVersion = nearbyVersion;
            scanCursor = 0;
        }

        uint requestBudget = MAX_IN_FLIGHT - inFlight;
        if (requestBudget > MAX_REQUESTS_PER_FRAME) {
            requestBudget = MAX_REQUESTS_PER_FRAME;
        }

        uint scanned = 0;
        size_t idx = scanCursor;
        outer: while (idx < nearby.length && scanned < MAX_SCAN_NODES_PER_FRAME) {
            const NearbyNode nn = nearby[idx];
            idx = idx + 1;
            if (nn.slot == NO_SLOT) {
                continue;
            }
            uint dv = doneVersion[nn.slot];
            if (dv == DONE_FOREVER || dv == nearbyVersion) {
                continue;
            }
            scanned = scanned + 1;

            uint freshOutOfRange = 0;
            foreach (int vIdx; 0 .. Vertex.max + 1) {
                Vertex vertex = cast(Vertex) vIdx;
                // Re-derive from the slot each iteration: ChunkParams.create
                // below can grow the graph slab, which moves Node memory
                // (slots stay valid, pointers don't).
                Chunk* c = &graph.nodeAt(nn.slot).chunks.values[vertex];
                if (c.state != ChunkState.Fresh) {
                    continue;
                }
                ChunkId chunkId = ChunkId(nn.id, vertex);

                MPoint!float chunkCenter =
                    nn.transform * vertexChunkBoundingSphereCenter(vertex);
                if (-startP.mip(chunkCenter.vec) > threshold) {
                    freshOutOfRange = freshOutOfRange + 1;
                    continue;
                }

                VoxelData* voxelData = chunkId in preloadedVoxelData;
                if (voxelData !is null) {
                    c.state = ChunkState.Populated;
                    c.voxels = *voxelData;
                    graph.nodeAt(nn.slot).setChunkRenderable(
                        vertex,
                        !c.voxels.isSolid(),
                    );
                    preloadedVoxelData.remove(chunkId);
                    continue;
                }

                if (requestBuf.length() >= requestBudget) {
                    // Out of request budget mid-node; resume here next frame.
                    idx = idx - 1;
                    break outer;
                }

                ChunkParams params = ChunkParams.create(graph, chunkId, flatWorldgen);
                graph.nodeAt(nn.slot).chunks.values[vertex].state =
                    ChunkState.Generating;
                requestBuf.push(GenRequest(chunkId, params));
            }
            uint mark = nearbyVersion;
            if (freshOutOfRange == 0) {
                mark = DONE_FOREVER;
            }
            doneVersion[nn.slot] = mark;
        }
        scanCursor = cast(uint) idx;

        if (requestBuf.length() == 0) {
            return;
        }

        if (gpu !is null) {
            // One submit for the whole frame's worth of chunks; picked up by
            // collectGpuBatch on a later frame rather than waiting here. The
            // request budget is below batchCapacity, so nothing is dropped.
            uint count = cast(uint) requestBuf.length();
            assert(count <= gpu.batchCapacity, "worldgen batch overflow");
            foreach (i; 0 .. count) {
                WorldgenParamsGPU gp = WorldgenGpu.buildParams(
                    requestBuf[i].params,
                    chunkRngSeed(requestBuf[i].params),
                );
                gpu.setParams(i, gp);
                gpuBatch.push(requestBuf[i]);
            }
            gpu.submitBatch(gpuDevice, gpuQueue, count);
            inFlight = inFlight + count;
            return;
        }

        inFlight = inFlight + cast(uint) requestBuf.length();
        queue.lock();
        queue.pending.appendFrom(requestBuf);
        pthread_cond_broadcast(&queue.cond);
        queue.unlock();
    }

    void applyVoxelData(ChunkId chunkId, VoxelData voxelData) {
        preloadedVoxelData.insert(chunkId, voxelData);
    }

    void release() {
        if (queue !is null) {
            queue.lock();
            queue.stopping = true;
            pthread_cond_broadcast(&queue.cond);
            queue.unlock();
        }
        workers.release();
        requestBuf.release();
        resultBuf.release();
        doneVersion.release();
        preloadedVoxelData.release();
    }
}

void populateChunk(ref Graph graph, ChunkId chunk, VoxelData voxels, ubyte dimension) {
    foreach (ChunkDirection dir; ChunkDirection.ALL) {
        ChunkId neighborChunk = getChunkNeighbor(graph, chunk, dir.axis, dir.sign);
        if (neighborChunk.node == NodeId.init) {
            continue;
        }
        if (!graph.contains(neighborChunk.node)) {
            continue;
        }
        Chunk* neighborC =
            &graph[neighborChunk.node].chunks.values[neighborChunk.vertex];
        if (neighborC.state != ChunkState.Populated) {
            continue;
        }
        fixMargins(dimension, chunk.vertex, voxels, dir, neighborC.voxels);
        neighborC.generation = neighborC.generation + 1;
    }
    Node* node = &graph[chunk.node];
    Chunk* c = &node.chunks.values[chunk.vertex];
    c.state = ChunkState.Populated;
    c.voxels = voxels;
    c.generation = c.generation + 1;
    node.setChunkRenderable(chunk.vertex, !voxels.isSolid());
}

ChunkId getChunkNeighbor(
    ref Graph graph,
    ChunkId chunk,
    ubyte coordAxis,
    CoordSign coordSign,
) {
    if (coordSign == CoordSign.Plus) {
        return ChunkId(chunk.node, vertexAdjacentVertices(chunk.vertex)[coordAxis]);
    }
    NodeId neighborNode = graph.neighbor(
        chunk.node,
        vertexCanonicalSides(chunk.vertex)[coordAxis],
    );
    if (neighborNode == NodeId.init) {
        return ChunkId(NodeId.init, chunk.vertex);
    }
    return ChunkId(neighborNode, chunk.vertex);
}
