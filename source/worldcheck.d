module worldcheck;

import core.stdc.math : coshf;
import core.stdc.stdio : FILE, fprintf;
import core.stdc.stdlib : free, malloc;
import client.meshing : Mesher;
import client.streaming : Streamer, populateChunk, resolveMaterials;
import client.structures : StructureProblem, growthProblem, placeWorldStructure;
import client.world : FULL_RADIUS;
import common.array : Array;
import common.clock : nowMilliseconds;
import common.coords : Coords;
import common.dodeca : CHUNK_BOUNDING_SPHERE_RADIUS, VERTEX_COUNT, Vertex, chunkBoundingSphereCenter;
import common.graph : Graph, NodeId;
import common.material : Material;
import common.math : MIsometry, MPoint;
import common.murmur : murmurHash3;
import common.node : Chunk, ChunkSlot, ChunkState, VoxelData;
import common.parallel : Executor;
import common.position : Position;
import common.traversal : NO_DEADLINE, NearbyNode, NearbyScratch;
import common.worldgen.generation : ChunkParams, GeneratedVoxels, Worldgen;
import common.worldgen.structure : altitude, edgeLength;

enum uint DRIVE_NEARBY_VERSION = 1;
enum uint DRIVE_IDLE_ITERATIONS = 200;
enum double DRIVE_BUDGET_MILLISECONDS = 5.0;
enum size_t HASH_HEADER_BYTES = 2;
enum float STRUCTURE_DUMP_RADIUS = 4.5f;

struct ContentHashes {
    ulong[2] materials;
    ulong[2] occupancy;

    static ContentHashes fromVoxels(Vertex vertex, ref const VoxelData voxels, ubyte dimension) {
        size_t cells = cast(size_t) dimension * dimension * dimension;
        ubyte* materialBytes = cast(ubyte*) malloc(HASH_HEADER_BYTES + cells * Material.sizeof);
        ubyte* occupancy = cast(ubyte*) malloc(HASH_HEADER_BYTES + cells);
        Material* materials = cast(Material*)(materialBytes + HASH_HEADER_BYTES);
        materialBytes[0] = vertex;
        materialBytes[1] = dimension;
        occupancy[0] = vertex;
        occupancy[1] = dimension;
        size_t cell = 0;
        foreach (x; 0 .. dimension) {
            foreach (y; 0 .. dimension) {
                foreach (z; 0 .. dimension) {
                    ubyte[3] coords = [cast(ubyte) x, cast(ubyte) y, cast(ubyte) z];
                    materials[cell] = voxels.get(Coords(coords).toIndex(dimension));
                    occupancy[HASH_HEADER_BYTES + cell] = materials[cell] != Material.none;
                    cell += 1;
                }
            }
        }
        ContentHashes result = ContentHashes(murmurHash3(materialBytes[0 .. HASH_HEADER_BYTES + cells * Material.sizeof]), murmurHash3(occupancy[0 .. HASH_HEADER_BYTES + cells]));
        free(materialBytes);
        free(occupancy);
        return result;
    }
}

struct WorldDigest {
    ulong[2] materials;
    ulong[2] occupancy;
    size_t populated;

    static WorldDigest fromGraph(ref const Graph graph) {
        WorldDigest digest;
        foreach (index; 0 .. cast(size_t) graph.nodeCount * VERTEX_COUNT) {
            ChunkSlot slot = ChunkSlot.fromIndex(index);
            const(Chunk)* chunk = graph.chunkAt(slot);
            if (chunk.state == ChunkState.populated) {
                digest.add(ContentHashes.fromVoxels(slot.vertex, chunk.voxels, graph.layout.dimension));
            }
        }
        return digest;
    }

    void add(ContentHashes hashes) {
        materials[0] += hashes.materials[0];
        materials[1] += hashes.materials[1];
        occupancy[0] += hashes.occupancy[0];
        occupancy[1] += hashes.occupancy[1];
        populated += 1;
    }

    void print(FILE* output) const {
        fprintf(output, "digest populated=%zu materials ", populated);
        printHash(output, materials);
        fprintf(output, " occupancy ");
        printHash(output, occupancy);
        fprintf(output, "\n");
    }
}

struct ChunkPass {
    double paramsMs = 0;
    double voxelsMs = 0;
    double denseMs = 0;
    double populateMs = 0;
    uint generated;
    uint solid;
    uint deferred;

