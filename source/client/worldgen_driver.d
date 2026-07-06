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
__gshared Mutex gMutex;
__gshared Condition gCond;
__gshared GenRequest[] gPending;
__gshared size_t gPendingHead;
__gshared GenResult[] gDone;
__gshared bool gStopping;

void workerFunc() {
    while (true) {
        GenRequest req;
        synchronized (gMutex) {
            while (gPendingHead >= gPending.length && !gStopping) {
                gCond.wait();
            }
            if (gPendingHead >= gPending.length) {
                return;
            }
            req = gPending[gPendingHead++];
            if (gPendingHead >= gPending.length) {
                gPending.length = 0;
                gPending.assumeSafeAppend();
                gPendingHead = 0;
            }
        }
        VoxelData voxels = generateVoxels(req.params);
        synchronized (gMutex) {
            gDone ~= GenResult(req.chunk, voxels);
        }
    }
}

struct WorldgenDriver {
    VoxelData[ChunkId] preloadedVoxelData;

    Thread[] workers;
    uint inFlight;
    GenRequest[] requestBuf;
    GenResult[] resultBuf;

    // Per-slot scan skip state. DONE_FOREVER: node has no Fresh chunks left
    // (Fresh never comes back, so this is permanent). Otherwise it holds the
    // nearby-set version at which the node had only out-of-range Fresh chunks
    // — valid to skip until the next recollect moves the range.
    uint[] doneVersion;
    enum uint DONE_FOREVER = uint.max;

    // Enough to keep every worker busy between frames without flooding the
    // queue with chunks the camera may move away from.
    enum uint MAX_IN_FLIGHT = 128;

    static WorldgenDriver create() {
        WorldgenDriver w;
        gMutex = new Mutex;
        gCond = new Condition(gMutex);
        gPending.length = 0;
        gPendingHead = 0;
        gDone.length = 0;
        gStopping = false;

        uint threadCount = totalCPUs > 2 ? totalCPUs - 2 : 1;
        if (threadCount > 8) {
            threadCount = 8;
        }
        foreach (i; 0 .. threadCount) {
            Thread t = new Thread(&workerFunc);
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
        // Integrate whatever the workers finished since last frame.
        resultBuf.length = 0;
        resultBuf.assumeSafeAppend();
        synchronized (gMutex) {
            if (gDone.length > 0) {
                resultBuf ~= gDone;
                gDone.length = 0;
                gDone.assumeSafeAppend();
            }
        }
        foreach (ref GenResult r; resultBuf) {
            inFlight--;
            populateChunk(graph, r.chunk, r.voxels, chunkSize);
        }

        // Queue fresh chunks in range, nearest-first (BFS order of `nearby`).
        float threshold = cosh(distance + CHUNK_BOUNDING_SPHERE_RADIUS);
        MPoint!float startP = camLocal * MPoint!float.origin();
        requestBuf.length = 0;
        requestBuf.assumeSafeAppend();

        if (doneVersion.length < graph.slotCount()) {
            doneVersion.length = graph.slotCount();
        }

        outer: foreach (ref const NearbyNode nn; nearby) {
            if (nn.slot == NO_SLOT) {
                continue;
            }
            uint dv = doneVersion[nn.slot];
            if (dv == DONE_FOREVER || dv == nearbyVersion) {
                continue;
            }

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

                if (inFlight + requestBuf.length >= MAX_IN_FLIGHT) {
                    // Not fully scanned; leave the node's skip state untouched.
                    break outer;
                }

                ChunkParams params = ChunkParams.create(graph, chunkId);
                graph.nodeAt(nn.slot).chunks.values[vertex].state = ChunkState.Generating;
                requestBuf ~= GenRequest(chunkId, params);
            }
            doneVersion[nn.slot] = freshOutOfRange == 0 ? DONE_FOREVER : nearbyVersion;
        }

        if (requestBuf.length > 0) {
            inFlight += cast(uint) requestBuf.length;
            synchronized (gMutex) {
                gPending ~= requestBuf;
                gCond.notifyAll();
            }
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
