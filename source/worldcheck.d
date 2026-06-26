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
    foreach (nodeId, ref container; graph.nodes) {
        foreach (vIdx; 0 .. 20) {
            const(Chunk)* c = &container.value.chunks.values[cast(Vertex) vIdx];
            if (c.state != ChunkState.Populated) {
                continue;
            }
            lines ~= ChunkLine(
                nodeId.value[0], nodeId.value[1], cast(ubyte) vIdx,
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

// Headless timing of pure world generation. For each iteration a fresh graph is
// built (so all chunks are Fresh), then every in-radius chunk is generated; only
// the generation loop is timed. Deterministic; reports total chunks and per-chunk
// cost so optimization work has a stable number to move.
void benchWorldgen(float radius, int iters, ubyte dimension) {
    MIsometry!float identity = MIsometry!float.identity();
    float threshold = cosh(radius + CHUNK_BOUNDING_SPHERE_RADIUS);
    MPoint!float startP = identity * MPoint!float.origin();

    double bestMs = double.max;
    double totalMs = 0;
    long chunks = 0;
    foreach (iter; 0 .. iters) {
        Graph graph = Graph.create(dimension);
        NearbyNode[] nearby = ensureAndCollectNearby(graph, NodeId.ROOT, identity, radius);

        long genChunks = 0;
        MonoTime start = MonoTime.currTime;
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
                genChunks++;
            }
        }
        double ms = (MonoTime.currTime - start).total!"usecs" / 1000.0;
        totalMs += ms;
        if (ms < bestMs) {
            bestMs = ms;
        }
        chunks = genChunks;
    }
    double avgMs = totalMs / iters;
    writefln("bench-worldgen dim=%d radius=%.1f chunks=%d iters=%d avg=%.2fms best=%.2fms per-chunk=%.1fus",
        dimension, radius, chunks, iters, avgMs, bestMs, bestMs * 1000.0 / chunks);
    stdout.flush();
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
