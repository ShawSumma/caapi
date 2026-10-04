module worldcheck;

import core.stdc.math : coshf;
import core.stdc.stdio : FILE, fprintf;
import core.stdc.stdlib : free, malloc, qsort;
import core.stdc.string : memcpy;
import client.meshing : Mesher;
import client.worldgen_driver : WorldgenDriver, populateChunk, resolveMaterials;
import common.array : Array;
import common.dodeca : CHUNK_BOUNDING_SPHERE_RADIUS, VERTEX_COUNT, Vertex, chunkBoundingSphereCenter;
import common.graph : Graph;
import common.math : MIsometry, MPoint;
import common.murmur : murmurHash3;
import common.node : Chunk, ChunkSlot, ChunkState, VoxelData;
import common.proto : Position;
import common.traversal : NearbyNode, NearbyScratch, nowMilliseconds;
import common.voxel_math : Coords;
import common.world : Material;
import common.worldgen.generation : ChunkParams, GeneratedVoxels, generateVoxels;

enum uint DRIVE_NEARBY_VERSION = 1;
enum uint DRIVE_IDLE_ITERATIONS = 200;
enum size_t HASH_HEADER_BYTES = 2;

struct ChunkLine {
    ulong[2] node;
    ulong[2] materials;
    ulong[2] occupancy;
    ubyte vertex;
}

struct ContentHashes {
    ulong[2] materials;
    ulong[2] occupancy;
}

struct ChunkPass {
    double paramsMs = 0;
    double voxelsMs = 0;
    double denseMs = 0;
    double populateMs = 0;
    uint generated;
    uint solid;
    uint deferred;
}

ChunkSlot chunkSlotAt(size_t index) {
    return ChunkSlot(cast(uint)(index / VERTEX_COUNT), cast(Vertex)(index % VERTEX_COUNT));
}

uint countDeferred(const(Graph)* graph) {
    uint count = 0;
    foreach (index; 0 .. cast(size_t) graph.nodeCount * VERTEX_COUNT) {
        if (graph.chunkAt(chunkSlotAt(index)).hasDeferredMaterials) {
            count += 1;
        }
    }
    return count;
}

void resolveAllMaterials(Graph* graph) {
    foreach (index; 0 .. cast(size_t) graph.nodeCount * VERTEX_COUNT) {
        if (graph.chunkAt(chunkSlotAt(index)).hasDeferredMaterials) {
            graph.resolveMaterials(chunkSlotAt(index));
        }
    }
}

ContentHashes chunkHashes(ubyte vertex, const(VoxelData)* voxels, ubyte dimension) {
    size_t cells = cast(size_t) dimension * dimension * dimension;
    ubyte* materials = cast(ubyte*) malloc(HASH_HEADER_BYTES + cells * Material.sizeof);
    ubyte* occupancy = cast(ubyte*) malloc(HASH_HEADER_BYTES + cells);
    materials[0] = vertex;
    materials[1] = dimension;
    occupancy[0] = vertex;
    occupancy[1] = dimension;
    size_t cell = 0;
    foreach (x; 0 .. dimension) {
        foreach (y; 0 .. dimension) {
            foreach (z; 0 .. dimension) {
                ubyte[3] coords = [cast(ubyte) x, cast(ubyte) y, cast(ubyte) z];
                Material material = voxels.get(Coords(coords).toIndex(dimension));
                memcpy(materials + HASH_HEADER_BYTES + cell * Material.sizeof, &material, Material.sizeof);
                occupancy[HASH_HEADER_BYTES + cell] = material != Material.Void;
                cell += 1;
            }
        }
    }
    ContentHashes result = ContentHashes(murmurHash3(materials[0 .. HASH_HEADER_BYTES + cells * Material.sizeof]), murmurHash3(occupancy[0 .. HASH_HEADER_BYTES + cells]));
    free(materials);
    free(occupancy);
    return result;
}

void printHash(FILE* output, ulong[2] hash) {
    ubyte[16] bytes;
    memcpy(bytes.ptr, hash.ptr, bytes.length);
    foreach (value; bytes) {
        fprintf(output, "%02x", cast(uint) value);
    }
}

ulong[2] lineHash(ChunkLine line, bool isOccupancy) {
    if (isOccupancy) {
        return line.occupancy;
    } else {
        return line.materials;
    }
}

ulong[2] digest(const(ChunkLine)[] lines, bool isOccupancy) {
    ulong[2]* hashes = cast(ulong[2]*) malloc(lines.length * (ulong[2]).sizeof);
    foreach (i, line; lines) {
        hashes[i] = lineHash(line, isOccupancy);
    }
    ulong[2] result = murmurHash3((cast(ubyte*) hashes)[0 .. lines.length * (ulong[2]).sizeof]);
    free(hashes);
    return result;
}

