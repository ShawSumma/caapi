module common.worldgen.generation;

import core.bitop : rol;
import core.stdc.math : asinhf, atanf, cosf, coshf, floorf, logf, powf, sinhf, sqrtf, tanf;
import core.stdc.stdlib : abs;
import core.stdc.string : memcpy;
import common.coords : CELL_NEIGHBOR_OFFSETS;
import common.dodeca : SIDE_COUNT, Side, VERTEX_COUNT, Vertex, canonicalSides, chunkGridCenterRadius, isAdjacentTo;
import common.graph : Graph, MAX_PARENTS, NO_SLOT, NodeId, ParentList, childId, sideBit;
import common.material : Material;
import common.math : PI, clamped;
import common.node : ChunkLayout, Occupancy, VoxelData;
import common.worldgen.building : Building;
import common.worldgen.plane : Plane;
import common.worldgen.sky : Ground, Grounds, PLANET, groundsAt;
import common.worldgen.structure : firstSideAmong, ringFaces;
import common.worldgen.terraingen : TERRAIN_SURFACE_THICKNESS, materialTable, nearestLatticePoint, sqr, terraingenVoronoi;

enum WorldgenKind : ubyte {
    terrain,
    plane,
    structure,
}

enum size_t STRUCTURE_NAME_CAPACITY = 256;
enum string TERRAIN_STRUCTURE = "planet";

struct PlaneWorld {
    float tiltRadians;
}

struct StructureWorld {
    char[STRUCTURE_NAME_CAPACITY] text;
    size_t length;

    static StructureWorld fromName(const(char)[] name) {
        assert(name.length <= STRUCTURE_NAME_CAPACITY);
        StructureWorld world = StructureWorld(' ', name.length);
        memcpy(world.text.ptr, name.ptr, name.length);
        return world;
    }

    const(char)[] name() const return {
        return text[0 .. length];
    }
}

struct Worldgen {
    union {
        PlaneWorld plane;
        StructureWorld structure;
    }
    WorldgenKind kind;

    static Worldgen makeTerrain() {
        return Worldgen.init;
    }

    static Worldgen fromPlane(PlaneWorld plane) {
        Worldgen worldgen;
        worldgen.plane = plane;
        worldgen.kind = WorldgenKind.plane;
        return worldgen;
    }

    static Worldgen fromStructure(StructureWorld structure) {
        Worldgen worldgen;
        worldgen.structure = structure;
        worldgen.kind = WorldgenKind.structure;
        return worldgen;
    }

    bool hasPlaneGround() const {
        return kind != WorldgenKind.terrain;
    }

    bool hasStructure() const {
        return kind != WorldgenKind.plane;
    }

    const(char)[] structureName() const return {
        if (kind == WorldgenKind.structure) {
            return structure.name();
        } else {
            return TERRAIN_STRUCTURE;
        }
    }

    float groundTiltRadians() const {
        float tilt = 0;
        final switch (kind) {
            case WorldgenKind.terrain:
            case WorldgenKind.structure:
                break;
            case WorldgenKind.plane:
                tilt = plane.tiltRadians;
                break;
        }
        return tilt;
    }
}

float degreesToRadians(float degrees) {
    return degrees * PI / DEGREES_PER_HALF_TURN;
}

enum TreeKind : ubyte {
    oak,
    birch,
    spruce,
}

struct TreeSpecies {
    Material wood;
    Material leaves;
    ubyte minTrunk;
    ubyte trunkChoices;
}

immutable TreeSpecies[TreeKind.max + 1] TREE_SPECIES = [
    TreeSpecies(Material.oakWood, Material.oakLeaves, 4, 2),
    TreeSpecies(Material.birchWood, Material.birchLeaves, 5, 2),
    TreeSpecies(Material.spruceWood, Material.spruceLeaves, 5, 3),
];

enum NodeStateKind : ubyte {
    sky,
    deepSky,
    land,
    deepLand,
}

