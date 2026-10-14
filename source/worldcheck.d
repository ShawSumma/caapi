module worldcheck;

import core.stdc.math : coshf, floorf;
import core.stdc.stdio : FILE, fprintf, fputc;
import core.stdc.stdlib : free, malloc;
import base.array : Array;
import base.clock : nowMilliseconds;
import base.hashmap : HashMap;
import base.murmur : murmurHash3;
import base.parallel : Executor;
import client.arrivals : populateChunk, resolveMaterials;
import client.meshing : Mesher;
import client.streaming : Streamer;
import client.structures : StructureProblem, growthProblem, placeWorldStructure;
import client.world : FULL_RADIUS;
import common.graph : Graph, NodeId;
import base.names : ENUM_NAMES;
import common.material : MATERIAL_COUNT;
import common.neighbors : needsMesh;
import common.node : Chunk, ChunkSlot, ChunkState, Voxels, cellIndex;
import common.position : Position;
import common.traversal : NO_DEADLINE, NearbyNode, NearbyScratch;
import common.worldgen.generation : ChunkParams, GeneratedVoxels, SplitMix, Worldgen;
import common.worldgen.sky : ChunkPoint, chunkPointOf;
import common.worldgen.structure : ColumnSpot, SiteFrame, altitude, columnPoint, edgeLength, forwarded, rootSite, sitePlacement, turned;
import plugins.api.api : Material, Turn;
import geometry.honeycomb : CORNER_COUNT, CUBE_RADIUS, Corner, cubeCenter;
import geometry.lorentz : Motion, Point;

enum uint DRIVE_NEARBY_VERSION = 1;
enum uint DRIVE_IDLE_ITERATIONS = 200;
enum double DRIVE_BUDGET_MILLISECONDS = 5.0;
enum size_t HASH_HEADER_BYTES = 2;
enum float STRUCTURE_DUMP_RADIUS = 4.5f;
enum uint SLICE_QUARTERS_AROUND = 4;
enum uint SLICE_QUARTERS_OF_FACE = 5;
enum size_t BENCH_MAP_LIVE = 2_000_000;
enum size_t BENCH_MAP_CHURN = 8_000_000;
enum size_t BENCH_MAP_LOOKUPS = 4_000_000;
enum double NANOSECONDS_PER_MILLISECOND = 1.0e6;

struct ContentHashes {
    ulong[2] materials;
    ulong[2] occupancy;

