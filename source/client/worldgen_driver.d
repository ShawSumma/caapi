module client.worldgen_driver;

import core.sync.condition : Condition;
import core.sync.mutex : Mutex;
import core.thread : Thread;
import std.math : cosh;
import std.parallelism : totalCPUs;
import common.dodeca : Vertex, CHUNK_BOUNDING_SPHERE_RADIUS,
    vertexChunkBoundingSphereCenter, vertexCanonicalSides, vertexAdjacentVertices;
import common.graph : Graph, NodeId, NO_SLOT;
import common.math : MPoint, MIsometry;
import common.node : Chunk, ChunkId, ChunkState, Node, VoxelData;
import common.traversal : NearbyNode;
import common.worldgen : ChunkParams, ChunkIncidentEnviroFactors, generateVoxels;
import common.margins : fixMargins;
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
struct GenQueue {
    Mutex mutex;
    Condition cond;
    GenRequest[] pending;
    size_t pendingHead;
    GenResult[] done;
    bool stopping;
}

void workerLoop(GenQueue* queue) {
    while (true) {
        GenRequest req;
        synchronized (queue.mutex) {
            while (queue.pendingHead >= queue.pending.length && !queue.stopping) {
                queue.cond.wait();
            }
            if (queue.pendingHead >= queue.pending.length) {
                return;
            }
            req = queue.pending[queue.pendingHead++];
            if (queue.pendingHead >= queue.pending.length) {
                queue.pending.length = 0;
                queue.pending.assumeSafeAppend();
                queue.pendingHead = 0;
            }
        }
        VoxelData voxels = generateVoxels(req.params);
        synchronized (queue.mutex) {
            queue.done ~= GenResult(req.chunk, voxels);
            queue.cond.notifyAll();
        }
    }
}

struct WorldgenDriver {
    VoxelData[ChunkId] preloadedVoxelData;

    GenQueue* queue;
    Thread[] workers;
    bool flatWorldgen;
    uint inFlight;
    GenRequest[] requestBuf;
    GenResult[] resultBuf;

    // Per-slot scan skip state. DONE_FOREVER: node has no Fresh chunks left
    // (Fresh never comes back, so this is permanent). Otherwise it holds the
    // nearby-set version at which the node had only out-of-range Fresh chunks
    // — valid to skip until the next recollect moves the range.
    uint[] doneVersion;
    enum uint DONE_FOREVER = uint.max;

    // Scan state: after a nearby-set rebuild every boundary node needs a
    // rescan; doing all ~30k in one frame is a visible hitch, so the scan
    // resumes from a cursor with a per-frame node budget instead.
    uint scanCursor;
    uint scanVersion;
    enum uint MAX_SCAN_NODES_PER_FRAME = 4096;
    enum uint MAX_REQUESTS_PER_FRAME = 32;

    // Enough to keep every worker busy between frames without flooding the
    // queue with chunks the camera may move away from.
    enum uint MAX_IN_FLIGHT = 128;

    static WorldgenDriver create() {
        WorldgenDriver w;
        w.queue = new GenQueue();
        w.queue.mutex = new Mutex();
        w.queue.cond = new Condition(w.queue.mutex);
        GenQueue* queue = w.queue;

        uint threadCount = totalCPUs > 2 ? totalCPUs - 2 : 1;
        if (threadCount > 8) {
            threadCount = 8;
        }
        foreach (i; 0 .. threadCount) {
            Thread t = new Thread(() => workerLoop(queue));
            t.isDaemon = true;
            t.start();
            w.workers ~= t;
        }
        return w;
    }