enum Material DEFERRED_STAND_IN_MATERIAL = Material.dirt;
enum float TERRAIN_SMOOTHNESS = 10.0f;
enum float ELEVATION_VARIATION = 4.0f;
enum float NOISE_STDDEV = 0.03f;
enum float TERRACE_STRENGTH = 0.4f;
enum float SMALL_TERRACE_SCALE = 5.0f;
enum float BIG_TERRACE_SCALE = 15.0f;
enum float SMALL_TERRACE_LIMITER = 2.0f;
enum float BIG_TERRACE_LIMITER = -1.0f;
enum float SMALL_TERRACE_WEIGHT = 0.6f;
enum float BIG_TERRACE_WEIGHT = 0.4f;
enum float BASE_TREE_DENSITY = 0.05f;
enum float RAINFALL_PER_TREE_DENSITY = 40.0f;
enum float MAX_TREE_DENSITY = 0.3f;
enum ubyte MIN_TREE_DIMENSION = 4;
enum int CANOPY_RADIUS = 2;
enum int CANOPY_CORNER_SPAN = 3;
enum int CANOPY_ABOVE_TRUNK = 1;
enum int SPRUCE_LOWEST_LEAVES = 2;
enum float SPRUCE_TEMPERATURE = -2.0f;
enum ulong BIRCH_ODDS = 3;
enum float DEGREES_PER_HALF_TURN = 180.0f;
enum ulong SPLITMIX_INCREMENT = 0x9e3779b97f4a7c15;
enum ulong SPLITMIX_MULTIPLIER_1 = 0xbf58476d1ce4e5b9;
enum ulong SPLITMIX_MULTIPLIER_2 = 0x94d049bb133111eb;
enum ulong UNIFORM_SEED_MULTIPLIER = 0x517cc1b727220a95;
enum ulong NORMAL_SEED_MULTIPLIER = 0x9e3779b97f4a7c15;
enum ulong CHUNK_HASH_MULTIPLIER = 0x517c_c1b7_2722_0a95;
enum uint RANDOM_FRACTION_SHIFT = 40;
enum float RANDOM_24_BIT_RANGE = 2.0f ^^ 24;
enum float RANDOM_24_BIT_RANGE_PLUS_2 = 2.0f ^^ 24 + 2;
enum ubyte TEST_DIMENSION = 12;

struct SplitMix {
    ulong state;

    ulong next() {
        state += SPLITMIX_INCREMENT;
        ulong z = state;
        z = (z ^ (z >> 30)) * SPLITMIX_MULTIPLIER_1;
        z = (z ^ (z >> 27)) * SPLITMIX_MULTIPLIER_2;
        return z ^ (z >> 31);
    }

    float normal() {
        ulong first = next();
        ulong second = next();
        return boxMuller(first, second);
    }

    float uniform() {
        return (cast(float)(next() >> RANDOM_FRACTION_SHIFT) / RANDOM_24_BIT_RANGE) * 2.0f - 1.0f;
    }
}

struct EnviroFactors {
    float maxElevation = 0;
    float temperature = 0;
    float rainfall = 0;
    float blockiness = 0;

    EnviroFactors variedBy(ulong spice) const {
        SplitMix normalSource = SplitMix(spice ^ (0 * NORMAL_SEED_MULTIPLIER));
        SplitMix temperatureSource = SplitMix(spice ^ (1 * UNIFORM_SEED_MULTIPLIER));
        SplitMix rainfallSource = SplitMix(spice ^ (2 * UNIFORM_SEED_MULTIPLIER));
        SplitMix blockinessSource = SplitMix(spice ^ (3 * UNIFORM_SEED_MULTIPLIER));
        return EnviroFactors(maxElevation + normalSource.normal() * ELEVATION_VARIATION, temperature + temperatureSource.uniform(), rainfall + rainfallSource.uniform(), blockiness + blockinessSource.uniform());
    }

    EnviroFactors continuedFrom(EnviroFactors b, EnviroFactors ab) const {
        return EnviroFactors(maxElevation + (b.maxElevation - ab.maxElevation), temperature + (b.temperature - ab.temperature), rainfall + (b.rainfall - ab.rainfall), blockiness + (b.blockiness - ab.blockiness));
    }
}

struct NodeState {
    EnviroFactors enviro;
    Plane surface;
    Plane reference;
    NodeStateKind kind;

    static NodeState fromParents(ref Graph graph, uint slot) {
        ParentList parents = graph.parents(slot);
        if (parents.count == 0) {
            return NodeState(EnviroFactors.init, Plane.fromSide(Side.a), Plane.fromSide(firstSideAmong(ringFaces(Side.a))), NodeStateKind.land);
        } else {
            NodeState first = graph.nodeAt(parents.links[0].slot).state;
            Side firstSide = parents.links[0].side;
            NodeStateKind kind = first.kind.child(firstSide);
            return NodeState(graph.inheritedEnviro(slot, parents), kind.surface(first.surface, firstSide), first.reference.reflectAcross(firstSide), kind);
        }
    }
}

EnviroFactors inheritedEnviro(ref Graph graph, uint slot, ParentList parents) {
    EnviroFactors first = graph.nodeAt(parents.links[0].slot).state.enviro;
    uint abSlot = graph.sharedParentSlot(parents);
    if (abSlot == NO_SLOT) {
        return first.variedBy(graph.idAt(slot).spice());
    } else {
        EnviroFactors ab = graph.ensureNodeStateAt(abSlot).enviro;
        return first.continuedFrom(graph.nodeAt(parents.links[1].slot).state.enviro, ab);
    }
}