    void generate(ref Graph graph, const(NearbyNode)[] nearby, float radius) {
        float threshold = coshf(radius + CHUNK_BOUNDING_SPHERE_RADIUS);
        MPoint!float start = MPoint!float.origin();
        foreach (nearbyNode; nearby) {
            foreach (vertexIndex; 0 .. VERTEX_COUNT) {
                Vertex vertex = cast(Vertex) vertexIndex;
                ChunkSlot slot = ChunkSlot(nearbyNode.slot, vertex);
                MPoint!float chunkCenter = nearbyNode.transform * vertex.chunkBoundingSphereCenter;
                if (graph.chunkAt(slot).state == ChunkState.fresh && !(-start.mip(chunkCenter.vec) > threshold)) {
                    generateChunk(graph, slot);
                }
            }
        }
    }

    void generateChunk(ref Graph graph, ChunkSlot slot) {
        double t0 = nowMilliseconds();
        ChunkParams params = ChunkParams.make(graph, slot.slot, slot.vertex);
        graph.chunkFor(slot).predicted = params.predictOccupancy();
        double t1 = nowMilliseconds();
        GeneratedVoxels result = params.generateVoxels();
        double t2 = nowMilliseconds();
        graph.populateChunk(slot, result);
        double t3 = nowMilliseconds();
        paramsMs += t1 - t0;
        voxelsMs += t2 - t1;
        populateMs += t3 - t2;
        generated += 1;
        if (result.voxels.isSolid()) {
            solid += 1;
        } else {
            denseMs += t2 - t1;
        }
        if (result.hasDeferredMaterials) {
            deferred += 1;
        }
    }
}

uint countDeferred(ref const Graph graph) {
    uint count = 0;
    foreach (index; 0 .. cast(size_t) graph.nodeCount * VERTEX_COUNT) {
        if (graph.chunkAt(ChunkSlot.fromIndex(index)).hasDeferredMaterials) {
            count += 1;
        }
    }
    return count;
}

void resolveAllMaterials(ref Graph graph) {
    foreach (index; 0 .. cast(size_t) graph.nodeCount * VERTEX_COUNT) {
        if (graph.chunkAt(ChunkSlot.fromIndex(index)).hasDeferredMaterials) {
            graph.resolveMaterials(ChunkSlot.fromIndex(index));
        }
    }
}

void generateWorld(ref Graph graph, float radius) {
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(graph, Position.origin(), radius);
    ChunkPass pass;
    pass.generate(graph, nearby, radius);
    graph.resolveAllMaterials();
    scratch.release();
}

void printHash(FILE* output, ulong[2] hash) {
    fprintf(output, "%016llx%016llx", hash[0], hash[1]);
}

void printChunkLine(FILE* output, NodeId node, Vertex vertex, ContentHashes hashes) {
    printHash(output, node.value);
    fprintf(output, " %02u ", cast(uint) vertex);
    printHash(output, hashes.materials);
    fprintf(output, " ");
    printHash(output, hashes.occupancy);
    fprintf(output, "\n");
}

void dumpWorld(FILE* output, float radius, ubyte dimension) {
    Graph graph = terrainGraph(dimension);
    graph.generateWorld(radius);
    foreach (index; 0 .. cast(size_t) graph.nodeCount * VERTEX_COUNT) {
        ChunkSlot slot = ChunkSlot.fromIndex(index);
        const(Chunk)* chunk = graph.chunkAt(slot);
        if (chunk.state == ChunkState.populated) {
            printChunkLine(output, graph.idAt(slot.slot), slot.vertex, ContentHashes.fromVoxels(slot.vertex, chunk.voxels, dimension));
        }
    }
    WorldDigest.fromGraph(graph).print(output);
    graph.release();
}

void printWorldDigest(FILE* output, float radius, ubyte dimension) {
    Graph graph = terrainGraph(dimension);
    graph.generateWorld(radius);
    WorldDigest.fromGraph(graph).print(output);
    graph.release();
}

size_t filledVoxels(ref Graph graph, uint slot) {
    size_t filled = 0;
    foreach (vertexIndex; 0 .. VERTEX_COUNT) {
        GeneratedVoxels generated = ChunkParams.make(graph, slot, cast(Vertex) vertexIndex).generateVoxels();
        foreach (x; 0 .. graph.layout.dimension) {
            foreach (y; 0 .. graph.layout.dimension) {
                foreach (z; 0 .. graph.layout.dimension) {
                    ubyte[3] coords = [cast(ubyte) x, cast(ubyte) y, cast(ubyte) z];
                    if (generated.voxels.get(Coords(coords).toIndex(graph.layout.dimension)) != Material.none) {
                        filled += 1;
                    }
                }
            }
        }
        generated.voxels.release();
    }
    return filled;
}