    static ContentHashes fromVoxels(Corner corner, ref const Voxels voxels, ubyte dimension) {
        size_t cells = cast(size_t) dimension * dimension * dimension;
        ubyte* materialBytes = cast(ubyte*) malloc(HASH_HEADER_BYTES + cells * Material.sizeof);
        ubyte* occupancy = cast(ubyte*) malloc(HASH_HEADER_BYTES + cells);
        Material* materials = cast(Material*)(materialBytes + HASH_HEADER_BYTES);
        materialBytes[0] = corner;
        materialBytes[1] = dimension;
        occupancy[0] = corner;
        occupancy[1] = dimension;
        size_t cell = 0;
        foreach (x; 0 .. dimension) {
            foreach (y; 0 .. dimension) {
                foreach (z; 0 .. dimension) {
                    materials[cell] = voxels.at(cellIndex(dimension, x, y, z));
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
        foreach (index; 0 .. cast(size_t) graph.slotCount * CORNER_COUNT) {
            ChunkSlot slot = ChunkSlot.fromIndex(index);
            const(Chunk)* chunk = graph.chunks.at(slot);
            if (chunk.state == ChunkState.populated) {
                digest.add(ContentHashes.fromVoxels(slot.corner, chunk.voxels, graph.layout.dimension));
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
        float threshold = coshf(radius + CUBE_RADIUS);
        Point!float start = Point!float.origin();
        foreach (nearbyNode; nearby) {
            foreach (cornerIndex; 0 .. CORNER_COUNT) {
                Corner corner = cast(Corner) cornerIndex;
                ChunkSlot slot = ChunkSlot(nearbyNode.slot, corner);
                Point!float chunkCenter = nearbyNode.transform * corner.cubeCenter;
                if (graph.chunks.at(slot).state == ChunkState.fresh && !(start.coshDistance(chunkCenter) > threshold)) {
                    generateChunk(graph, slot);
                }
            }
        }
    }

    void generateChunk(ref Graph graph, ChunkSlot slot) {
        double t0 = nowMilliseconds();
        ChunkParams params = ChunkParams.make(graph.view, slot.slot, slot.corner);
        graph.chunks.writable(slot).predicted = params.predictOccupancy();
        double t1 = nowMilliseconds();
        GeneratedVoxels result = params.generateVoxels();
        double t2 = nowMilliseconds();
        graph.populateChunk(slot, result);
        double t3 = nowMilliseconds();
        paramsMs += t1 - t0;
        voxelsMs += t2 - t1;
        populateMs += t3 - t2;
        generated += 1;
        if (result.voxels.isUniform()) {
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
    foreach (index; 0 .. cast(size_t) graph.slotCount * CORNER_COUNT) {
        if (graph.chunks.at(ChunkSlot.fromIndex(index)).hasDeferredMaterials) {
            count += 1;
        }
    }
    return count;
}

void resolveAllMaterials(ref Graph graph) {
    foreach (index; 0 .. cast(size_t) graph.slotCount * CORNER_COUNT) {
        if (graph.chunks.at(ChunkSlot.fromIndex(index)).hasDeferredMaterials) {
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

void printChunkLine(FILE* output, NodeId node, Corner corner, ContentHashes hashes) {
    printHash(output, node.value);
    fprintf(output, " %02u ", cast(uint) corner);
    printHash(output, hashes.materials);
    fprintf(output, " ");
    printHash(output, hashes.occupancy);
    fprintf(output, "\n");
}

void dumpWorld(FILE* output, float radius, ubyte dimension) {
    Graph graph = terrainGraph(dimension);
    graph.generateWorld(radius);
    foreach (index; 0 .. cast(size_t) graph.slotCount * CORNER_COUNT) {
        ChunkSlot slot = ChunkSlot.fromIndex(index);
        const(Chunk)* chunk = graph.chunks.at(slot);
        if (chunk.state == ChunkState.populated) {
            printChunkLine(output, graph.idAt(slot.slot), slot.corner, ContentHashes.fromVoxels(slot.corner, chunk.voxels, dimension));
        }
    }
    WorldDigest.fromGraph(graph).print(output);
    graph.release();
}

void printMaterialCensus(FILE* output, float radius, ubyte dimension) {
    Graph graph = terrainGraph(dimension);
    graph.generateWorld(radius);
    size_t[MATERIAL_COUNT] counts;
    foreach (index; 0 .. cast(size_t) graph.slotCount * CORNER_COUNT) {
        const(Chunk)* chunk = graph.chunks.at(ChunkSlot.fromIndex(index));
        if (chunk.state == ChunkState.populated) {
            foreach (cell; 0 .. cast(size_t) dimension * dimension * dimension) {
                counts[chunk.voxels.at(cell)] += 1;
            }
        }
    }
    foreach (material, count; counts) {
        if (count > 0 && material != Material.none) {
            fprintf(output, "%.*s %zu\n", cast(int) ENUM_NAMES!Material[material].length, ENUM_NAMES!Material[material].ptr, count);
        }
    }
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
    foreach (cornerIndex; 0 .. CORNER_COUNT) {
        GeneratedVoxels generated = ChunkParams.make(graph.view, slot, cast(Corner) cornerIndex).generateVoxels();
        foreach (x; 0 .. graph.layout.dimension) {
            foreach (y; 0 .. graph.layout.dimension) {
                foreach (z; 0 .. graph.layout.dimension) {
                    if (generated.voxels.at(cellIndex(graph.layout.dimension, x, y, z)) != Material.none) {
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
        NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.anchorSlot), Motion!float.identity()), STRUCTURE_DUMP_RADIUS);
        foreach (node; nearby) {
            if (graph.ensureStructureAt(node.slot)) {
                fprintf(output, "altitude=%.3f filled=%zu\n", cast(double)(*graph.ensureState(node.slot)).altitude(), graph.filledVoxels(node.slot));
            }
        }
        scratch.release();
        fprintf(output, "lines=%zu brushes=%u stops=%zu claims=%u edge=%.4f\n", graph.structures.blueprint.lines.length, graph.structures.blueprint.brushCount, graph.structures.blueprint.route.length, graph.structures.blueprint.claimCount, cast(double) edgeLength(graph.layout).value);
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
        NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.anchorSlot), Motion!float.identity()), STRUCTURE_DUMP_RADIUS);
        Array!ulong painted;
        foreach (node; nearby) {
            if (graph.ensureStructureAt(node.slot)) {
                painted.append(graph.generatedHash(node.slot));
            }
        }
        size_t tiles = graph.structures.blueprint.tiles.length;
        foreach (tile; 0 .. tiles) {
            graph.structures.blueprint.dropTile(cast(uint) tile);
        }
        foreach (slot; 0 .. graph.slotCount) {
            graph.structures.releaseBuilding(slot);
        }
        size_t index = 0;
        foreach (node; nearby) {
            if (graph.ensureStructureAt(node.slot)) {
                differing += graph.generatedHash(node.slot) != painted.ptr[index];
                index += 1;
            }
        }
        fprintf(output, "repaint structured=%zu tiles=%zu painted_again=%u differing=%u\n", painted.length, tiles, graph.structures.blueprint.restoredTiles, differing);
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

bool printSlices(FILE* output, ubyte dimension, Worldgen worldgen, int height) {
    Graph graph = Graph.make(dimension, worldgen);
    StructureProblem problem = graph.placeWorldStructure();
    if (!problem.isPresent) {
        SiteFrame root = rootSite(graph.anchorSlot);
        SiteFrame[2] vertices = [root, forwarded(root, 1)];
        foreach (vertex, first; vertices) {
            SiteFrame around = first;
            foreach (index; 0 .. SLICE_QUARTERS_AROUND) {
                fprintf(output, "vertex %u quarter %u\n", cast(uint) vertex, cast(uint) index);
                graph.printQuarter(output, around, height);
                around = graph.view.turned(around, Turn.right);
            }
        }
        SiteFrame corner = root;
        foreach (index; 0 .. SLICE_QUARTERS_OF_FACE) {
            fprintf(output, "face quarter %u\n", cast(uint) index);
            graph.printQuarter(output, corner, height);
            corner = graph.view.turned(forwarded(corner, 1), Turn.right);
        }
        problem = growthProblem(graph);
    }
    if (problem.isPresent) {
        fprintf(output, "%s\n", problem.text.ptr);
    }
    graph.release();
    return !problem.isPresent;
}

void printQuarter(ref Graph graph, FILE* output, SiteFrame quarter, int height) {
    SiteFrame tower = graph.view.turned(graph.view.turned(quarter, Turn.pitchUp), Turn.rollRight);
    int far = graph.layout.dimension - 1;
    foreach_reverse (y; 0 .. far + 1) {
        foreach (x; 0 .. far + 1) {
            fputc(graph.generatedAt(tower, [x, y, height]) == Material.none ? '.' : '#', output);
        }
        fputc('\n', output);
    }
}

Material generatedAt(ref Graph graph, SiteFrame tower, int[3] cell) {
    Point!float center = sitePlacement(tower, graph.layout) * columnPoint(graph.layout, ColumnSpot(cell[0] + 0.5f, cell[1] + 0.5f, cell[2] + 0.5f));
    Position at = graph.ensureNormalized(Position(graph.idAt(tower.node), Motion!float.shiftTo(center)));
    uint slot = graph.slotOf(at.node);
    ChunkPoint inChunk = chunkPointOf(at.local * Point!float.origin());
    int[3] voxel = void;
    foreach (axis; 0 .. 3) {
        voxel[axis] = cast(int) floorf(graph.layout.cubeToGrid(inChunk.coords[axis]));
    }
    GeneratedVoxels generated = ChunkParams.make(graph.view, slot, inChunk.corner).generateVoxels();
    Material material = generated.voxels.at(cellIndex(graph.layout.dimension, voxel[0], voxel[1], voxel[2]));
    generated.voxels.release();
    return material;
}

ulong generatedHash(ref Graph graph, uint slot) {
    ulong hash = 0;
    foreach (cornerIndex; 0 .. CORNER_COUNT) {
        GeneratedVoxels generated = ChunkParams.make(graph.view, slot, cast(Corner) cornerIndex).generateVoxels();
        hash +=ContentHashes.fromVoxels(cast(Corner) cornerIndex, generated.voxels, graph.layout.dimension).materials[0];
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
    foreach (index; 0 .. cast(size_t) graph.slotCount * CORNER_COUNT) {
        if (graph.needsMesh(ChunkSlot.fromIndex(index))) {
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
    uint nodesBefore = graph.slotCount;
    double start = nowMilliseconds();
    double driveMs = 0;
    uint drives = 0;
    do {
        double driveStart = nowMilliseconds();
        streamer.drive(graph, nearby, Position.origin(), Motion!float.identity(), radius, DRIVE_NEARBY_VERSION, false, driveStart + DRIVE_BUDGET_MILLISECONDS);
        driveMs += nowMilliseconds() - driveStart;
        drives += 1;
        if (streamer.inFlight > 0) {
            streamer.integrate(graph, true, 0);
        }
    } while (streamer.inFlight > 0 || streamer.scanCursor < nearby.length);
    double totalMs = nowMilliseconds() - start;
    uint populated = 0;
    foreach (index; 0 .. cast(size_t) graph.slotCount * CORNER_COUNT) {
        if (graph.chunks.at(ChunkSlot.fromIndex(index)).state == ChunkState.populated) {
            populated += 1;
        }
    }
    fprintf(output, "bench-drive dim=%u radius=%.2f populated=%u nodes=%u->%u drives=%u total=%.1fms drive=%.1fms integrate_and_wait=%.1fms\n", cast(uint) dimension, cast(double) radius, populated, nodesBefore, graph.slotCount, drives, totalMs, driveMs, totalMs - driveMs);
    double idleStart = nowMilliseconds();
    foreach (_; 0 .. DRIVE_IDLE_ITERATIONS) {
        streamer.drive(graph, nearby, Position.origin(), Motion!float.identity(), radius, DRIVE_NEARBY_VERSION, false, nowMilliseconds() + DRIVE_BUDGET_MILLISECONDS);
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
    fprintf(output, "bench-nearby dim=%u radius=%.1f nodes=%zu graph=%u iterations=%u cold=%.1fms collect=%.3fms\n", cast(uint) dimension, cast(double) radius, nodeCount, graph.slotCount, iterations, coldMs, (nowMilliseconds() - start) / iterations);
    scratch.release();
    graph.release();
}

NodeId benchKey(ulong index) {
    return NodeId([SplitMix(index).next(), SplitMix(~index).next()]);
}

// Churns NodeId keys the way the graph's slot map churns while flying: a window of live keys sliding forward.
void benchHashMap(FILE* output) {
    HashMap!(NodeId, uint) map;
    double start = nowMilliseconds();
    foreach (index; 0 .. BENCH_MAP_LIVE) {
        map.insert(benchKey(index), cast(uint) index);
    }
    double filled = nowMilliseconds();
    foreach (index; 0 .. BENCH_MAP_CHURN) {
        map.insert(benchKey(BENCH_MAP_LIVE + index), cast(uint) index);
        map.remove(benchKey(index));
    }
    double churned = nowMilliseconds();
    size_t found = 0;
    SplitMix pick = SplitMix(BENCH_MAP_LIVE);
    foreach (_; 0 .. BENCH_MAP_LOOKUPS) {
        found += map.find(benchKey(BENCH_MAP_CHURN + pick.next() % BENCH_MAP_LIVE)) !is null;
    }
    double hit = nowMilliseconds();
    foreach (index; 0 .. BENCH_MAP_LOOKUPS) {
        found += map.find(benchKey(index)) !is null;
    }
    double missed = nowMilliseconds();
    size_t capacity = map.current.capacity;
    map.release();
    double released = nowMilliseconds();
    fprintf(output, "bench-hashmap live=%zu: fill %.1fns/insert, churn %.1fns/insert+remove, hit %.1fns, miss %.1fns, found %zu of %zu, releasing %zu slots %.1fms\n", BENCH_MAP_LIVE, (filled - start) * NANOSECONDS_PER_MILLISECOND / BENCH_MAP_LIVE, (churned - filled) * NANOSECONDS_PER_MILLISECOND / BENCH_MAP_CHURN, (hit - churned) * NANOSECONDS_PER_MILLISECOND / BENCH_MAP_LOOKUPS, (missed - hit) * NANOSECONDS_PER_MILLISECOND / BENCH_MAP_LOOKUPS, found, BENCH_MAP_LOOKUPS, capacity, released - missed);
}

NearbyNode[] collectPruned(ref NearbyScratch scratch, ref Graph graph, float radius) {
    scratch.begin(graph, Position.origin(), radius, FULL_RADIUS);
    scratch.advance(graph, NO_DEADLINE, Executor.init);
    return scratch.nodes.slice();
}
