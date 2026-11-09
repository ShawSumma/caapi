module worldcheck;

import core.stdc.math : coshf, floorf;
import core.stdc.stdio : FILE, fprintf, fputc;
import core.stdc.stdlib : free, malloc;
import base.array : Array;
import base.clock : Deadline, NANOSECONDS_PER_MILLISECOND, nowMilliseconds;
import base.hashmap : HashMap, Present;
import base.murmur : Hash128, murmurHash3;
import base.names : ENUM_NAMES;
import base.numbers : higherOf;
import base.parallel : Executor;
import base.splitmix : SplitMix;
import base.vector3 : Vec3;
import client.arguments : ExitStatus, exitStatus;
import client.arrivals : populateChunk, resolveMaterials;
import client.meshing : Mesher;
import client.streaming : Pacing, Streamer;
import client.structures : StructureProblem, growthProblem, placeWorldStructure;
import client.world : FULL_RADIUS;
import common.eviction : Evictor, Unloaded;
import common.graph : Graph, NodeId;
import client.game : highestMiningTier;
import client.plugins : registry;
import common.content.check : Reach, checkReach, checkUses, terrainMaterials;
import common.content.content : content;
import common.items : materialNames;
import common.material : MaterialSet, including, joined, materialCount, nameHashOf;
import common.neighbors : needsMesh;
import common.node : Chunk, ChunkSlot, ChunkState, Materials, Voxels, cellIndex;
import common.position : Position;
import common.traversal : NearbyNode, NearbyScratch;
import common.worldgen.blueprint : Blueprint, EdgeUses;
import common.worldgen.generation : ChunkParams, GeneratedVoxels, StructureWorld, Worldgen;
import common.worldgen.horospheres : ChunkPoint, chunkPointOf;
import common.worldgen.store : dropTile;
import common.worldgen.structure : ColumnSpot, SiteFrame, altitude, columnPoint, edgeLength, forwarded, rootSite, sitePlacement, turnSite;
import geometry.honeycomb : CORNER_COUNT, CUBE_RADIUS, Corner, FACE_COUNT, Face, cubeCenter;
import geometry.lorentz : Motion, Point;
import plugins.api.api : MOST_MATERIALS, Material, Turn;

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
enum size_t BENCH_MAP_BATCH = 1024;
enum uint FORGET_STEPS = 16;
enum uint FORGET_SIDE_STRIDE = 5;
enum float FORGET_NEAR_RADIUS = 1.0f;
enum uint FORGET_SWEEPS = 4000;

struct ContentHashes {
    Hash128 materials;
    Hash128 occupancy;

    static ContentHashes fromVoxels(Corner corner, const Voxels voxels, ubyte dimension) {
        size_t cells = cast(size_t) dimension * dimension * dimension;
        ubyte* materialBytes = cast(ubyte*) malloc(HASH_HEADER_BYTES + cells * ulong.sizeof);
        ubyte* occupancy = cast(ubyte*) malloc(HASH_HEADER_BYTES + cells);
        ulong* materials = cast(ulong*)(materialBytes + HASH_HEADER_BYTES);
        materialBytes[0] = corner;
        materialBytes[1] = dimension;
        occupancy[0] = corner;
        occupancy[1] = dimension;
        size_t cell = 0;
        foreach (x; 0 .. dimension) {
            foreach (y; 0 .. dimension) {
                foreach (z; 0 .. dimension) {
                    Material material = voxels.at(cellIndex(dimension, x, y, z));
                    materials[cell] = nameHashOf(material);
                    occupancy[HASH_HEADER_BYTES + cell] = 0;
                    if (material != Material.none) {
                        occupancy[HASH_HEADER_BYTES + cell] = 1;
                    }
                    cell += 1;
                }
            }
        }
        ContentHashes result = ContentHashes(murmurHash3(materialBytes[0 .. HASH_HEADER_BYTES + cells * ulong.sizeof]), murmurHash3(occupancy[0 .. HASH_HEADER_BYTES + cells]));
        free(materialBytes);
        free(occupancy);
        return result;
    }
}

