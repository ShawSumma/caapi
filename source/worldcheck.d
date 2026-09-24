module worldcheck;

import core.stdc.math : coshf;
import core.stdc.stdio : FILE, fprintf;
import core.stdc.stdlib : free, malloc, qsort;
import core.stdc.string : memcpy;
import core.sys.posix.time : CLOCK_MONOTONIC, clock_gettime, nanosleep, timespec;
import client.worldgen_driver : WorldgenDriver, createWorldgenDriver, driveWorldgen, populateChunk, releaseWorldgenDriver;
import common.array : Array;
import common.dodeca : CHUNK_BOUNDING_SPHERE_RADIUS, VERTEX_COUNT, Vertex, vertexChunkBoundingSphereCenter;
import common.graph : Graph, ROOT_NODE, createGraph;
import common.math : MIsometry, MPoint;
import common.murmur : murmurHash3;
import common.node : Chunk, ChunkId, ChunkState, VoxelData, VoxelKind;
import common.traversal : NearbyNode, NearbyScratch, ensureAndCollectNearby;
import common.world : Material;
import common.worldgen.generation : ChunkParams, createChunkParams, generateVoxels;

enum size_t UNLIMITED_NODE_CREATION = size_t.max;
enum uint DRIVE_IDLE_FRAMES = 3;
enum uint DRIVE_MAX_FRAMES = 100_000;
enum uint DRIVE_NEARBY_VERSION = 1;
enum uint DRIVE_IDLE_ITERATIONS = 200;
enum long DRIVE_POLL_NANOSECONDS = 1_000_000;
enum double NANOSECONDS_PER_MILLISECOND = 1e6;
enum double MILLISECONDS_PER_SECOND = 1e3;
enum size_t HASH_HEADER_BYTES = 2;

struct ChunkLine {
    ulong[2] node;
    ulong[2] hash;
    ubyte vertex;
}

struct ChunkPass {
    double paramsMs;
    double voxelsMs;
    double populateMs;
    uint generated;
    uint solid;
}

double nowMilliseconds() {
    timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec * MILLISECONDS_PER_SECOND + now.tv_nsec / NANOSECONDS_PER_MILLISECOND;
}

ulong[2] chunkHash(ubyte vertex, const(VoxelData)* voxels) {
    size_t payload = Material.sizeof;
    if (voxels.kind == VoxelKind.Dense) {
        payload = voxels.denseData.length * Material.sizeof;
    }
    ubyte* buffer = cast(ubyte*) malloc(HASH_HEADER_BYTES + payload);
    buffer[0] = vertex;
    buffer[1] = cast(ubyte) voxels.kind;
    if (voxels.kind == VoxelKind.Dense) {
        memcpy(buffer + HASH_HEADER_BYTES, voxels.denseData.ptr, payload);
    } else {
        memcpy(buffer + HASH_HEADER_BYTES, &voxels.solidMaterial, payload);
    }
    ulong[2] result = murmurHash3(buffer[0 .. HASH_HEADER_BYTES + payload]);
    free(buffer);
    return result;
}

int compareWords(ulong a, ulong b) {
    int result = 0;
    if (a < b) {
        result = -1;
    } else if (a > b) {
        result = 1;
    }
    return result;
}

extern (C) int compareChunkLines(const(void)* left, const(void)* right) {
    const(ChunkLine)* a = cast(const(ChunkLine)*) left;
    const(ChunkLine)* b = cast(const(ChunkLine)*) right;
    int result = compareWords(a.node[0], b.node[0]);
    if (result == 0) {
        result = compareWords(a.node[1], b.node[1]);
    }
    if (result == 0) {
        result = cast(int) a.vertex - cast(int) b.vertex;
    }
    return result;
}

ChunkPass generateNearby(Graph* graph, const(NearbyNode)[] nearby, float radius) {
    ChunkPass pass;
    float threshold = coshf(radius + CHUNK_BOUNDING_SPHERE_RADIUS);
    MPoint!float start = MPoint!float.origin();
    foreach (nearbyNode; nearby) {
        foreach (vertexIndex; 0 .. VERTEX_COUNT) {
            Vertex vertex = cast(Vertex) vertexIndex;
            MPoint!float chunkCenter = nearbyNode.transform * vertexChunkBoundingSphereCenter(vertex);
            if (graph.nodeAt(nearbyNode.slot).chunks[vertex].state == ChunkState.Fresh && !(-start.mip(chunkCenter.vec) > threshold)) {
                ChunkId chunkId = ChunkId(nearbyNode.id, vertex);
                double t0 = nowMilliseconds();
                ChunkParams params = createChunkParams(graph, chunkId, false);
                double t1 = nowMilliseconds();
                VoxelData voxels = generateVoxels(&params);
                double t2 = nowMilliseconds();
                bool solid = voxels.isSolid();
                populateChunk(graph, chunkId, voxels);
                double t3 = nowMilliseconds();
                pass.paramsMs += t1 - t0;
                pass.voxelsMs += t2 - t1;
                pass.populateMs += t3 - t2;
                pass.generated += 1;
                if (solid) {
                    pass.solid += 1;
                }
            }
        }
    }
    return pass;
}

