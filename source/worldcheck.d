module worldcheck;

// Deterministic, headless world-generation dump. Emits one line per generated
// chunk: "<nodeId> <vertex> <hash>", sorted, so a plain diff of two runs points
// at the exact chunk(s) that changed. The per-chunk hash covers the chunk's
// voxel + margin bytes; the GPU mesh is a pure function of those, so an
// unchanged line means an unchanged mesh for that chunk. No aggregate digest.

import core.stdc.math : coshf;
import core.stdc.stdio : fflush, printf, stdout;
import common.array : Array, sortSlice;
import common.clock : nowMs, sleepMs;
import common.graph : Graph, NodeId;
import common.node : Chunk, ChunkId, ChunkState, VoxelData;
import common.dodeca : Vertex, CHUNK_BOUNDING_SPHERE_RADIUS;
import common.dodeca : vertexChunkBoundingSphereCenter;
import common.math : MIsometry, MPoint;
import common.traversal : ensureAndCollectNearby, NearbyNode, NearbyScratch;
import common.worldgen : ChunkParams, generateVoxels;
import client.worldgen_driver : WorldgenDriver, populateChunk;

// Two independent FNV-1a streams widened to 128 bits. Only used to tell one
// run's chunk from another's, so collision resistance beyond accidental
// change detection is not required.
struct Hash128 {
    ulong a = 0xCBF29CE484222325;
    ulong b = 0x9E3779B97F4A7C15;

    void put(const(ubyte)[] bytes) {
        foreach (x; bytes) {
            a = (a ^ x) * 0x100000001B3;
            b = (b ^ x) * 0xD6E8FEB86659FD93;
            b = b ^ (b >> 29);
        }
    }

    ubyte[16] finish() const {
        ubyte[16] result;
        foreach (i; 0 .. 8) {
            result[i] = cast(ubyte)(a >> (i * 8));
            result[i + 8] = cast(ubyte)(b >> (i * 8));
        }
        return result;
    }
}

ubyte[16] chunkHash(ubyte vertex, const ref VoxelData v) {
    Hash128 h;
    ubyte[2] head = [vertex, cast(ubyte) v.kind];
    h.put(head[]);
    if (v.kind == VoxelData.Kind.Solid) {
        ushort m = cast(ushort) v.solidMaterial;
        h.put((cast(ubyte*) &m)[0 .. 2]);
    } else {
        h.put(cast(const(ubyte)[]) v.denseData);
    }
    return h.finish();
}

void hex32(ref char[33] buf, const(ubyte)[] d) {
    static immutable string digits = "0123456789abcdef";
    foreach (i; 0 .. 16) {
        buf[i * 2] = digits[d[i] >> 4];
        buf[i * 2 + 1] = digits[d[i] & 0xF];
    }
    buf[32] = '\0';
}

struct ChunkLine {
    ulong n0;
    ulong n1;
    ubyte vertex;
    ubyte[16] hash;

    int opCmp(const ChunkLine other) const {
        if (n0 != other.n0) {
            return (n0 > other.n0) - (n0 < other.n0);
        }
        if (n1 != other.n1) {
            return (n1 > other.n1) - (n1 < other.n1);
        }
        return cast(int) vertex - cast(int) other.vertex;
    }
}

// True when the chunk is unbuilt and close enough that the client worldgen
// driver would generate it. Keeps dumpWorld and benchGen selecting exactly
// the same set.
bool shouldGenerate(
    ref Graph graph,
    ref const NearbyNode nn,
    Vertex vertex,
    const ref MPoint!float startP,
    float threshold,
) {
    Chunk* c = &graph[nn.id].chunks.values[vertex];
    if (c.state != ChunkState.Fresh) {
        return false;
    }
    MPoint!float chunkCenter = nn.transform * vertexChunkBoundingSphereCenter(vertex);
    return -startP.mip(chunkCenter.vec) <= threshold;
}