struct WorldDigest {
    Hash128 materials;
    Hash128 occupancy;
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
        materials.first += hashes.materials.first;
        materials.second += hashes.materials.second;
        occupancy.first += hashes.occupancy.first;
        occupancy.second += hashes.occupancy.second;
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
        if (result.materials == Materials.deferred) {
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

void printHash(FILE* output, Hash128 hash) {
    fprintf(output, "%016llx%016llx", hash.first, hash.second);
}

void printChunkLine(FILE* output, NodeId node, Corner corner, ContentHashes hashes) {
    printHash(output, node.value);
    fprintf(output, " %02u ", cast(uint) corner);
    printHash(output, hashes.materials);
    fprintf(output, " ");
    printHash(output, hashes.occupancy);
    fprintf(output, "\n");
}

ExitStatus finishWorld(FILE* output, ref Graph graph) {
    StructureProblem problem = growthProblem(graph);
    printProblem(output, problem);
    graph.release();
    return exitStatus(!problem.isPresent);
}

ExitStatus dumpWorld(FILE* output, float radius, ubyte dimension) {
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
    return finishWorld(output, graph);
}

ExitStatus printMaterialCensus(FILE* output, float radius, ubyte dimension) {
    Graph graph = terrainGraph(dimension);
    graph.generateWorld(radius);
    size_t[MOST_MATERIALS] counts;
    foreach (index; 0 .. cast(size_t) graph.slotCount * CORNER_COUNT) {
        const(Chunk)* chunk = graph.chunks.at(ChunkSlot.fromIndex(index));
        if (chunk.state == ChunkState.populated) {
            foreach (cell; 0 .. cast(size_t) dimension * dimension * dimension) {
                counts[chunk.voxels.at(cell).id] += 1;
            }
        }
    }
    printCounts(output, counts[1 .. materialCount()], 1);
    return finishWorld(output, graph);
}

bool touchesAir(const(Chunk)* chunk, ubyte dimension, Vec3!int cell) {
    foreach (axis; 0 .. 3) {
        foreach (step; [-1, 1]) {
            Vec3!int beside = cell;
            beside[axis] += step;
            if (beside[axis] >= 0 && beside[axis] < dimension && chunk.voxels.at(cellIndex(dimension, beside.x, beside.y, beside.z)) == Material.none) {
                return true;
            }
        }
    }
    return false;
}

ExitStatus printSurfaceCensus(FILE* output, float radius, ubyte dimension) {
    Graph graph = terrainGraph(dimension);
    graph.generateWorld(radius);
    size_t[MOST_MATERIALS] counts;
    foreach (index; 0 .. cast(size_t) graph.slotCount * CORNER_COUNT) {
        const(Chunk)* chunk = graph.chunks.at(ChunkSlot.fromIndex(index));
        if (chunk.state == ChunkState.populated && !chunk.voxels.isUniform()) {
            foreach (x; 0 .. dimension) {
                foreach (y; 0 .. dimension) {
                    foreach (z; 0 .. dimension) {
                        Material material = chunk.voxels.at(cellIndex(dimension, x, y, z));
                        if (material != Material.none && touchesAir(chunk, dimension, Vec3!int(x, y, z))) {
                            counts[material.id] += 1;
                        }
                    }
                }
            }
        }
    }
    printCounts(output, counts[1 .. materialCount()], 1);
    return finishWorld(output, graph);
}

void printCounts(FILE* output, const(size_t)[] counts, uint first) {
    foreach (index, count; counts) {
        if (count > 0) {
            const(char)[] name = materialNames.ptr[first + index];
            fprintf(output, "%.*s %zu\n", cast(int) name.length, name.ptr, count);
        }
    }
}

void printProblem(FILE* output, ref const StructureProblem problem) {
    if (problem.isPresent) {
        fprintf(output, "%s\n", problem.text.ptr);
    }
}

ExitStatus printWorldDigest(FILE* output, float radius, ubyte dimension) {
    Graph graph = terrainGraph(dimension);
    graph.generateWorld(radius);
    WorldDigest.fromGraph(graph).print(output);
    return finishWorld(output, graph);
}

size_t countFilled(ref Graph graph, uint slot) {
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

ExitStatus dumpStructure(FILE* output, ubyte dimension, Worldgen worldgen) {
    Graph graph = Graph.make(dimension, worldgen);
    StructureProblem problem = graph.placeWorldStructure();
    if (!problem.isPresent) {
        NearbyScratch scratch;
        NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.anchorSlot), Motion!float.identity()), STRUCTURE_DUMP_RADIUS);
        foreach (node; nearby) {
            bool needsBuilding = graph.ensureStructureAt(node.slot);
            if (needsBuilding) {
                fprintf(output, "altitude=%.3f filled=%zu\n", cast(double)(*graph.ensureState(node.slot)).altitude(), graph.countFilled(node.slot));
            }
        }
        scratch.release();
        fprintf(output, "lines=%zu brushes=%zu stops=%zu claims=%u edge=%.4f\n", graph.structures.blueprint.lines.length, graph.structures.blueprint.brushTotal(), graph.structures.blueprint.route.length, graph.structures.blueprint.claimCount, cast(double) edgeLength(graph.layout).value);
        problem = growthProblem(graph);
    }
    printProblem(output, problem);
    ExitStatus status = exitStatus(!problem.isPresent);
    graph.release();
    return status;
}