int compareWords(ulong a, ulong b) {
    if (a < b) {
        return -1;
    } else if (a > b) {
        return 1;
    } else {
        return 0;
    }
}

extern (C) int compareChunkLines(const(void)* left, const(void)* right) {
    const(ChunkLine)* a = cast(const(ChunkLine)*) left;
    const(ChunkLine)* b = cast(const(ChunkLine)*) right;
    immutable int high = compareWords(a.node[0], b.node[0]);
    immutable int low = compareWords(a.node[1], b.node[1]);
    if (high != 0) {
        return high;
    } else if (low != 0) {
        return low;
    } else {
        return cast(int) a.vertex - cast(int) b.vertex;
    }
}

double averageOf(double total, size_t count) {
    if (count > 0) {
        return total / count;
    } else {
        return 0;
    }
}

ChunkPass generateNearby(Graph* graph, const(NearbyNode)[] nearby, float radius) {
    ChunkPass pass;
    float threshold = coshf(radius + CHUNK_BOUNDING_SPHERE_RADIUS);
    MPoint!float start = MPoint!float.origin();
    foreach (nearbyNode; nearby) {
        foreach (vertexIndex; 0 .. VERTEX_COUNT) {
            Vertex vertex = cast(Vertex) vertexIndex;
            ChunkSlot slot = ChunkSlot(nearbyNode.slot, vertex);
            MPoint!float chunkCenter = nearbyNode.transform * vertex.chunkBoundingSphereCenter;
            if (graph.chunkAt(slot).state == ChunkState.Fresh && !(-start.mip(chunkCenter.vec) > threshold)) {
                double t0 = nowMilliseconds();
                ChunkParams params = ChunkParams.make(graph, nearbyNode.slot, vertex, false);
                graph.chunkAt(slot).predicted = params.predictOccupancy();
                double t1 = nowMilliseconds();
                GeneratedVoxels generated = generateVoxels(&params);
                double t2 = nowMilliseconds();
                immutable bool isSolid = generated.voxels.isSolid();
                immutable bool hasDeferredMaterials = generated.hasDeferredMaterials;
                graph.populateChunk(slot, generated);
                double t3 = nowMilliseconds();
                pass.paramsMs += t1 - t0;
                pass.voxelsMs += t2 - t1;
                pass.populateMs += t3 - t2;
                pass.generated += 1;
                if (isSolid) {
                    pass.solid += 1;
                } else {
                    pass.denseMs += t2 - t1;
                }
                if (hasDeferredMaterials) {
                    pass.deferred += 1;
                }
            }
        }
    }
    return pass;
}

void dumpWorld(FILE* output, float radius, ubyte dimension) {
    Graph graph = Graph.make(dimension);
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(&graph, Position.origin(), radius);
    generateNearby(&graph, nearby, radius);
    resolveAllMaterials(&graph);
    Array!ChunkLine lines;
    foreach (index; 0 .. cast(size_t) graph.nodeCount * VERTEX_COUNT) {
        ChunkSlot slot = chunkSlotAt(index);
        const(Chunk)* chunk = graph.chunkAt(slot);
        if (chunk.state == ChunkState.Populated) {
            ContentHashes hashes = chunkHashes(cast(ubyte) slot.vertex, &chunk.voxels, dimension);
            lines.append(ChunkLine(graph.idAt(slot.slot).value, hashes.materials, hashes.occupancy, cast(ubyte) slot.vertex));
        }
    }
    qsort(lines.ptr, lines.length, ChunkLine.sizeof, &compareChunkLines);
    fprintf(output, "dim=%u radius=%.3f nodes=%u nearby=%zu populated=%zu\n", cast(uint) dimension, cast(double) radius, graph.nodeCount, nearby.length, lines.length);
    foreach (line; lines.slice()) {
        fprintf(output, "%016llx%016llx %02u ", line.node[0], line.node[1], cast(uint) line.vertex);
        printHash(output, line.materials);
        fprintf(output, " ");
        printHash(output, line.occupancy);
        fprintf(output, "\n");
    }
    fprintf(output, "digest materials ");
    printHash(output, digest(lines.slice(), false));
    fprintf(output, " occupancy ");
    printHash(output, digest(lines.slice(), true));
    fprintf(output, "\n");
    lines.release();
    scratch.release();
    graph.release();
}