uint sharedParentSlot(ref const Graph graph, ParentList parents) {
    if (parents.count > 1) {
        return graph.neighborSlot(parents.links[0].slot, parents.links[1].side);
    } else {
        return NO_SLOT;
    }
}

NodeStateKind child(NodeStateKind self, Side side) {
    if (self == NodeStateKind.sky && side == Side.a) {
        return NodeStateKind.land;
    } else if (self == NodeStateKind.land && side == Side.a) {
        return NodeStateKind.sky;
    } else if (self == NodeStateKind.sky && !side.isAdjacentTo(Side.a)) {
        return NodeStateKind.deepSky;
    } else if (self == NodeStateKind.land && !side.isAdjacentTo(Side.a)) {
        return NodeStateKind.deepLand;
    } else {
        return self;
    }
}

Plane surface(NodeStateKind kind, Plane parentSurface, Side parentSide) {
    if (kind == NodeStateKind.land) {
        return Plane.fromSide(Side.a);
    } else if (kind == NodeStateKind.sky) {
        return -Plane.fromSide(Side.a);
    } else {
        return parentSurface.reflectAcross(parentSide);
    }
}

struct ValueRange {
    float low;
    float high;

    static ValueRange fromValues(float[8] values) {
        ValueRange result = ValueRange(values[0], values[0]);
        foreach (value; values[1 .. 8]) {
            if (value < result.low) {
                result.low = value;
            }
            if (value > result.high) {
                result.high = value;
            }
        }
        return result;
    }
}

struct UniformChunk {
    Material material;
    bool isProven;
}

struct ChunkIncidentEnviroFactors {
    float[8] maxElevations;
    float[8] temperatures;
    float[8] rainfalls;
    float[8] blockinesses;

    static ChunkIncidentEnviroFactors make(ref Graph graph, uint slot, Vertex vertex) {
        Side[3] sides = vertex.canonicalSides;
        ChunkIncidentEnviroFactors result;
        graph.corners.focus(graph.idAt(slot));
        graph.virtuals.clear();
        foreach (corner; 0 .. 8) {
            ushort crossed = 0;
            foreach (axis; 0 .. 3) {
                if ((corner & (4 >> axis)) != 0) {
                    crossed |= sideBit(sides[axis]);
                }
            }
            if (!graph.corners.has(crossed)) {
                NodeRef first = graph.crossedIf(NodeRef(slot, 0), sides[0], (corner & 4) != 0);
                NodeRef second = graph.crossedIf(first, sides[1], (corner & 2) != 0);
                NodeRef third = graph.crossedIf(second, sides[2], (corner & 1) != 0);
                graph.corners.store(crossed, graph.enviroOf(third));
            }
            EnviroFactors enviro = graph.corners.values[crossed];
            result.maxElevations[corner] = enviro.maxElevation;
            result.temperatures[corner] = enviro.temperature;
            result.rainfalls[corner] = enviro.rainfall;
            result.blockinesses[corner] = enviro.blockiness;
        }
        return result;
    }
}

// The enviro across a set of commuting sides depends only on the node it starts from, so it holds for as long as
// requests keep coming from the same node, which they do for the twenty chunks of a node.
struct CornerCache {
    EnviroFactors[1 << SIDE_COUNT] values;
    uint[1 << SIDE_COUNT] stamps;
    NodeId base;
    uint generation = 1;

    void focus(NodeId node) {
        if (node != base) {
            base = node;
            generation += 1;
        }
    }

    bool has(ushort crossed) const {
        return stamps[crossed] == generation;
    }

    void store(ushort crossed, EnviroFactors enviro) {
        values[crossed] = enviro;
        stamps[crossed] = generation;
    }
}

// A node that does not exist yet, worked out the way Graph.insertChildSlot and NodeState.fromParents would create it,
// so terrain can read the enviro of nodes past the loaded region without creating and later evicting them.
struct VirtualNode {
    NodeRef[MAX_PARENTS] parents;
    Side[MAX_PARENTS] sides;
    uint count;
    ushort parentSides;
    NodeId id;
    EnviroFactors enviro;
}

struct NodeRef {
    uint slot;
    uint index;

    bool isVirtual() const {
        return slot == NO_SLOT;
    }
}

NodeRef crossedIf(ref Graph graph, NodeRef node, Side side, bool isCrossed) {
    if (isCrossed) {
        return graph.neighborRef(node, side);
    } else {
        return node;
    }
}

NodeRef neighborRef(ref Graph graph, NodeRef node, Side side) {
    if (!node.isVirtual()) {
        uint existing = graph.neighborSlot(node.slot, side);
        if (existing != NO_SLOT) {
            return NodeRef(existing, 0);
        } else {
            return graph.virtualChild(node, side);
        }
    } else if ((graph.virtuals.ptr[node.index].parentSides & sideBit(side)) != 0) {
        return graph.virtualParent(node, side);
    } else {
        return graph.virtualChild(node, side);
    }
}