MaterialSet placedBy(const(char)[] name, ubyte dimension, FILE* output) {
    MaterialSet placed;
    Graph graph = Graph.make(dimension, Worldgen.fromStructure(StructureWorld.fromName(name)));
    StructureProblem problem = graph.placeWorldStructure();
    if (problem.isPresent) {
        fprintf(output, "%.*s: ", cast(int) name.length, name.ptr);
        printProblem(output, problem);
    } else {
        NearbyScratch scratch;
        NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.anchorSlot), Motion!float.identity()), STRUCTURE_DUMP_RADIUS);
        foreach (node; nearby) {
            graph.ensureStructureAt(node.slot);
        }
        foreach (material; graph.structures.blueprint.materials.slice()) {
            placed = placed.including(material);
        }
        scratch.release();
    }
    graph.release();
    return placed;
}

ExitStatus checkContent(FILE* output, ubyte dimension) {
    MaterialSet found = terrainMaterials();
    foreach (name; registry().allNames()) {
        found = found.joined(placedBy(name, dimension, output));
    }
    Reach reach = Reach.make(found);
    reach.settle();
    uint problems = cast(uint) content().problems.length + checkReach(reach, output) + checkUses(output);
    if (reach.tier != highestMiningTier()) {
        fprintf(output, "the reachable tools mine tier %u of the %u some block needs\n", reach.tier, highestMiningTier());
        problems += 1;
    }
    reach.release();
    fprintf(output, "content-check: %u problems\n", problems);
    return exitStatus(problems == 0);
}

