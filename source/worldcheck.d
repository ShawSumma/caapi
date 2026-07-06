module worldcheck;

// Deterministic, headless world-generation dump. Emits one line per generated
// chunk: "<nodeId> <vertex> <hash>", sorted, so a plain diff of two runs points
// at the exact chunk(s) that changed. The per-chunk hash covers the chunk's
// voxel + margin bytes; the GPU mesh is a pure function of those, so an
// unchanged line means an unchanged mesh for that chunk. No aggregate digest.

import std.stdio;
import std.algorithm : sort;
import std.math : cosh;
import core.time : MonoTime;
import std.digest.murmurhash : MurmurHash3;
import common.graph : Graph, NodeId;
import common.node : Chunk, ChunkId, ChunkState, VoxelData;
import common.dodeca : Vertex, CHUNK_BOUNDING_SPHERE_RADIUS, vertexChunkBoundingSphereCenter;
import common.math : MIsometry, MPoint;
import common.traversal : ensureAndCollectNearby, NearbyNode, NearbyScratch;
import common.worldgen : ChunkParams, generateVoxels;
import client.worldgen_driver : populateChunk;

private ubyte[16] chunkHash(ubyte vertex, const ref VoxelData v) {
    MurmurHash3!128 h;
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

private void hex32(ref char[32] buf, const(ubyte)[] d) {
    static immutable digits = "0123456789abcdef";
    foreach (i; 0 .. 16) {
        buf[i * 2] = digits[d[i] >> 4];
        buf[i * 2 + 1] = digits[d[i] & 0xF];
    }
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

void dumpWorld(float radius, ubyte dimension) {
    Graph graph = Graph.create(dimension);
    MIsometry!float identity = MIsometry!float.identity();
    NearbyNode[] nearby = ensureAndCollectNearby(graph, NodeId.ROOT, identity, radius);

    // Generate exactly the chunks the client worldgen driver would (same threshold).
    float threshold = cosh(radius + CHUNK_BOUNDING_SPHERE_RADIUS);
    MPoint!float startP = identity * MPoint!float.origin();
    foreach (ref nn; nearby) {
        foreach (vIdx; 0 .. 20) {
            Vertex vertex = cast(Vertex) vIdx;
            Chunk* c = &graph[nn.id].chunks.values[vertex];
            if (c.state != ChunkState.Fresh) {
                continue;
            }
            MPoint!float chunkCenter = nn.transform * vertexChunkBoundingSphereCenter(vertex);
            if (-startP.mip(chunkCenter.vec) > threshold) {
                continue;
            }
            ChunkId chunkId = ChunkId(nn.id, vertex);
            ChunkParams params = ChunkParams.create(graph, chunkId);
            VoxelData voxels = generateVoxels(params);
            populateChunk(graph, chunkId, voxels, dimension);
        }
    }

    ChunkLine[] lines;
    foreach (ref container; graph.containers) {
        foreach (vIdx; 0 .. 20) {
            const(Chunk)* c = &container.value.chunks.values[cast(Vertex) vIdx];
            if (c.state != ChunkState.Populated) {
                continue;
            }
            lines ~= ChunkLine(
                container.id.value[0], container.id.value[1], cast(ubyte) vIdx,
                chunkHash(cast(ubyte) vIdx, c.voxels));
        }
    }
    sort(lines);

    writefln("# dim=%d radius=%.3f nodes=%d nearby=%d populated=%d", dimension, radius, graph.len, nearby.length, lines.length);
    foreach (ref ln; lines) {
        char[32] hh;
        hex32(hh, ln.hash[]);
        writefln("%016x%016x %02d %s", ln.n0, ln.n1, ln.vertex, hh);
    }
    stdout.flush();
}

// Headless timing of chunk generation. Generates every chunk within `radius`
// of the origin and reports where the time goes: params (enviro factors from
// the graph), voxels (generateVoxels proper), and populate (margin fixups).
void benchGen(float radius, ubyte dimension) {
    Graph graph = Graph.create(dimension);
    MIsometry!float identity = MIsometry!float.identity();
    NearbyNode[] nearby = ensureAndCollectNearby(graph, NodeId.ROOT, identity, radius);

    float threshold = cosh(radius + CHUNK_BOUNDING_SPHERE_RADIUS);
    MPoint!float startP = identity * MPoint!float.origin();

    double paramsMs = 0;
    double voxelsMs = 0;
    double populateMs = 0;
    uint generated = 0;
    uint solid = 0;

    foreach (ref nn; nearby) {
        foreach (vIdx; 0 .. 20) {
            Vertex vertex = cast(Vertex) vIdx;
            Chunk* c = &graph[nn.id].chunks.values[vertex];
            if (c.state != ChunkState.Fresh) {
                continue;
            }
            MPoint!float chunkCenter = nn.transform * vertexChunkBoundingSphereCenter(vertex);
            if (-startP.mip(chunkCenter.vec) > threshold) {
                continue;
            }
            ChunkId chunkId = ChunkId(nn.id, vertex);

            MonoTime t0 = MonoTime.currTime;
            ChunkParams params = ChunkParams.create(graph, chunkId);
            MonoTime t1 = MonoTime.currTime;
            VoxelData voxels = generateVoxels(params);
            MonoTime t2 = MonoTime.currTime;
            populateChunk(graph, chunkId, voxels, dimension);
            MonoTime t3 = MonoTime.currTime;

            paramsMs += (t1 - t0).total!"usecs" / 1000.0;
            voxelsMs += (t2 - t1).total!"usecs" / 1000.0;
            populateMs += (t3 - t2).total!"usecs" / 1000.0;
            generated++;
            if (voxels.kind == VoxelData.Kind.Solid) {
                solid++;
            }
        }
    }

    writefln("bench-gen dim=%d radius=%.2f chunks=%d (solid=%d dense=%d)",
        dimension, radius, generated, solid, generated - solid);
    writefln("  params   total=%.1fms avg=%.3fms", paramsMs, paramsMs / generated);
    writefln("  voxels   total=%.1fms avg=%.3fms (dense avg=%.3fms)",
        voxelsMs, voxelsMs / generated,
        generated > solid ? voxelsMs / (generated - solid) : 0);
    writefln("  populate total=%.1fms avg=%.3fms", populateMs, populateMs / generated);
}

// Headless smoke test + timing of the async worldgen driver: runs the real
// drive() loop (worker threads and all) until every chunk in range is
// populated, then reports chunk count and wall time. The populated count must
// match dumpWorld/benchGen for the same radius.
void benchDrive(float radius, ubyte dimension) {
    import core.thread : Thread;
    import core.time : msecs;
    import client.worldgen_driver : WorldgenDriver;

    Graph graph = Graph.create(dimension);
    MIsometry!float identity = MIsometry!float.identity();
    NearbyScratch scratch;
    NearbyNode[] nearby = ensureAndCollectNearby(scratch, graph, NodeId.ROOT, identity, radius);
    WorldgenDriver driver = WorldgenDriver.create();

    MonoTime start = MonoTime.currTime;
    uint idleFrames = 0;
    uint frames = 0;
    while (idleFrames < 3 && frames < 100_000) {
        driver.drive(nearby, identity, radius, graph, dimension, 1);
        frames++;
        if (driver.inFlight == 0) {
            idleFrames++;
        } else {
            idleFrames = 0;
            Thread.sleep(1.msecs);
        }
    }
    double totalMs = (MonoTime.currTime - start).total!"usecs" / 1000.0;

    uint populated = 0;
    foreach (ref container; graph.containers) {
        foreach (vIdx; 0 .. 20) {
            if (container.value.chunks.values[cast(Vertex) vIdx].state == ChunkState.Populated) {
                populated++;
            }
        }
    }
    writefln("bench-drive dim=%d radius=%.2f populated=%d frames=%d total=%.1fms",
        dimension, radius, populated, frames, totalMs);

    // Steady state: everything generated, nothing to do — this is the pure
    // per-frame scan cost the render loop pays forever after.
    MonoTime idleStart = MonoTime.currTime;
    enum idleIters = 200;
    foreach (_; 0 .. idleIters) {
        driver.drive(nearby, identity, radius, graph, dimension, 1);
    }
    double idleMs = (MonoTime.currTime - idleStart).total!"usecs" / 1000.0 / idleIters;
    writefln("bench-drive idle scan=%.3fms/frame (%d nodes)", idleMs, cast(uint) nearby.length);
}

// Headless timing of the per-frame nearby traversal. Builds the graph once,
// then times the alloc-per-call (4-arg) vs reuse-scratch (5-arg) paths over
// `iters` iterations from a fixed node. Deterministic; no window/script.
void benchNearby(float radius, int iters, ubyte dimension) {
    Graph graph = Graph.create(dimension);
    MIsometry!float identity = MIsometry!float.identity();
    size_t nodeCount = ensureAndCollectNearby(graph, NodeId.ROOT, identity, radius).length;

    MonoTime allocStart = MonoTime.currTime;
    foreach (iter; 0 .. iters) {
        ensureAndCollectNearby(graph, NodeId.ROOT, identity, radius);
    }
    double allocMs = (MonoTime.currTime - allocStart).total!"usecs" / 1000.0 / iters;

    NearbyScratch scratch;
    MonoTime reuseStart = MonoTime.currTime;
    foreach (iter; 0 .. iters) {
        ensureAndCollectNearby(scratch, graph, NodeId.ROOT, identity, radius);
    }
    double reuseMs = (MonoTime.currTime - reuseStart).total!"usecs" / 1000.0 / iters;

    writefln("bench-nearby dim=%d radius=%.1f nodes=%d iters=%d alloc=%.3fms reuse=%.3fms speedup=%.2fx", dimension, radius, nodeCount, iters, allocMs, reuseMs, allocMs / reuseMs);
}