bool dumpStructure(FILE* output, ubyte dimension, Worldgen worldgen) {
    Graph graph = Graph.make(dimension, worldgen);
    StructureProblem problem = graph.placeWorldStructure();
    if (!problem.isPresent) {
        NearbyScratch scratch;
        NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.anchorSlot), MIsometry!float.identity()), STRUCTURE_DUMP_RADIUS);
        foreach (node; nearby) {
            if (graph.ensureStructureAt(node.slot)) {
                graph.ensureNodeStateAt(node.slot);
                fprintf(output, "altitude=%.3f filled=%zu\n", cast(double) graph.nodeAt(node.slot).state.altitude(), graph.filledVoxels(node.slot));
            }
        }
        scratch.release();
        fprintf(output, "lines=%zu brushes=%u stops=%zu claims=%u edge=%.4f\n", graph.blueprint.lines.length, graph.blueprint.brushCount, graph.blueprint.route.length, graph.blueprint.claimCount,cast(double) edgeLength(graph.layout).value);
        problem = growthProblem(graph);
    }
    if (problem.isPresent) {
        fprintf(output, "%s\n", problem.text.ptr);
    }
    graph.release();
    return !problem.isPresent;
}

bool checkRepaint(FILE* output, ubyte dimension, Worldgen worldgen) {
    Graph graph = Graph.make(dimension, worldgen);
    StructureProblem problem = graph.placeWorldStructure();
    uint differing = 0;
    if (!problem.isPresent) {
        NearbyScratch scratch;
        NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.anchorSlot), MIsometry!float.identity()), STRUCTURE_DUMP_RADIUS);
        Array!ulong painted;
        foreach (node; nearby) {
            if (graph.ensureStructureAt(node.slot)) {
                painted.append(graph.generatedHash(node.slot));
            }
        }
        size_t tiles = graph.blueprint.tiles.length;
        foreach (tile; 0 .. tiles) {
            graph.blueprint.dropTile(cast(uint) tile);
        }
        foreach (slot; 0 .. graph.nodeCount) {
            if (graph.nodeAt(slot).hasBuilding) {
                graph.nodeAt(slot).building.release();
                graph.nodeAt(slot).hasBuilding = false;
            }
        }
        size_t index = 0;
        foreach (node; nearby) {
            if (graph.ensureStructureAt(node.slot)) {
                differing += graph.generatedHash(node.slot) != painted.ptr[index];
                index += 1;
            }
        }
        fprintf(output, "repaint structured=%zu tiles=%zu painted_again=%u differing=%u\n", painted.length, tiles, graph.blueprint.restoredTiles, differing);
        painted.release();
        scratch.release();
        problem = growthProblem(graph);
    }
    if (problem.isPresent) {
        fprintf(output, "%s\n", problem.text.ptr);
    }
    graph.release();
    return !problem.isPresent && differing == 0;
}

ulong generatedHash(ref Graph graph, uint slot) {
    ulong hash = 0;
    foreach (vertexIndex; 0 .. VERTEX_COUNT) {
        GeneratedVoxels generated = ChunkParams.make(graph, slot, cast(Vertex) vertexIndex).generateVoxels();
        hash += ContentHashes.fromVoxels(cast(Vertex) vertexIndex, generated.voxels, graph.layout.dimension).materials[0];
        generated.voxels.release();
    }
    return hash;
}

Graph terrainGraph(ubyte dimension) {
    Graph graph = Graph.make(dimension, Worldgen.makeTerrain());
    StructureProblem problem = graph.placeWorldStructure();
    assert(!problem.isPresent);
    return graph;
}

double averageOf(double total, size_t count) {
    if (count > 0) {
        return total / count;
    } else {
        return 0;
    }
}

void benchGen(FILE* output, float radius, ubyte dimension) {
    Graph graph = terrainGraph(dimension);
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(graph, Position.origin(), radius);
    ChunkPass pass;
    pass.generate(graph, nearby, radius);
    uint dense = pass.generated - pass.solid;
    fprintf(output, "bench-gen dim=%u radius=%.2f chunks=%u solid=%u dense=%u deferred=%u resolved_on_exposure=%u\n", cast(uint) dimension, cast(double) radius, pass.generated, pass.solid, dense, pass.deferred, pass.deferred - graph.countDeferred());
    fprintf(output, "params total=%.1fms avg=%.3fms\n", pass.paramsMs, averageOf(pass.paramsMs, pass.generated));
    fprintf(output, "voxels total=%.1fms avg=%.3fms dense_avg=%.3fms\n", pass.voxelsMs, averageOf(pass.voxelsMs, pass.generated), averageOf(pass.denseMs, dense));
    fprintf(output, "populate total=%.1fms avg=%.3fms\n", pass.populateMs, averageOf(pass.populateMs, pass.generated));
    scratch.release();
    graph.release();
}