ExitStatus checkRepaint(FILE* output, ubyte dimension, Worldgen worldgen) {
    Graph graph = Graph.make(dimension, worldgen);
    StructureProblem problem = graph.placeWorldStructure();
    uint differing = 0;
    if (!problem.isPresent) {
        NearbyScratch scratch;
        NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.anchorSlot), Motion!float.identity()), STRUCTURE_DUMP_RADIUS);
        Array!ulong painted;
        foreach (node; nearby) {
            bool needsBuilding = graph.ensureStructureAt(node.slot);
            if (needsBuilding) {
                painted.append(graph.hashGenerated(node.slot));
            }
        }
        size_t tiles = graph.structures.blueprint.tiles.length;
        foreach (tile; 0 .. tiles) {
            if (tile % 2 == 0) {
                graph.dropTile(cast(uint) tile);
            }
        }
        foreach (slot; 0 .. graph.slotCount) {
            graph.structures.releaseBuilding(slot);
        }
        size_t index = 0;
        foreach (node; nearby) {
            bool needsBuilding = graph.ensureStructureAt(node.slot);
            if (needsBuilding) {
                ulong repainted = graph.hashGenerated(node.slot);
                if (repainted != painted.ptr[index]) {
                    differing += 1;
                }
                index += 1;
            }
        }
        fprintf(output, "repaint structured=%zu tiles=%zu painted_again=%u differing=%u\n", painted.length, tiles, graph.structures.blueprint.restoredTiles, differing);
        painted.release();
        scratch.release();
        problem = growthProblem(graph);
    }
    printProblem(output, problem);
    graph.release();
    return exitStatus(!problem.isPresent && differing == 0);
}

struct StructureCounts {
    size_t lines;
    size_t edges;
    size_t pending;
    size_t tiles;

    static StructureCounts of(ref const Graph graph) {
        const(Blueprint)* blueprint = &graph.structures.blueprint;
        size_t pending = 0;
        foreach (ref const id, ref const list; graph.structures.pending) {
            pending += 1;
        }
        return StructureCounts(blueprint.lines.length - blueprint.freeLines.length, blueprint.edgeCount(), pending, blueprint.liveTiles.length + blueprint.droppedTiles.length);
    }
}

void hashStructured(ref Graph graph, const(NearbyNode)[] nearby, ref HashMap!(NodeId, ulong) hashes) {
    foreach (node; nearby) {
        bool needsBuilding = graph.ensureStructureAt(node.slot);
        if (needsBuilding) {
            hashes.insert(graph.idAt(node.slot), graph.hashGenerated(node.slot));
        }
    }
}

ExitStatus checkForget(FILE* output, ubyte dimension, Worldgen worldgen) {
    Graph graph = Graph.make(dimension, worldgen);
    StructureProblem problem = graph.placeWorldStructure();
    uint differing = 0;
    uint forgotten = 0;
    if (!problem.isPresent) {
        NearbyScratch scratch;
        Position anchor = Position(graph.idAt(graph.anchorSlot), Motion!float.identity());
        HashMap!(NodeId, ulong) first;
        graph.hashStructured(scratch.collectAll(graph, anchor, STRUCTURE_DUMP_RADIUS), first);
        StructureCounts painted = StructureCounts.of(graph);
        uint far = graph.anchorSlot;
        foreach (step; 0 .. FORGET_STEPS) {
            uint side = step * FORGET_SIDE_STRIDE;
            while (graph.isParentFace(far, cast(Face)(side % FACE_COUNT))) {
                side += 1;
            }
            far = graph.ensureNeighborSlot(far, cast(Face)(side % FACE_COUNT));
        }
        NearbyScratch away;
        away.collectAll(graph, Position(graph.idAt(far), Motion!float.identity()), FORGET_NEAR_RADIUS);
        Evictor evictor;
        Array!Unloaded unloaded;
        double evicting = nowMilliseconds();
        foreach (_; 0 .. FORGET_SWEEPS) {
            unloaded.clear();
            evictor.sweep(graph, away, null, Point!float.origin(), unloaded, nowMilliseconds());
        }
        evicting = nowMilliseconds() - evicting;
        forgotten = evictor.forgottenTiles;
        StructureCounts left = StructureCounts.of(graph);
        EdgeUses edgeUses = graph.structures.blueprint.edgeUses();
        HashMap!(NodeId, Present) kept;
        size_t structured = 0;
        size_t keptCount = 0;
        foreach (ref const id, ref const hash; first) {
            structured += 1;
            if (graph.slotOf(id).exists) {
                kept.insert(id, Present.init);
                keptCount += 1;
            }
        }
        HashMap!(NodeId, ulong) again;
        graph.hashStructured(scratch.collectAll(graph, anchor, STRUCTURE_DUMP_RADIUS), again);
        uint missing = 0;
        uint keptDiffering = 0;
        foreach (ref const id, ref const hash; first) {
            const(ulong)* repainted = again.find(id);
            if (repainted is null) {
                missing += 1;
            } else if (*repainted != hash) {
                differing += 1;
                if (kept.find(id) !is null) {
                    keptDiffering += 1;
                }
            }
        }
        differing += missing;
        fprintf(output, "forget evicting %u nodes and %u tiles took %.0fms\n", evictor.evicted, evictor.droppedTiles, evicting);
        fprintf(output, "forget structured=%zu (%zu never evicted) forgot=%u of %u dropped tiles,lines %zu->%zu edges %zu->%zu (kept %u, used %u, unused %u) pending %zu->%zu tiles %zu->%zu, differing=%u (%u never evicted, %u missing)\n", structured, keptCount, forgotten, evictor.droppedTiles, painted.lines, left.lines, painted.edges, left.edges, edgeUses.kept, edgeUses.used, edgeUses.unused, painted.pending, left.pending, painted.tiles, left.tiles, differing, keptDiffering, missing);
        kept.release();
        first.release();
        again.release();
        unloaded.release();
        evictor.release();
        away.release();
        scratch.release();
        problem = growthProblem(graph);
    }
    printProblem(output, problem);
    graph.release();
    return exitStatus(!problem.isPresent && differing == 0 && forgotten > 0);
}