NodeRef virtualParent(ref Graph graph, NodeRef node, Side side) {
    const(VirtualNode)* virtual = &graph.virtuals.ptr[node.index];
    uint index = 0;
    while (virtual.sides[index] != side) {
        index += 1;
    }
    return virtual.parents[index];
}

ushort parentSidesOf(ref const Graph graph, NodeRef node) {
    if (node.isVirtual()) {
        return graph.virtuals.ptr[node.index].parentSides;
    } else {
        return graph.nodeAt(node.slot).parentSides;
    }
}

NodeId idOf(ref const Graph graph, NodeRef node) {
    if (node.isVirtual()) {
        return graph.virtuals.ptr[node.index].id;
    } else {
        return graph.idAt(node.slot);
    }
}

EnviroFactors enviroOf(ref Graph graph, NodeRef node) {
    if (node.isVirtual()) {
        return graph.virtuals.ptr[node.index].enviro;
    } else {
        return graph.ensureNodeStateAt(node.slot).enviro;
    }
}

NodeRef virtualChild(ref Graph graph, NodeRef parent, Side side) {
    VirtualNode made;
    foreach (candidateIndex; 0 .. SIDE_COUNT) {
        Side candidate = cast(Side) candidateIndex;
        if (candidate == side || (candidate.isAdjacentTo(side) && (graph.parentSidesOf(parent) & sideBit(candidate)) != 0)) {
            if (candidate == side) {
                made.parents[made.count] = parent;
            } else {
                made.parents[made.count] = graph.neighborRef(graph.neighborRef(parent, candidate), side);
            }
            made.sides[made.count] = candidate;
            made.parentSides |= sideBit(candidate);
            made.count += 1;
        }
    }
    made.id = childId(graph.idOf(made.parents[0]), made.sides[0]);
    EnviroFactors first = graph.enviroOf(made.parents[0]);
    if (made.count > 1 && graph.isLinked(made.parents[0], made.sides[1])) {
        made.enviro = first.continuedFrom(graph.enviroOf(made.parents[1]), graph.enviroOf(graph.neighborRef(made.parents[0], made.sides[1])));
    } else {
        made.enviro = first.variedBy(made.id.spice());
    }
    graph.virtuals.append(made);
    return NodeRef(NO_SLOT, cast(uint)(graph.virtuals.length - 1));
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.makeTerrain());
    foreach (side; 0 .. SIDE_COUNT) {
        uint neighbor = graph.ensureNeighborSlot(graph.anchorSlot, cast(Side) side);
        foreach (outer; 0 .. SIDE_COUNT) {
            graph.ensureNeighborSlot(neighbor, cast(Side) outer);
        }
    }
    uint virtualCorners = 0;
    foreach (slot; 0 .. graph.nodeCount) {
        foreach (vertexIndex; 0 .. VERTEX_COUNT) {
            Vertex vertex = cast(Vertex) vertexIndex;
            uint live = graph.liveCount;
            ChunkIncidentEnviroFactors computed = ChunkIncidentEnviroFactors.make(graph, slot, vertex);
            assert(graph.liveCount == live);
            virtualCorners += cast(uint) graph.virtuals.length;
            Side[3] sides = vertex.canonicalSides;
            foreach (corner; 0 .. 8) {
                uint at = slot;
                foreach (axis; 0 .. 3) {
                    if ((corner & (4 >> axis)) != 0) {
                        at = graph.ensureNeighborSlot(at, sides[axis]);
                    }
                }
                EnviroFactors created = graph.ensureNodeStateAt(at).enviro;
                assert(computed.maxElevations[corner] == created.maxElevation && computed.temperatures[corner] == created.temperature);
                assert(computed.rainfalls[corner] == created.rainfall && computed.blockinesses[corner] == created.blockiness);
            }
        }
    }
    assert(virtualCorners > 0);
    graph.release();
}

bool isLinked(ref const Graph graph, NodeRef node, Side side) {
    if (node.isVirtual()) {
        return (graph.virtuals.ptr[node.index].parentSides & sideBit(side)) != 0;
    } else {
        return graph.neighborSlot(node.slot, side) != NO_SLOT;
    }
}

const(Building)* buildingIfPresent(ref Graph graph, uint slot) {
    if (graph.ensureStructureAt(slot)) {
        return graph.ensureBuildingAt(slot);
    } else {
        return null;
    }
}

struct ChunkParams {
    const(Building)* building;
    ulong nodeSpice;
    Grounds grounds;
    ChunkIncidentEnviroFactors env;
    Plane reference;
    float slopeTangent;
    float slopeSecant;
    ChunkLayout layout;
    Vertex chunk;
    bool hasStructure;
    bool isResolvingMaterials;