void dumpWorld(float radius, ubyte dimension) {
    Graph graph = Graph.create(dimension);
    MIsometry!float identity = MIsometry!float.identity();
    NearbyScratch scratch;
    scope(exit) {
        scratch.release();
    }
    NearbyNode[] nearby =
        ensureAndCollectNearby(scratch, graph, NodeId.ROOT, identity, radius);

    float threshold = coshf(radius + CHUNK_BOUNDING_SPHERE_RADIUS);
    MPoint!float startP = identity * MPoint!float.origin();
    foreach (ref nn; nearby) {
        foreach (vIdx; 0 .. 20) {
            Vertex vertex = cast(Vertex) vIdx;
            if (!shouldGenerate(graph, nn, vertex, startP, threshold)) {
                continue;
            }
            ChunkId chunkId = ChunkId(nn.id, vertex);
            ChunkParams params = ChunkParams.create(graph, chunkId);
            VoxelData voxels = generateVoxels(params);
            populateChunk(graph, chunkId, voxels, dimension);
        }
    }

    Array!ChunkLine lines;
    scope(exit) {
        lines.release();
    }
    foreach (slot; 0 .. graph.slotCount()) {
        foreach (vIdx; 0 .. 20) {
            const(Chunk)* c =
                &graph.container(slot).value.chunks.values[cast(Vertex) vIdx];
            if (c.state != ChunkState.Populated) {
                continue;
            }
            NodeId id = graph.idAt(slot);
            ChunkLine line;
            line.n0 = id.value[0];
            line.n1 = id.value[1];
            line.vertex = cast(ubyte) vIdx;
            line.hash = chunkHash(cast(ubyte) vIdx, c.voxels);
            lines.push(line);
        }
    }
    sortSlice(lines.slice());

    printf(
        "# dim=%d radius=%.3f nodes=%zu nearby=%zu populated=%zu\n",
        cast(int) dimension,
        cast(double) radius,
        cast(size_t) graph.len,
        nearby.length,
        lines.length(),
    );
    foreach (i; 0 .. lines.length()) {
        char[33] hh;
        hex32(hh, lines[i].hash[]);
        printf(
            "%016llx%016llx %02d %s\n",
            lines[i].n0,
            lines[i].n1,
            cast(int) lines[i].vertex,
            hh.ptr,
        );
    }
    fflush(stdout);
}

// Headless timing of chunk generation. Generates every chunk within `radius`
// of the origin and reports where the time goes: params (enviro factors from
// the graph), voxels (generateVoxels proper), and populate (margin fixups).
void benchGen(float radius, ubyte dimension) {
    Graph graph = Graph.create(dimension);
    MIsometry!float identity = MIsometry!float.identity();
    NearbyScratch genScratch;
    scope(exit) {
        genScratch.release();
    }
    NearbyNode[] nearby =
        ensureAndCollectNearby(genScratch, graph, NodeId.ROOT, identity, radius);

    float threshold = coshf(radius + CHUNK_BOUNDING_SPHERE_RADIUS);
    MPoint!float startP = identity * MPoint!float.origin();

    double paramsMs = 0;
    double voxelsMs = 0;
    double populateMs = 0;
    uint generated = 0;
    uint solid = 0;

    foreach (ref nn; nearby) {
        foreach (vIdx; 0 .. 20) {
            Vertex vertex = cast(Vertex) vIdx;
            if (!shouldGenerate(graph, nn, vertex, startP, threshold)) {
                continue;
            }
            ChunkId chunkId = ChunkId(nn.id, vertex);

            double t0 = nowMs();
            ChunkParams params = ChunkParams.create(graph, chunkId);
            double t1 = nowMs();
            VoxelData voxels = generateVoxels(params);
            double t2 = nowMs();
            populateChunk(graph, chunkId, voxels, dimension);
            double t3 = nowMs();

            paramsMs = paramsMs + (t1 - t0);
            voxelsMs = voxelsMs + (t2 - t1);
            populateMs = populateMs + (t3 - t2);
            generated = generated + 1;
            if (voxels.kind == VoxelData.Kind.Solid) {
                solid = solid + 1;
            }
        }
    }

    if (generated == 0) {
        printf("bench-gen dim=%d radius=%.2f no chunks in range\n",
            cast(int) dimension, cast(double) radius);
        return;
    }

    double denseAvgMs = 0;
    if (generated > solid) {
        denseAvgMs = voxelsMs / (generated - solid);
    }

    printf(
        "bench-gen dim=%d radius=%.2f chunks=%u (solid=%u dense=%u)\n",
        cast(int) dimension,
        cast(double) radius,
        generated,
        solid,
        generated - solid,
    );
    printf(
        "  params   total=%.1fms avg=%.3fms\n",
        paramsMs,
        paramsMs / generated,
    );
    printf(
        "  voxels   total=%.1fms avg=%.3fms (dense avg=%.3fms)\n",
        voxelsMs,
        voxelsMs / generated,
        denseAvgMs,
    );
    printf(
        "  populate total=%.1fms avg=%.3fms\n",
        populateMs,
        populateMs / generated,
    );
}