ExitStatus printSlices(FILE* output, ubyte dimension, Worldgen worldgen, int height) {
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
                around = graph.view.turnSite(around, Turn.right);
            }
        }
        SiteFrame corner = root;
        foreach (index; 0 .. SLICE_QUARTERS_OF_FACE) {
            fprintf(output, "face quarter %u\n", cast(uint) index);
            graph.printQuarter(output, corner, height);
            corner = graph.view.turnSite(forwarded(corner, 1), Turn.right);
        }
        problem = growthProblem(graph);
    }
    printProblem(output, problem);
    ExitStatus status = exitStatus(!problem.isPresent);
    graph.release();
    return status;
}

void printQuarter(ref Graph graph, FILE* output, SiteFrame quarter, int height) {
    SiteFrame tower = graph.view.turnSite(graph.view.turnSite(quarter, Turn.pitchUp), Turn.rollRight);
    int far = graph.layout.dimension - 1;
    foreach_reverse (y; 0 .. far + 1) {
        foreach (x; 0 .. far + 1) {
            char mark = '#';
            Material generated = graph.generateAt(tower, Vec3!int(x, y, height));
            if (generated == Material.none) {
                mark = '.';
            }
            fputc(mark, output);
        }
        fputc('\n', output);
    }
}

Material generateAt(ref Graph graph, SiteFrame tower, Vec3!int cell) {
    Point!float center = sitePlacement(tower, graph.layout) * columnPoint(graph.layout, ColumnSpot(cell.x + 0.5f, cell.y + 0.5f, cell.z + 0.5f));
    Position at = graph.ensureNormalized(Position(graph.idAt(tower.node), Motion!float.shiftTo(center)));
    uint slot = graph.slotOf(at.node).value;
    ChunkPoint inChunk = chunkPointOf(at.local * Point!float.origin());
    Vec3!int voxel = void;
    foreach (axis; 0 .. 3) {
        voxel[axis] = cast(int) floorf(graph.layout.cubeToGrid(inChunk.coords[axis]));
    }
    GeneratedVoxels generated = ChunkParams.make(graph.view, slot, inChunk.corner).generateVoxels();
    Material material = generated.voxels.at(cellIndex(graph.layout.dimension, voxel.x, voxel.y, voxel.z));
    generated.voxels.release();
    return material;
}