    static ChunkParams make(ref Graph graph, uint slot, Vertex vertex) {
        NodeState state = *graph.ensureNodeStateAt(slot);
        return ChunkParams(
            graph.buildingIfPresent(slot),
            graph.idAt(slot).spice(),
            graph.groundsAt(slot),
            ChunkIncidentEnviroFactors.make(graph, slot, vertex),
            state.reference,
            tanf(graph.worldgen.groundTiltRadians()),
            1.0f / cosf(graph.worldgen.groundTiltRadians()),
            graph.layout,
            vertex,
            graph.ensureStructureAt(slot),
            false,
        );
    }

    ubyte dimension() const {
        return layout.dimension;
    }

    ref const(Ground) ground(uint index) const return {
        return grounds.items[index];
    }

    ValueRange altitudes(uint index) const {
        float center = ground(index).surface.distanceToChunk(chunk, [0.5f, 0.5f, 0.5f]);
        return ValueRange(center - chunkGridCenterRadius(), center + chunkGridCenterRadius());
    }

    bool isTilted(uint index) const {
        return index == PLANET && slopeTangent != 0;
    }

    float groundLevelAt(uint index, float[3] coord) const {
        float height = ground(index).surface.distanceToChunk(chunk, coord);
        if (!isTilted(index)) {
            return height;
        } else {
            float across = asinhf(sinhf(reference.distanceToChunk(chunk, coord)) / coshf(height));
            return atanf(sinhf(height)) + slopeTangent * across;
        }
    }

    ValueRange groundRange(uint index) const {
        float center = groundLevelAt(index, [0.5f, 0.5f, 0.5f]);
        float radius = chunkGridCenterRadius();
        if (isTilted(index)) {
            radius = radius * slopeSecant;
        }
        return ValueRange(center - radius, center + radius);
    }

    float terrainCeiling(uint index) const {
        if (ground(index).isFlat) {
            return 0;
        } else {
            return (ValueRange.fromValues(env.maxElevations).high + terrainElevationSlack()) / TERRAIN_SMOOTHNESS;
        }
    }

    bool isClearOf(uint index) const {
        return groundRange(index).low > terrainCeiling(index);
    }

    bool isFullOf(uint index) const {
        float highest = groundRange(index).high;
        if (ground(index).isFlat) {
            return highest < 0;
        } else {
            return isProvenBelowTerrain(highest);
        }
    }

    bool isClearOfAll() const {
        uint index = 0;
        while (index < grounds.count && isClearOf(index)) {
            index += 1;
        }
        return index == grounds.count;
    }

    bool isFullOfAny() const {
        uint index = 0;
        while (index < grounds.count && !isFullOf(index)) {
            index += 1;
        }
        return index < grounds.count;
    }

    bool isProvenClear() const {
        return !hasStructure && isClearOfAll();
    }

    bool isProvenBelowTerrain(float highest) const {
        return (ValueRange.fromValues(env.maxElevations).low - terraceElevationBound()) / TERRAIN_SMOOTHNESS > highest;
    }

    Occupancy predictOccupancy() const {
        if (hasStructure) {
            return Occupancy.unknown;
        } else if (isClearOfAll()) {
            return Occupancy.empty;
        } else if (isFullOfAny()) {
            return Occupancy.full;
        } else {
            return Occupancy.unknown;
        }
    }

    UniformChunk provenUniformMaterial(float highestVoxel) const {
        ValueRange elevations = ValueRange.fromValues(env.maxElevations);
        float lowestTerrain = elevations.low - terrainElevationSlack();
        float highestTerrain = elevations.high + terrainElevationSlack();
        float depth = lowestTerrain / TERRAIN_SMOOTHNESS - highestVoxel;
        if (depth > TERRAIN_SURFACE_THICKNESS) {
            const(Material)[] table = materialTable(lowestTerrain, depth);
            ValueRange rains = ValueRange.fromValues(env.rainfalls);
            ValueRange temperatures = ValueRange.fromValues(env.temperatures);
            float climateSlack = noiseBound();
            uint cell = nearestLatticePoint(rains.low - climateSlack, temperatures.low - climateSlack);
            if (materialTable(highestTerrain, depth).ptr == table.ptr && nearestLatticePoint(rains.low - climateSlack, temperatures.high + climateSlack) == cell && nearestLatticePoint(rains.high + climateSlack, temperatures.low - climateSlack) == cell && nearestLatticePoint(rains.high + climateSlack, temperatures.high + climateSlack) == cell) {
                return UniformChunk(table[cell], true);
            } else {
                return UniformChunk(Material.none, false);
            }
        } else {
            return UniformChunk(Material.none, false);
        }
    }