void dumpWorld(FILE* output, float radius, ubyte dimension) {
    Graph graph = createGraph(dimension);
    NearbyScratch scratch;
    NearbyNode[] nearby = ensureAndCollectNearby(&scratch, &graph, ROOT_NODE, MIsometry!float.identity(), radius, UNLIMITED_NODE_CREATION);
    generateNearby(&graph, nearby, radius);
    Array!ChunkLine lines;
    foreach (slot; 0 .. graph.nodeCount) {
        foreach (vertexIndex; 0 .. VERTEX_COUNT) {
            const(Chunk)* chunk = &graph.nodeAt(slot).chunks[vertexIndex];
            if (chunk.state == ChunkState.Populated) {
                lines.append(ChunkLine(graph.idAt(slot).value, chunkHash(cast(ubyte) vertexIndex, &chunk.voxels), cast(ubyte) vertexIndex));
            }
        }
    }
    qsort(lines.ptr, lines.length, ChunkLine.sizeof, &compareChunkLines);
    fprintf(output, "dim=%u radius=%.3f nodes=%u nearby=%zu populated=%zu\n", cast(uint) dimension, cast(double) radius, graph.nodeCount, nearby.length, lines.length);
    foreach (line; lines.slice()) {
        ubyte[16] bytes;
        memcpy(bytes.ptr, line.hash.ptr, bytes.length);
        fprintf(output, "%016llx%016llx %02u ", line.node[0], line.node[1], cast(uint) line.vertex);
        foreach (value; bytes) {
            fprintf(output, "%02x", cast(uint) value);
        }
        fprintf(output, "\n");
    }
    lines.release();
    scratch.release();
    graph.release();
}

void benchGen(FILE* output, float radius, ubyte dimension) {
    Graph graph = createGraph(dimension);
    NearbyScratch scratch;
    NearbyNode[] nearby = ensureAndCollectNearby(&scratch, &graph, ROOT_NODE, MIsometry!float.identity(), radius, UNLIMITED_NODE_CREATION);
    ChunkPass pass = generateNearby(&graph, nearby, radius);
    uint dense = pass.generated - pass.solid;
    double denseAverage = 0;
    if (dense > 0) {
        denseAverage = pass.voxelsMs / dense;
    }
    fprintf(output, "bench-gen dim=%u radius=%.2f chunks=%u solid=%u dense=%u\n", cast(uint) dimension, cast(double) radius, pass.generated, pass.solid, dense);
    fprintf(output, "params total=%.1fms avg=%.3fms\n", pass.paramsMs, pass.paramsMs / pass.generated);
    fprintf(output, "voxels total=%.1fms avg=%.3fms dense_avg=%.3fms\n", pass.voxelsMs, pass.voxelsMs / pass.generated, denseAverage);
    fprintf(output, "populate total=%.1fms avg=%.3fms\n", pass.populateMs, pass.populateMs / pass.generated);
    scratch.release();
    graph.release();
}

void benchDrive(FILE* output, float radius, ubyte dimension) {
    Graph graph = createGraph(dimension);
    NearbyScratch scratch;
    NearbyNode[] nearby = ensureAndCollectNearby(&scratch, &graph, ROOT_NODE, MIsometry!float.identity(), radius, UNLIMITED_NODE_CREATION);
    WorldgenDriver driver = createWorldgenDriver(false);
    timespec poll = timespec(0, DRIVE_POLL_NANOSECONDS);
    double start = nowMilliseconds();
    uint idleFrames = 0;
    uint frames = 0;
    while (idleFrames < DRIVE_IDLE_FRAMES && frames < DRIVE_MAX_FRAMES) {
        driveWorldgen(&driver, nearby, MIsometry!float.identity(), radius, &graph, DRIVE_NEARBY_VERSION);
        frames += 1;
        if (driver.inFlight == 0) {
            idleFrames += 1;
        } else {
            idleFrames = 0;
            nanosleep(&poll, null);
        }
    }
    double totalMs = nowMilliseconds() - start;
    uint populated = 0;
    foreach (slot; 0 .. graph.nodeCount) {
        foreach (vertexIndex; 0 .. VERTEX_COUNT) {
            if (graph.nodeAt(slot).chunks[vertexIndex].state == ChunkState.Populated) {
                populated += 1;
            }
        }
    }
    fprintf(output, "bench-drive dim=%u radius=%.2f populated=%u frames=%u total=%.1fms\n", cast(uint) dimension, cast(double) radius, populated, frames, totalMs);
    double idleStart = nowMilliseconds();
    foreach (i; 0 .. DRIVE_IDLE_ITERATIONS) {
        driveWorldgen(&driver, nearby, MIsometry!float.identity(), radius, &graph, DRIVE_NEARBY_VERSION);
    }
    fprintf(output, "bench-drive idle scan=%.3fms/frame nodes=%zu\n", (nowMilliseconds() - idleStart) / DRIVE_IDLE_ITERATIONS, nearby.length);
    releaseWorldgenDriver(&driver);
    scratch.release();
    graph.release();
}

void benchNearby(FILE* output, float radius, uint iterations, ubyte dimension) {
    Graph graph = createGraph(dimension);
    NearbyScratch scratch;
    size_t nodeCount = ensureAndCollectNearby(&scratch, &graph, ROOT_NODE, MIsometry!float.identity(), radius, UNLIMITED_NODE_CREATION).length;
    double start = nowMilliseconds();
    foreach (i; 0 .. iterations) {
        ensureAndCollectNearby(&scratch, &graph, ROOT_NODE, MIsometry!float.identity(), radius, UNLIMITED_NODE_CREATION);
    }
    fprintf(output, "bench-nearby dim=%u radius=%.1f nodes=%zu iterations=%u collect=%.3fms\n", cast(uint) dimension, cast(double) radius, nodeCount, iterations, (nowMilliseconds() - start) / iterations);
    scratch.release();
    graph.release();
}