ulong hashGenerated(ref Graph graph, uint slot) {
    ulong hash = 0;
    foreach (cornerIndex; 0 .. CORNER_COUNT) {
        GeneratedVoxels generated = ChunkParams.make(graph.view, slot, cast(Corner) cornerIndex).generateVoxels();
        hash += ContentHashes.fromVoxels(cast(Corner) cornerIndex, generated.voxels, graph.layout.dimension).materials.first;
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
            slowestMs = higherOf(elapsed, slowestMs);
            mostFaces = higherOf(count, mostFaces);
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
        streamer.drive(graph, nearby, Position.origin(), Motion!float.identity(), radius, DRIVE_NEARBY_VERSION, Pacing.budgeted, Deadline.at(driveStart + DRIVE_BUDGET_MILLISECONDS));
        driveMs += nowMilliseconds() - driveStart;
        drives += 1;
        if (streamer.inFlight > 0) {
            streamer.integrate(graph, Deadline.init);
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
        streamer.drive(graph, nearby, Position.origin(), Motion!float.identity(), radius, DRIVE_NEARBY_VERSION, Pacing.budgeted, Deadline.at(nowMilliseconds() + DRIVE_BUDGET_MILLISECONDS));
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
    return NodeId(Hash128(SplitMix(index).next(), SplitMix(~index).next()));
}

struct WorstBatch {
    double start = 0;
    double worst = 0;

    void after(size_t index) {
        if (index % BENCH_MAP_BATCH == BENCH_MAP_BATCH - 1) {
            double now = nowMilliseconds();
            worst = higherOf(now - start, worst);
            start = now;
        }
    }
}

void benchHashMap(FILE* output) {
    HashMap!(NodeId, uint) map;
    double start = nowMilliseconds();
    WorstBatch batch = WorstBatch(start);
    foreach (index; 0 .. BENCH_MAP_LIVE) {
        map.insert(benchKey(index), cast(uint) index);
        batch.after(index);
    }
    double filled = nowMilliseconds();
    batch.start = filled;
    foreach (index; 0 .. BENCH_MAP_CHURN) {
        map.insert(benchKey(BENCH_MAP_LIVE + index), cast(uint) index);
        map.remove(benchKey(index));
        batch.after(index);
    }
    double churned = nowMilliseconds();
    size_t found = 0;
    SplitMix pick = SplitMix(BENCH_MAP_LIVE);
    foreach (_; 0 .. BENCH_MAP_LOOKUPS) {
        if (map.find(benchKey(BENCH_MAP_CHURN + pick.next() % BENCH_MAP_LIVE)) !is null) {
            found += 1;
        }
    }
    double hit = nowMilliseconds();
    foreach (index; 0 .. BENCH_MAP_LOOKUPS) {
        if (map.find(benchKey(index)) !is null) {
            found += 1;
        }
    }
    double missed = nowMilliseconds();
    size_t capacity = map.current.capacity;
    map.release();
    double released = nowMilliseconds();
    fprintf(output, "bench-hashmap live=%zu: fill %.1fns/insert, churn %.1fns/insert+remove, slowest %zu changes %.2fms, hit %.1fns, miss %.1fns, found %zu of %zu, releasing %zu slots %.1fms\n", BENCH_MAP_LIVE, (filled - start) * NANOSECONDS_PER_MILLISECOND / BENCH_MAP_LIVE, (churned - filled) * NANOSECONDS_PER_MILLISECOND / BENCH_MAP_CHURN, BENCH_MAP_BATCH, batch.worst, (hit - churned) * NANOSECONDS_PER_MILLISECOND / BENCH_MAP_LOOKUPS, (missed - hit) * NANOSECONDS_PER_MILLISECOND / BENCH_MAP_LOOKUPS, found, BENCH_MAP_LOOKUPS, capacity, released - missed);
}

NearbyNode[] collectPruned(ref NearbyScratch scratch, ref Graph graph, float radius) {
    scratch.begin(graph, Position.origin(), radius, FULL_RADIUS);
    scratch.advance(graph, Deadline.init, Executor.init);
    return scratch.nodes.slice();
}