    GeneratedVoxels generateVoxels() const {
        TerrainGenerator generator = TerrainGenerator(VoxelData.fromMaterial(Material.none), this, SplitMix(hash(nodeSpice, chunk)), false);
        foreach (index; 0 .. grounds.count) {
            if (ground(index).isFlat) {
                generator.generateFlat(index);
            } else {
                generator.generateTerrain(index);
                generator.generateTrees(index);
            }
        }
        generator.generateStructure();
        generator.voxels.compressUniform(dimension);
        generator.voxels.initializeMargins(dimension);
        return GeneratedVoxels(generator.voxels, generator.hasDeferredMaterials);
    }
}

struct GeneratedVoxels {
    VoxelData voxels;
    bool hasDeferredMaterials;
}

struct TerrainGenerator {
    VoxelData voxels;
    ChunkParams params;
    SplitMix rng;
    bool hasDeferredMaterials;

    void generateTerrain(uint ground) {
        ubyte dimension = params.dimension;
        ValueRange altitudes = params.altitudes(ground);
        UniformChunk uniform = params.provenUniformMaterial(altitudes.high);
        if (altitudes.low <= params.terrainCeiling(ground)) {
            if (uniform.isProven) {
                fillEmpty(uniform.material);
            } else if (!params.isResolvingMaterials && !params.hasStructure && params.grounds.count == 1 && params.isProvenBelowTerrain(altitudes.high)) {
                voxels = VoxelData.fromMaterial(DEFERRED_STAND_IN_MATERIAL);
                hasDeferredMaterials = true;
            } else {
                foreach (x; 0 .. dimension) {
                    foreach (y; 0 .. dimension) {
                        foreach (z; 0 .. dimension) {
                            generateTerrainVoxel(ground, params.layout.cellCenter([x, y, z]), voxelIndex(dimension, x, y, z));
                        }
                    }
                }
            }
        }
    }

    void fillEmpty(Material material) {
        if (voxels.isSolidVoid()) {
            voxels = VoxelData.fromMaterial(material);
        } else if (!voxels.isSolid()) {
            ubyte dimension = params.dimension;
            foreach (x; 0 .. dimension) {
                foreach (y; 0 .. dimension) {
                    foreach (z; 0 .. dimension) {
                        setIfEmpty([x, y, z], material);
                    }
                }
            }
        }
    }

    void generateFlat(uint ground) {
        ubyte dimension = params.dimension;
        ValueRange range = params.groundRange(ground);
        if (range.high < 0) {
            fillEmpty(Material.dirt);
        } else if (range.low <= 0) {
            foreach (x; 0 .. dimension) {
                foreach (y; 0 .. dimension) {
                    foreach (z; 0 .. dimension) {
                        if (params.groundLevelAt(ground, params.layout.cellCenter([x, y, z])) < 0) {
                            setIfEmpty([x, y, z], Material.dirt);
                        }
                    }
                }
            }
        }
    }

    void generateStructure() {
        if (params.hasStructure) {
            ubyte dimension = params.dimension;
            foreach (x; 0 .. dimension) {
                foreach (y; 0 .. dimension) {
                    foreach (z; 0 .. dimension) {
                        size_t index = voxelIndex(dimension, x, y, z);
                        Material existing = voxels.get(index);
                        Material material = params.building.materialAt(params.chunk, [x, y, z], existing);
                        if (material != existing) {
                            voxels.toDense(dimension)[index] = material;
                        }
                    }
                }
            }
        }
    }

    void generateTerrainVoxel(uint ground, float[3] center, size_t index) {
        float[3] trilerpCoords = trilerpCoordsOf(center);
        float rain = trilerp(params.env.rainfalls, trilerpCoords) + rng.normal() * NOISE_STDDEV;
        float temperature = trilerp(params.env.temperatures, trilerpCoords) + rng.normal() * NOISE_STDDEV;
        float voxelElevation = params.ground(ground).surface.distanceToChunk(params.chunk, center);
        float elevationPreNoise = terrainElevation(params.env, center, voxelElevation);
        float distancePreNoise = elevationPreNoise / TERRAIN_SMOOTHNESS - voxelElevation;
        float elevation = elevationPreNoise + TERRAIN_SMOOTHNESS * (rng.normal() * NOISE_STDDEV);
        float distance = surfaceDistance(distancePreNoise, elevation / TERRAIN_SMOOTHNESS - voxelElevation);
        if (distance >= 0.0f && voxels.get(index) == Material.none) {
            voxels.toDense(params.dimension)[index] = terraingenVoronoi(elevation, rain, temperature, distance);
        }
    }

    void generateTrees(uint ground) {
        ubyte dimension = params.dimension;
        if (!voxels.isSolid() && dimension > MIN_TREE_DIMENSION) {
            float density = clamped(BASE_TREE_DENSITY + params.env.rainfalls[0] / RAINFALL_PER_TREE_DENSITY, 0.0f, MAX_TREE_DENSITY);
            float temperature = meanOf(params.env.temperatures);
            uint interior = dimension - 2;
            uint candidateCount = cast(uint)(cast(float)(interior * interior * interior) * density);
            foreach (_; 0 .. candidateCount) {
                int x = cast(int)(1 + (rng.next() % interior));
                int y = cast(int)(1 + (rng.next() % interior));
                int z = cast(int)(1 + (rng.next() % interior));
                ulong roll = rng.next();
                placeTree(ground, [x, y, z], treeKind(temperature, roll));
            }
        }
    }