void benchGen(FILE* output, float radius, ubyte dimension) {
    Graph graph = Graph.make(dimension);
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(&graph, Position.origin(), radius);
    ChunkPass pass = generateNearby(&graph, nearby, radius);
    uint dense = pass.generated - pass.solid;
    fprintf(output, "bench-gen dim=%u radius=%.2f chunks=%u solid=%u dense=%u deferred=%u resolved_on_exposure=%u\n", cast(uint) dimension, cast(double) radius, pass.generated, pass.solid, dense, pass.deferred, pass.deferred - countDeferred(&graph));
    fprintf(output, "params total=%.1fms avg=%.3fms\n", pass.paramsMs, averageOf(pass.paramsMs, pass.generated));
    fprintf(output, "voxels total=%.1fms avg=%.3fms dense_avg=%.3fms\n", pass.voxelsMs, averageOf(pass.voxelsMs, pass.generated), averageOf(pass.denseMs, dense));
    fprintf(output, "populate total=%.1fms avg=%.3fms\n", pass.populateMs, averageOf(pass.populateMs, pass.generated));
    scratch.release();
    graph.release();
}

void benchMesh(FILE* output, float radius, ubyte dimension) {
    Graph graph = Graph.make(dimension);
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(&graph, Position.origin(), radius);
    generateNearby(&graph, nearby, radius);
    Mesher mesher;
    mesher.setup(dimension);
    uint meshed = 0;
    size_t faces = 0;
    size_t mostFaces = 0;
    double totalMs = 0;
    double slowestMs = 0;
    foreach (index; 0 .. cast(size_t) graph.nodeCount * VERTEX_COUNT) {
        const(Chunk)* chunk = graph.chunkAt(chunkSlotAt(index));
        if (chunk.state == ChunkState.Populated && !chunk.voxels.isSolid()) {
            double start = nowMilliseconds();
            size_t count = mesher.mesh(&graph, chunkSlotAt(index)).length;
            double elapsed = nowMilliseconds() - start;
            totalMs += elapsed;
            if (elapsed > slowestMs) {
                slowestMs = elapsed;
            }
            if (count > mostFaces) {
                mostFaces = count;
            }
            faces += count;
            meshed += 1;
        }
    }
    fprintf(output, "bench-mesh dim=%u radius=%.2f meshed=%u faces=%zu max_faces=%zu total=%.1fms avg=%.4fms max=%.4fms\n", cast(uint) dimension, cast(double) radius, meshed, faces, mostFaces, totalMs, averageOf(totalMs, meshed), slowestMs);
    mesher.release();
    scratch.release();
    graph.release();
}

void benchDrive(FILE* output, float radius, ubyte dimension) {
    Graph graph = Graph.make(dimension);
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(&graph, Position.origin(), radius);
    WorldgenDriver driver = WorldgenDriver.make(false);
    uint nodesBefore = graph.nodeCount;
    double start = nowMilliseconds();
    double driveMs = 0;
    uint frames = 0;
    do {
        double driveStart = nowMilliseconds();
        driver.drive(nearby, MIsometry!float.identity(), radius, &graph, DRIVE_NEARBY_VERSION, false);
        driveMs += nowMilliseconds() - driveStart;
        frames += 1;
        if (driver.inFlight > 0) {
            driver.integrate(&graph, true, 0);
        }
    } while (driver.inFlight > 0 || driver.scanCursor < nearby.length);
    double totalMs = nowMilliseconds() - start;
    uint populated = 0;
    foreach (index; 0 .. cast(size_t) graph.nodeCount * VERTEX_COUNT) {
        if (graph.chunkAt(chunkSlotAt(index)).state == ChunkState.Populated) {
            populated += 1;
        }
    }
    fprintf(output, "bench-drive dim=%u radius=%.2f populated=%u nodes=%u->%u frames=%u total=%.1fms drive=%.1fms integrate_and_wait=%.1fms\n", cast(uint) dimension, cast(double) radius, populated, nodesBefore, graph.nodeCount, frames, totalMs, driveMs, totalMs - driveMs);
    double idleStart = nowMilliseconds();
    foreach (i; 0 .. DRIVE_IDLE_ITERATIONS) {
        driver.drive(nearby, MIsometry!float.identity(), radius, &graph, DRIVE_NEARBY_VERSION, false);
    }
    fprintf(output, "bench-drive idle scan=%.3fms/frame nodes=%zu\n", (nowMilliseconds() - idleStart) / DRIVE_IDLE_ITERATIONS, nearby.length);
    driver.release();
    scratch.release();
    graph.release();
}

void benchNearby(FILE* output, float radius, uint iterations, ubyte dimension) {
    Graph graph = Graph.make(dimension);
    NearbyScratch scratch;
    size_t nodeCount = scratch.collectAll(&graph, Position.origin(), radius).length;
    double start = nowMilliseconds();
    foreach (i; 0 .. iterations) {
        scratch.collectAll(&graph, Position.origin(), radius);
    }
    fprintf(output, "bench-nearby dim=%u radius=%.1f nodes=%zu iterations=%u collect=%.3fms\n", cast(uint) dimension, cast(double) radius, nodeCount, iterations, (nowMilliseconds() - start) / iterations);
    scratch.release();
    graph.release();
}