void benchMesh(FILE* output, float radius, ubyte dimension) {
    Graph graph = terrainGraph(dimension);
    graph.generateWorld(radius);
    Mesher mesher;
    mesher.setup(dimension);
    uint meshed = 0;
    size_t faces = 0;
    size_t mostFaces = 0;
    double totalMs = 0;
    double slowestMs = 0;
    foreach (index; 0 .. cast(size_t) graph.nodeCount * VERTEX_COUNT) {
        const(Chunk)* chunk = graph.chunkAt(ChunkSlot.fromIndex(index));
        if (chunk.state == ChunkState.populated && !chunk.voxels.isSolid()) {
            double start = nowMilliseconds();
            size_t count = mesher.mesh(graph, ChunkSlot.fromIndex(index)).length;
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
    graph.release();
}

void benchDrive(FILE* output, float radius, ubyte dimension) {
    Graph graph = terrainGraph(dimension);
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(graph, Position.origin(), radius);
    Streamer streamer = Streamer.make();
    uint nodesBefore = graph.nodeCount;
    double start = nowMilliseconds();
    double driveMs = 0;
    uint drives = 0;
    do {
        double driveStart = nowMilliseconds();
        streamer.drive(graph, nearby, MIsometry!float.identity(), radius, DRIVE_NEARBY_VERSION, false, driveStart + DRIVE_BUDGET_MILLISECONDS);
        driveMs += nowMilliseconds() - driveStart;
        drives += 1;
        if (streamer.inFlight > 0) {
            streamer.integrate(graph, true, 0);
        }
    } while (streamer.inFlight > 0 || streamer.scanCursor < nearby.length);
    double totalMs = nowMilliseconds() - start;
    uint populated = 0;
    foreach (index; 0 .. cast(size_t) graph.nodeCount * VERTEX_COUNT) {
        if (graph.chunkAt(ChunkSlot.fromIndex(index)).state == ChunkState.populated) {
            populated += 1;
        }
    }
    fprintf(output, "bench-drive dim=%u radius=%.2f populated=%u nodes=%u->%u drives=%u total=%.1fms drive=%.1fms integrate_and_wait=%.1fms\n", cast(uint) dimension, cast(double) radius, populated, nodesBefore, graph.nodeCount, drives, totalMs, driveMs, totalMs - driveMs);
    double idleStart = nowMilliseconds();
    foreach (_; 0 .. DRIVE_IDLE_ITERATIONS) {
        streamer.drive(graph, nearby, MIsometry!float.identity(), radius, DRIVE_NEARBY_VERSION, false, nowMilliseconds() + DRIVE_BUDGET_MILLISECONDS);
    }
    fprintf(output, "bench-drive idle scan=%.3fms/drive nodes=%zu\n", (nowMilliseconds() - idleStart) / DRIVE_IDLE_ITERATIONS, nearby.length);
    streamer.release();
    scratch.release();
    graph.release();
}

void benchNearby(FILE* output, float radius, uint iterations, ubyte dimension) {
    Graph graph = terrainGraph(dimension);
    NearbyScratch scratch;
    double coldStart = nowMilliseconds();
    size_t nodeCount = scratch.collectPruned(graph, radius).length;
    double coldMs = nowMilliseconds() - coldStart;
    double start = nowMilliseconds();
    foreach (_; 0 .. iterations) {
        scratch.collectPruned(graph, radius);
    }
    fprintf(output, "bench-nearby dim=%u radius=%.1f nodes=%zu graph=%u iterations=%u cold=%.1fms collect=%.3fms\n", cast(uint) dimension, cast(double) radius, nodeCount, graph.nodeCount, iterations, coldMs, (nowMilliseconds() - start) / iterations);    scratch.release();
    graph.release();
}

NearbyNode[] collectPruned(ref NearbyScratch scratch, ref Graph graph, float radius) {
    scratch.begin(graph, Position.origin(), radius, FULL_RADIUS);
    scratch.advance(graph, NO_DEADLINE, Executor.init);
    return scratch.nodes.slice();
}