// Headless smoke test + timing of the async worldgen driver: runs the real
// drive() loop (worker threads and all) until every chunk in range is
// populated, then reports chunk count and wall time. The populated count must
// match dumpWorld/benchGen for the same radius.
void benchDrive(float radius, ubyte dimension) {
    Graph graph = Graph.create(dimension);
    MIsometry!float identity = MIsometry!float.identity();
    NearbyScratch scratch;
    NearbyNode[] nearby =
        ensureAndCollectNearby(scratch, graph, NodeId.ROOT, identity, radius);
    WorldgenDriver driver = WorldgenDriver.create();

    double start = nowMs();
    uint idleFrames = 0;
    uint frames = 0;
    while (idleFrames < 3 && frames < 100_000) {
        driver.drive(nearby, identity, radius, graph, dimension, 1);
        frames = frames + 1;
        if (driver.inFlight == 0) {
            idleFrames = idleFrames + 1;
        } else {
            idleFrames = 0;
            sleepMs(1);
        }
    }
    double totalMs = nowMs() - start;

    uint populated = 0;
    foreach (slot; 0 .. graph.slotCount()) {
        foreach (vIdx; 0 .. 20) {
            const(Chunk)* c =
                &graph.container(slot).value.chunks.values[cast(Vertex) vIdx];
            if (c.state == ChunkState.Populated) {
                populated = populated + 1;
            }
        }
    }
    printf(
        "bench-drive dim=%d radius=%.2f populated=%u frames=%u total=%.1fms\n",
        cast(int) dimension,
        cast(double) radius,
        populated,
        frames,
        totalMs,
    );

    // Steady state: everything generated, nothing to do — this is the pure
    // per-frame scan cost the render loop pays forever after.
    enum uint IDLE_ITERS = 200;
    double idleStart = nowMs();
    foreach (iter; 0 .. IDLE_ITERS) {
        driver.drive(nearby, identity, radius, graph, dimension, 1);
    }
    double idleMs = (nowMs() - idleStart) / IDLE_ITERS;
    printf(
        "bench-drive idle scan=%.3fms/frame (%zu nodes)\n",
        idleMs,
        nearby.length,
    );
}

// Headless timing of the per-frame nearby traversal. Builds the graph once,
// then times the alloc-per-call (4-arg) vs reuse-scratch (5-arg) paths over
// `iters` iterations from a fixed node. Deterministic; no window/script.
void benchNearby(float radius, int iters, ubyte dimension) {
    if (iters <= 0) {
        printf("bench-nearby needs a positive iteration count\n");
        return;
    }
    Graph graph = Graph.create(dimension);
    MIsometry!float identity = MIsometry!float.identity();
    NearbyScratch warm;
    size_t nodeCount =
        ensureAndCollectNearby(warm, graph, NodeId.ROOT, identity, radius).length;
    warm.release();

    // A fresh scratch per iteration, so its buffers grow from empty every
    // time. This is the cost the reuse path below avoids.
    double allocStart = nowMs();
    foreach (iter; 0 .. iters) {
        NearbyScratch fresh;
        ensureAndCollectNearby(fresh, graph, NodeId.ROOT, identity, radius);
        fresh.release();
    }
    double allocMs = (nowMs() - allocStart) / iters;

    NearbyScratch scratch;
    scope(exit) {
        scratch.release();
    }
    double reuseStart = nowMs();
    foreach (iter; 0 .. iters) {
        ensureAndCollectNearby(scratch, graph, NodeId.ROOT, identity, radius);
    }
    double reuseMs = (nowMs() - reuseStart) / iters;

    double speedup = 0;
    if (reuseMs > 0) {
        speedup = allocMs / reuseMs;
    }

    printf(
        "bench-nearby dim=%d radius=%.1f nodes=%zu iters=%d\n",
        cast(int) dimension,
        cast(double) radius,
        nodeCount,
        iters,
    );
    printf(
        "  alloc=%.3fms reuse=%.3fms speedup=%.2fx\n",
        allocMs,
        reuseMs,
        speedup,
    );
}