    void placeTree(uint ground, int[3] base, TreeKind kind) {
        ubyte dimension = params.dimension;
        int upDirection = params.ground(ground).surface.risingNeighbor(params.chunk, params.layout, base);
        int[3] up = CELL_NEIGHBOR_OFFSETS[upDirection];
        bool isBaseEmpty = voxels.get(voxelIndex(dimension, base[0], base[1], base[2])) == Material.none;
        bool isAboveEmpty = voxels.get(voxelIndex(dimension, base[0] + up[0], base[1] + up[1], base[2] + up[2])) == Material.none;
        if (isBaseEmpty && isAboveEmpty && isGroundMaterial(voxels.get(voxelIndex(dimension, base[0] - up[0], base[1] - up[1], base[2] - up[2])))) {
            TreeSpecies species = TREE_SPECIES[kind];
            ulong roll = rng.next();
            TreeFrame frame = TreeFrame.fromUp(base, upDirection, cast(int)(species.minTrunk + roll % species.trunkChoices));
            if (frame.fitsWithin(dimension)) {
                growTree(frame, kind);
            }
        }
    }

    void growTree(TreeFrame frame, TreeKind kind) {
        TreeSpecies species = TREE_SPECIES[kind];
        foreach (level; 0 .. frame.trunk) {
            setIfEmpty(frame.cell(level, 0, 0), species.wood);
        }
        foreach (level; 0 .. frame.top + 1) {
            foreach (i; -CANOPY_RADIUS .. CANOPY_RADIUS + 1) {
                foreach (j; -CANOPY_RADIUS .. CANOPY_RADIUS + 1) {
                    if (isLeaf(kind, frame.trunk, level, i, j)) {
                        setIfEmpty(frame.cell(level, i, j), species.leaves);
                    }
                }
            }
        }
    }

    void setIfEmpty(int[3] cell, Material material) {
        size_t index = voxelIndex(params.dimension, cell[0], cell[1], cell[2]);
        if (voxels.get(index) == Material.none) {
            voxels.toDense(params.dimension)[index] = material;
        }
    }
}

struct TreeFrame {
    int[3] base;
    int[3] up;
    size_t across;
    size_t along;
    int trunk;
    int top;

    static TreeFrame fromUp(int[3] base, int upDirection, int trunk) {
        size_t axis = upDirection / 2;
        return TreeFrame(base, CELL_NEIGHBOR_OFFSETS[upDirection], (axis + 1) % 3, (axis + 2) % 3, trunk, trunk + CANOPY_ABOVE_TRUNK);
    }

    int[3] cell(int level, int i, int j) const {
        int[3] result = [base[0] + up[0] * level, base[1] + up[1] * level, base[2] + up[2] * level];
        result[across] += i;
        result[along] += j;
        return result;
    }

    bool fitsWithin(ubyte dimension) const {
        return isInChunk(cell(0, -CANOPY_RADIUS, -CANOPY_RADIUS), dimension) && isInChunk(cell(top, CANOPY_RADIUS, CANOPY_RADIUS), dimension);
    }
}

bool isInChunk(int[3] cell, ubyte dimension) {
    return cell[0] >= 0 && cell[0] < dimension && cell[1] >= 0 && cell[1] < dimension && cell[2] >= 0 && cell[2] < dimension;
}

TreeKind treeKind(float temperature, ulong roll) {
    if (temperature < SPRUCE_TEMPERATURE) {
        return TreeKind.spruce;
    } else if (roll % BIRCH_ODDS == 0) {
        return TreeKind.birch;
    } else {
        return TreeKind.oak;
    }
}

bool isLeaf(TreeKind kind, int trunk, int level, int i, int j) {
    int spread = chebyshevLength(i, j);
    int span = abs(i) + abs(j);
    bool isWide = spread <= CANOPY_RADIUS && span <= CANOPY_CORNER_SPAN;
    if (kind == TreeKind.spruce) {
        return spruceLeaf(trunk, level, span, isWide);
    } else if (level == trunk - 2 || level == trunk - 1) {
        return isWide;
    } else if (level == trunk) {
        return spread <= 1;
    } else if (level == trunk + 1) {
        return span <= 1;
    } else {
        return false;
    }
}