    void drive(
        const(NearbyNode)[] nearby,
        MIsometry!float camLocal,
        float distance,
        ref Graph graph,
        ubyte chunkSize,
        uint nearbyVersion,
    ) {
        integrate(graph, chunkSize, false);

        // Queue fresh chunks in range, nearest-first (BFS order of `nearby`).
        float threshold = cosh(distance + CHUNK_BOUNDING_SPHERE_RADIUS);
        MPoint!float startP = camLocal * MPoint!float.origin();
        requestBuf.length = 0;
        requestBuf.assumeSafeAppend();

        if (doneVersion.length < graph.slotCount()) {
            doneVersion.length = graph.slotCount();
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
        outer: for (; idx < nearby.length && scanned < MAX_SCAN_NODES_PER_FRAME; idx++) {
            const NearbyNode nn = nearby[idx];
            if (nn.slot == NO_SLOT) {
                continue;
            }
            uint dv = doneVersion[nn.slot];
            if (dv == DONE_FOREVER || dv == nearbyVersion) {
                continue;
            }
            scanned++;

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

                MPoint!float chunkCenter = nn.transform * vertexChunkBoundingSphereCenter(vertex);
                if (-startP.mip(chunkCenter.vec) > threshold) {
                    freshOutOfRange++;
                    continue;
                }

                VoxelData* voxelData = chunkId in preloadedVoxelData;
                if (voxelData !is null) {
                    c.state = ChunkState.Populated;
                    c.voxels = *voxelData;
                    preloadedVoxelData.remove(chunkId);
                    continue;
                }

                if (requestBuf.length >= requestBudget) {
                    // Out of request budget mid-node; resume here next frame.
                    break outer;
                }

                ChunkParams params = ChunkParams.create(graph, chunkId, flatWorldgen);
                graph.nodeAt(nn.slot).chunks.values[vertex].state = ChunkState.Generating;
                requestBuf ~= GenRequest(chunkId, params);
            }
            doneVersion[nn.slot] = freshOutOfRange == 0 ? DONE_FOREVER : nearbyVersion;
        }
        scanCursor = cast(uint) idx;

        if (requestBuf.length > 0) {
            inFlight += cast(uint) requestBuf.length;
            synchronized (queue.mutex) {
                queue.pending ~= requestBuf;
                queue.cond.notifyAll();
            }
        }
    }

    /// Stops and joins the worker threads; the driver is unusable after.
    void stop() {
        synchronized (queue.mutex) {
            queue.stopping = true;
            queue.cond.notifyAll();
        }
        foreach (t; workers) {
            t.join();
        }
        workers = null;
    }

    /// Blocks until every requested chunk is generated and integrated. With
    /// this after each drive, what the world contains at each frame no
    /// longer depends on worker timing, which headless runs require.
    void settle(ref Graph graph, ubyte chunkSize) {
        while (inFlight > 0) {
            integrate(graph, chunkSize, true);
        }
    }

    /// Populates chunks the workers have finished. With `wait`, blocks until
    /// at least one result is available.
    void integrate(ref Graph graph, ubyte chunkSize, bool wait) {
        resultBuf.length = 0;
        resultBuf.assumeSafeAppend();
        synchronized (queue.mutex) {
            while (wait && queue.done.length == 0) {
                queue.cond.wait();
            }
            if (queue.done.length > 0) {
                resultBuf ~= queue.done;
                queue.done.length = 0;
                queue.done.assumeSafeAppend();
            }
        }
        foreach (ref GenResult r; resultBuf) {
            inFlight--;
            populateChunk(graph, r.chunk, r.voxels, chunkSize);
        }
    }

    void applyVoxelData(ChunkId chunkId, VoxelData voxelData) {
        preloadedVoxelData[chunkId] = voxelData;
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
        Chunk* neighborC = &graph[neighborChunk.node].chunks.values[neighborChunk.vertex];
        if (neighborC.state != ChunkState.Populated) {
            continue;
        }
        fixMargins(dimension, chunk.vertex, voxels, dir, neighborC.voxels);
        neighborC.generation++;
    }
    Chunk* c = &graph[chunk.node].chunks.values[chunk.vertex];
    c.state = ChunkState.Populated;
    c.voxels = voxels;
    c.generation++;
}

ChunkId getChunkNeighbor(ref Graph graph, ChunkId chunk, ubyte coordAxis, CoordSign coordSign) {
    if (coordSign == CoordSign.Plus) {
        return ChunkId(chunk.node, vertexAdjacentVertices(chunk.vertex)[coordAxis]);
    }
    else {
        NodeId neighborNode = graph.neighbor(chunk.node, vertexCanonicalSides(chunk.vertex)[coordAxis]);
        if (neighborNode == NodeId.init) {
            return ChunkId(NodeId.init, chunk.vertex);
        }
        return ChunkId(neighborNode, chunk.vertex);
    }
}