bool spruceLeaf(int trunk, int level, int span, bool isWide) {
    if (level == trunk + 1) {
        return false;
    } else if (level == trunk) {
        return span == 0;
    } else if (level == trunk - 1) {
        return span <= 1;
    } else if (level >= SPRUCE_LOWEST_LEAVES && (trunk - level) % 2 == 0) {
        return isWide;
    } else if (level >= SPRUCE_LOWEST_LEAVES) {
        return span <= 1;
    } else {
        return false;
    }
}

int chebyshevLength(int i, int j) {
    if (abs(i) > abs(j)) {
        return abs(i);
    } else {
        return abs(j);
    }
}

float meanOf(float[8] values) {
    float sum = 0;
    foreach (value; values) {
        sum += value;
    }
    return sum / values.length;
}

float surfaceDistance(float distancePreNoise, float distanceWithNoise) {
    if (distancePreNoise > 0.0f && distanceWithNoise > 0.0f) {
        return distanceWithNoise;
    } else if (distancePreNoise > 0.0f) {
        return 0.0f;
    } else {
        return distancePreNoise;
    }
}

float terrainElevationSlack() {
    return terraceElevationBound() + TERRAIN_SMOOTHNESS * noiseBound();
}

float terraceElevationBound() {
    return (SMALL_TERRACE_WEIGHT * SMALL_TERRACE_SCALE + BIG_TERRACE_WEIGHT * BIG_TERRACE_SCALE) * TERRACE_STRENGTH;
}

float noiseBound() {
    return NOISE_STDDEV * sqrtf(2.0f * logf(RANDOM_24_BIT_RANGE_PLUS_2));
}

bool isGroundMaterial(Material material) {
    return material == Material.dirt || material == Material.grass || material == Material.mudGrass || material == Material.lushGrass || material == Material.tanGrass || material == Material.coarseGrass;
}

float serp(float v0, float v1, float t, float threshold) {
    if (t < threshold) {
        return v0;
    } else if (t < 1.0f - threshold) {
        float s = (t - threshold) / ((1.0f - threshold) - threshold);
        return v0 * (1.0f - s) + v1 * s;
    } else {
        return v1;
    }
}

float terracingDiff(float elevationRaw, float blockiness, float scale, float strength, float limiter) {
    float threshold = strength / (1.0f + powf(2.0f, limiter - blockiness));
    float elevationFloor = floorf(elevationRaw / scale);
    float elevationRemainder = elevationRaw / scale - elevationFloor;
    return scale * elevationFloor + serp(0.0f, scale, elevationRemainder, threshold) - elevationRaw;
}

size_t voxelIndex(ubyte dimension, int x, int y, int z) {
    size_t stride = dimension + 2;
    return (x + 1) + (y + 1) * stride + (z + 1) * stride * stride;
}

float lerp(float v0, float v1, float s) {
    return v0 * (1.0f - s) + v1 * s;
}

float bilerp(float v00, float v01, float v10, float v11, float tx, float ty) {
    return lerp(lerp(v00, v01, tx), lerp(v10, v11, tx), ty);
}

float[3] trilerpCoordsOf(float[3] center) {
    return [(1.0f - center[0]) * 0.5f, (1.0f - center[1]) * 0.5f, (1.0f - center[2]) * 0.5f];
}

float terrainElevation(ref const ChunkIncidentEnviroFactors env, float[3] center, float voxelElevation) {
    float[3] coords = trilerpCoordsOf(center);
    float elevationPreTerracing = trilerp(env.maxElevations, coords);
    float blockiness = trilerp(env.blockinesses, coords);
    float strength = TERRACE_STRENGTH / (1.0f + sqr(voxelElevation));
    float terracingSmall = terracingDiff(elevationPreTerracing, blockiness, SMALL_TERRACE_SCALE, strength, SMALL_TERRACE_LIMITER);
    float terracingBig = terracingDiff(elevationPreTerracing, blockiness, BIG_TERRACE_SCALE, strength, BIG_TERRACE_LIMITER);
    return elevationPreTerracing + SMALL_TERRACE_WEIGHT * terracingSmall + BIG_TERRACE_WEIGHT * terracingBig;
}

float trilerp(float[8] values, float[3] t) {
    float front = bilerp(values[0], values[4], values[2], values[6], t[0], t[1]);
    float back = bilerp(values[1], values[5], values[3], values[7], t[0], t[1]);
    return lerp(front, back, t[2]);
}

float boxMuller(ulong first, ulong second) {
    float u1 = cast(float)((first >> RANDOM_FRACTION_SHIFT) + 1) / RANDOM_24_BIT_RANGE_PLUS_2;
    float u2 = cast(float)(second >> RANDOM_FRACTION_SHIFT) / RANDOM_24_BIT_RANGE;
    return sqrtf(-2.0f * logf(u1)) * cosf(2.0f * PI * u2);
}

ulong hash(ulong a, ulong b) {
    return (rol(a, 5) ^ b) * CHUNK_HASH_MULTIPLIER;
}
