module common.worldgen.generation;

import core.bitop : rol;
import core.stdc.math : cosf, floorf, logf, powf, sqrtf;
import common.dodeca : Side, Vertex, canonicalSides, chunkGridCenterRadius, isAdjacentTo;
import common.graph : Graph, NO_SLOT, ParentList;
import common.math : PI;
import common.node : Occupancy, VoxelData;
import common.world : Material;
import common.worldgen.plane : Plane;
import common.worldgen.terraingen : TERRAIN_SURFACE_THICKNESS, materialTable, nearestLatticePoint, sqr, terraingenVoronoi;

enum NodeStateKind : ubyte {
    Sky,
    DeepSky,
    Land,
    DeepLand,
}

enum NodeStateRoad : ubyte {
    East,
    DeepEast,
    West,
    DeepWest,
}

enum Material DEFERRED_STAND_IN_MATERIAL = Material.Dirt;
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
enum float ROAD_HALF_WIDTH = 0.3f;
enum float ROAD_CENTER_HALF_WIDTH = 0.15f;
enum float ROAD_CLEARANCE = 0.9f;
enum float ROAD_THICKNESS = 0.075f;
enum float RAINFALL_PER_TREE_DENSITY = 100.0f;
enum float MAX_TREE_DENSITY = 0.5f;
enum ubyte MIN_TREE_DIMENSION = 4;
enum uint TRUSS_CRITERIA = 2;
enum int NO_GROUND_DIRECTION = -1;
enum ulong SPLITMIX_INCREMENT = 0x9e3779b97f4a7c15;
enum ulong SPLITMIX_MULTIPLIER_1 = 0xbf58476d1ce4e5b9;
enum ulong SPLITMIX_MULTIPLIER_2 = 0x94d049bb133111eb;
enum ulong UNIFORM_SEED_MULTIPLIER = 0x517cc1b727220a95;
enum ulong NORMAL_SEED_MULTIPLIER = 0x9e3779b97f4a7c15;
enum ulong CHUNK_HASH_MULTIPLIER = 0x517c_c1b7_2722_0a95;
enum uint RANDOM_FRACTION_SHIFT = 40;
enum float RANDOM_24_BIT_RANGE = 2.0f ^^ 24;
enum float RANDOM_24_BIT_RANGE_PLUS_2 = 2.0f ^^ 24 + 2;

immutable int[3][6] TREE_NEIGHBOR_OFFSETS = [
    [-1, 0, 0],
    [1, 0, 0],
    [0, -1, 0],
    [0, 1, 0],
    [0, 0, -1],
    [0, 0, 1],
];

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
    NodeStateKind kind;
    NodeStateRoad road;

    static NodeState fromParents(Graph* graph, uint slot) {
        ParentList parents = graph.parents(slot);
        if (parents.count == 0) {
            return NodeState(EnviroFactors.init, Plane.fromSide(Side.A), NodeStateKind.Land, NodeStateRoad.West);
        } else {
            const(NodeState)* first = &graph.nodeAt(parents.links[0].slot).state;
            Side firstSide = parents.links[0].side;
            NodeStateKind kind = first.kind.child(firstSide);
            return NodeState(inheritedEnviro(graph, slot, &parents), kind.surface(first.surface, firstSide), kind, first.road.child(firstSide));
        }
    }
}

EnviroFactors inheritedEnviro(Graph* graph, uint slot, const(ParentList)* parents) {
    const(NodeState)* first = &graph.nodeAt(parents.links[0].slot).state;
    uint abSlot = sharedParentSlot(graph, parents);
    if (abSlot == NO_SLOT) {
        return first.enviro.variedBy(graph.idAt(slot).spice());
    } else {
        EnviroFactors ab = graph.ensureNodeStateAt(abSlot).enviro;
        return first.enviro.continuedFrom(graph.nodeAt(parents.links[1].slot).state.enviro, ab);
    }
}

uint sharedParentSlot(const(Graph)* graph, const(ParentList)* parents) {
    if (parents.count > 1) {
        return graph.neighborSlot(parents.links[0].slot, parents.links[1].side);
    } else {
        return NO_SLOT;
    }
}

NodeStateKind child(NodeStateKind self, Side side) {
    if (self == NodeStateKind.Sky && side == Side.A) {
        return NodeStateKind.Land;
    } else if (self == NodeStateKind.Land && side == Side.A) {
        return NodeStateKind.Sky;
    } else if (self == NodeStateKind.Sky && !side.isAdjacentTo(Side.A)) {
        return NodeStateKind.DeepSky;
    } else if (self == NodeStateKind.Land && !side.isAdjacentTo(Side.A)) {
        return NodeStateKind.DeepLand;
    } else {
        return self;
    }
}

Plane surface(NodeStateKind kind, Plane parentSurface, Side parentSide) {
    if (kind == NodeStateKind.Land) {
        return Plane.fromSide(Side.A);
    } else if (kind == NodeStateKind.Sky) {
        return -Plane.fromSide(Side.A);
    } else {
        return parentSurface.reflectAcross(parentSide);
    }
}

NodeStateRoad child(NodeStateRoad self, Side side) {
    if (self == NodeStateRoad.East && side == Side.B) {
        return NodeStateRoad.West;
    } else if (self == NodeStateRoad.West && side == Side.B) {
        return NodeStateRoad.East;
    } else if (self == NodeStateRoad.East && !side.isAdjacentTo(Side.B)) {
        return NodeStateRoad.DeepEast;
    } else if (self == NodeStateRoad.West && !side.isAdjacentTo(Side.B)) {
        return NodeStateRoad.DeepWest;
    } else {
        return self;
    }
}

struct ValueRange {
    float low;
    float high;
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

    static ChunkIncidentEnviroFactors make(Graph* graph, uint slot, Vertex vertex) {
        Side[3] sides = vertex.canonicalSides;
        ChunkIncidentEnviroFactors result;
        foreach (corner; 0 .. 8) {
            uint first = crossedIf(graph, slot, sides[0], (corner & 4) != 0);
            uint second = crossedIf(graph, first, sides[1], (corner & 2) != 0);
            uint third = crossedIf(graph, second, sides[2], (corner & 1) != 0);
            EnviroFactors enviro = graph.ensureNodeStateAt(third).enviro;
            result.maxElevations[corner] = enviro.maxElevation;
            result.temperatures[corner] = enviro.temperature;
            result.rainfalls[corner] = enviro.rainfall;
            result.blockinesses[corner] = enviro.blockiness;
        }
        return result;
    }
}

uint crossedIf(Graph* graph, uint slot, Side side, bool isCrossed) {
    if (isCrossed) {
        return graph.ensureNeighborSlot(slot, side);
    } else {
        return slot;
    }
}

struct ChunkParams {
    ulong nodeSpice;
    ChunkIncidentEnviroFactors env;
    Plane surface;
    ubyte dimension;
    Vertex chunk;
    bool isRoad;
    bool isRoadSupport;
    bool isFlat;
    bool isResolvingMaterials;

    static ChunkParams make(Graph* graph, uint slot, Vertex vertex, bool isFlat) {
        const(NodeState)* state = graph.ensureNodeStateAt(slot);
        immutable bool isOnRoadLine = state.road == NodeStateRoad.East || state.road == NodeStateRoad.West;
        ChunkParams params;
        params.dimension = graph.layout.dimension;
        params.chunk = vertex;
        params.env = ChunkIncidentEnviroFactors.make(graph, slot, vertex);
        params.surface = state.surface;
        params.isRoad = state.kind == NodeStateKind.Sky && isOnRoadLine;
        params.isRoadSupport = (state.kind == NodeStateKind.Land || state.kind == NodeStateKind.DeepLand) && isOnRoadLine;
        params.isFlat = isFlat;
        params.nodeSpice = graph.idAt(slot).spice();
        return params;
    }

    ValueRange altitudes() const {
        float center = surface.distanceToChunk(chunk, [0.5f, 0.5f, 0.5f]);
        return ValueRange(center - chunkGridCenterRadius(), center + chunkGridCenterRadius());
    }

    float terrainCeiling() const {
        if (isFlat) {
            return 0;
        } else {
            return (valueRange(env.maxElevations).high + terrainElevationSlack()) / TERRAIN_SMOOTHNESS;
        }
    }

    bool isProvenClear() const {
        return isProvenClearAt(altitudes().low);
    }

    bool isProvenClearAt(float lowest) const {
        if (!isFlat && isRoad) {
            return lowest > terrainCeiling() && lowest > ROAD_THICKNESS;
        } else if (!isFlat && isRoadSupport) {
            return false;
        } else {
            return lowest > terrainCeiling();
        }
    }

    bool isProvenBelowTerrain(float highest) const {
        return (valueRange(env.maxElevations).low - terraceElevationBound()) / TERRAIN_SMOOTHNESS > highest;
    }

    Occupancy predictOccupancy() const {
        ValueRange range = altitudes();
        if (isProvenClearAt(range.low)) {
            return Occupancy.empty;
        } else if (isFlat && range.high < 0) {
            return Occupancy.full;
        } else if (!isFlat && !isRoad && isProvenBelowTerrain(range.high)) {
            return Occupancy.full;
        } else {
            return Occupancy.unknown;
        }
    }

    VoxelData flatVoxels() const {
        if (altitudes().high < 0) {
            return VoxelData.solid(Material.Dirt);
        } else if (isProvenClear()) {
            return VoxelData.solid(Material.Void);
        } else {
            VoxelData voxels = VoxelData.solid(Material.Void);
            foreach (x; 0 .. dimension) {
                foreach (y; 0 .. dimension) {
                    foreach (z; 0 .. dimension) {
                        if (surface.distanceToChunk(chunk, voxelCenter(dimension, x, y, z)) < 0) {
                            voxels.dataMut(dimension)[voxelIndex(dimension, x, y, z)] = Material.Dirt;
                        }
                    }
                }
            }
            voxels.compressUniform(dimension);
            voxels.initializeMargins(dimension);
            return voxels;
        }
    }

    UniformChunk provenUniformMaterial(float highestVoxel) const {
        ValueRange elevations = valueRange(env.maxElevations);
        float lowestTerrain = elevations.low - terrainElevationSlack();
        float highestTerrain = elevations.high + terrainElevationSlack();
        float depth = lowestTerrain / TERRAIN_SMOOTHNESS - highestVoxel;
        if (depth > TERRAIN_SURFACE_THICKNESS) {
            const(Material)[] table = materialTable(lowestTerrain, depth);
            ValueRange rains = valueRange(env.rainfalls);
            ValueRange temperatures = valueRange(env.temperatures);
            float climateSlack = noiseBound();
            uint cell = nearestLatticePoint(rains.low - climateSlack, temperatures.low - climateSlack);
            if (materialTable(highestTerrain, depth).ptr == table.ptr && nearestLatticePoint(rains.low - climateSlack, temperatures.high + climateSlack) == cell && nearestLatticePoint(rains.high + climateSlack, temperatures.low - climateSlack) == cell && nearestLatticePoint(rains.high + climateSlack, temperatures.high + climateSlack) == cell) {
                return UniformChunk(table[cell], true);
            } else {
                return UniformChunk(Material.Void, false);
            }
        } else {
            return UniformChunk(Material.Void, false);
        }
    }
}

struct GeneratedVoxels {
    VoxelData voxels;
    bool hasDeferredMaterials;
}

struct TerrainGenerator {
    VoxelData voxels;
    const(ChunkParams)* params;
    SplitMix rng;
    bool hasDeferredMaterials;

    void generateTerrain() {
        ubyte dimension = params.dimension;
        ValueRange altitudes = params.altitudes();
        UniformChunk uniform = params.provenUniformMaterial(altitudes.high);
        if (altitudes.low > params.terrainCeiling()) {
            voxels = VoxelData.solid(Material.Void);
        } else if (uniform.isProven) {
            voxels = VoxelData.solid(uniform.material);
        } else if (!params.isResolvingMaterials && !params.isRoad && params.isProvenBelowTerrain(altitudes.high)) {
            voxels = VoxelData.solid(DEFERRED_STAND_IN_MATERIAL);
            hasDeferredMaterials = true;
        } else {
            foreach (x; 0 .. dimension) {
                foreach (y; 0 .. dimension) {
                    foreach (z; 0 .. dimension) {
                        generateTerrainVoxel(voxelCenter(dimension, x, y, z), voxelIndex(dimension, x, y, z));
                    }
                }
            }
        }
    }

    void generateTerrainVoxel(float[3] center, size_t index) {
        float[3] trilerpCoords = [
            (1.0f - center[0]) * 0.5f,
            (1.0f - center[1]) * 0.5f,
            (1.0f - center[2]) * 0.5f,
        ];
        float rain = trilerp(params.env.rainfalls, trilerpCoords) + rng.normal() * NOISE_STDDEV;
        float temperature = trilerp(params.env.temperatures, trilerpCoords) + rng.normal() * NOISE_STDDEV;
        float elevationPreTerracing = trilerp(params.env.maxElevations, trilerpCoords);
        float blockiness = trilerp(params.env.blockinesses, trilerpCoords);
        float voxelElevation = params.surface.distanceToChunk(params.chunk, center);
        float strength = TERRACE_STRENGTH / (1.0f + sqr(voxelElevation));
        float terracingSmall = terracingDiff(elevationPreTerracing, blockiness, SMALL_TERRACE_SCALE, strength, SMALL_TERRACE_LIMITER);
        float terracingBig = terracingDiff(elevationPreTerracing, blockiness, BIG_TERRACE_SCALE, strength, BIG_TERRACE_LIMITER);
        float elevationPreNoise = elevationPreTerracing + SMALL_TERRACE_WEIGHT * terracingSmall + BIG_TERRACE_WEIGHT * terracingBig;
        float distancePreNoise = elevationPreNoise / TERRAIN_SMOOTHNESS - voxelElevation;
        float elevation = elevationPreNoise + TERRAIN_SMOOTHNESS * (rng.normal() * NOISE_STDDEV);
        float distance = surfaceDistance(distancePreNoise, elevation / TERRAIN_SMOOTHNESS - voxelElevation);
        if (distance >= 0.0f) {
            voxels.dataMut(params.dimension)[index] = terraingenVoronoi(elevation, rain, temperature, distance);
        }
    }

    void generateRoad() {
        Plane plane = -Plane.fromSide(Side.B);
        ubyte dimension = params.dimension;
        foreach (x; 0 .. dimension) {
            foreach (y; 0 .. dimension) {
                foreach (z; 0 .. dimension) {
                    float[3] center = voxelCenter(dimension, x, y, z);
                    float horizontalDistance = plane.distanceToChunk(params.chunk, center);
                    float elevation = params.surface.distanceToChunk(params.chunk, center);
                    if (!(horizontalDistance > ROAD_HALF_WIDTH || elevation > ROAD_CLEARANCE)) {
                        voxels.dataMut(dimension)[voxelIndex(dimension, x, y, z)] = roadMaterial(elevation, horizontalDistance);
                    }
                }
            }
        }
    }

    void generateRoadSupport() {
        Plane plane = -Plane.fromSide(Side.B);
        ubyte dimension = params.dimension;
        foreach (x; 0 .. dimension) {
            foreach (y; 0 .. dimension) {
                foreach (z; 0 .. dimension) {
                    size_t index = voxelIndex(dimension, x, y, z);
                    if (voxels.get(index) == Material.Void && isTrussAt(dimension, x, y, z) && !(plane.distanceToChunk(params.chunk, voxelCenter(dimension, x, y, z)) > ROAD_HALF_WIDTH)) {
                        voxels.dataMut(dimension)[index] = Material.WoodPlanks;
                    }
                }
            }
        }
    }

    void generateTrees() {
        ubyte dimension = params.dimension;
        if (!voxels.isSolid() && dimension > MIN_TREE_DIMENSION) {
            float density = clamped(params.env.rainfalls[0] / RAINFALL_PER_TREE_DENSITY, 0.0f, MAX_TREE_DENSITY);
            uint interior = dimension - 2;
            uint candidateCount = cast(uint)(cast(float)(interior * interior * interior) * density);
            foreach (_; 0 .. candidateCount) {
                int x = cast(int)(1 + (rng.next() % interior));
                int y = cast(int)(1 + (rng.next() % interior));
                int z = cast(int)(1 + (rng.next() % interior));
                placeTree(x, y, z);
            }
        }
    }

    void placeTree(int x, int y, int z) {
        ubyte dimension = params.dimension;
        size_t location = voxelIndex(dimension, x, y, z);
        if (voxels.get(location) == Material.Void) {
            int voidNeighbors = 0;
            int groundDirection = NO_GROUND_DIRECTION;
            foreach (direction; 0 .. 6) {
                Material neighbor = voxels.get(voxelIndex(dimension, x + TREE_NEIGHBOR_OFFSETS[direction][0], y + TREE_NEIGHBOR_OFFSETS[direction][1], z + TREE_NEIGHBOR_OFFSETS[direction][2]));
                if (neighbor == Material.Void) {
                    voidNeighbors += 1;
                } else if (isGroundMaterial(neighbor)) {
                    groundDirection = direction;
                }
            }
            if (voidNeighbors == 5 && groundDirection != NO_GROUND_DIRECTION) {
                voxels.dataMut(dimension)[location] = Material.Wood;
                int leafX = x - TREE_NEIGHBOR_OFFSETS[groundDirection][0];
                int leafY = y - TREE_NEIGHBOR_OFFSETS[groundDirection][1];
                int leafZ = z - TREE_NEIGHBOR_OFFSETS[groundDirection][2];
                if (leafX >= 0 && leafX < dimension && leafY >= 0 && leafY < dimension && leafZ >= 0 && leafZ < dimension) {
                    voxels.dataMut(dimension)[voxelIndex(dimension, leafX, leafY, leafZ)] = Material.Leaves;
                }
            }
        }
    }
}

GeneratedVoxels generateVoxels(const(ChunkParams)* params) {
    if (params.isFlat) {
        return GeneratedVoxels(params.flatVoxels(), false);
    } else {
        TerrainGenerator generator = TerrainGenerator(VoxelData.solid(Material.Void), params, SplitMix(hash(params.nodeSpice, params.chunk)), false);
        generator.generateTerrain();
        if (params.isRoad && !(generator.voxels.isSolidVoid() && params.altitudes().low > ROAD_THICKNESS)) {
            generator.generateRoad();
        } else if (params.isRoadSupport && !(generator.voxels.isSolid() && !generator.voxels.isSolidVoid())) {
            generator.generateRoadSupport();
        }
        generator.generateTrees();
        generator.voxels.compressUniform(params.dimension);
        generator.voxels.initializeMargins(params.dimension);
        return GeneratedVoxels(generator.voxels, generator.hasDeferredMaterials);
    }
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

Material roadMaterial(float elevation, float horizontalDistance) {
    if (elevation < ROAD_THICKNESS && horizontalDistance < ROAD_CENTER_HALF_WIDTH) {
        return Material.WhiteBrick;
    } else if (elevation < ROAD_THICKNESS) {
        return Material.GreyBrick;
    } else {
        return Material.Void;
    }
}

float clamped(float value, float low, float high) {
    if (value < low) {
        return low;
    } else if (value > high) {
        return high;
    } else {
        return value;
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

ValueRange valueRange(float[8] values) {
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

bool isTrussAt(ubyte dimension, int x, int y, int z) {
    int offset = dimension / 3;
    uint criteriaMet = 0;
    if (x == offset) {
        criteriaMet += 1;
    }
    if (y == offset) {
        criteriaMet += 1;
    }
    if (z == offset) {
        criteriaMet += 1;
    }
    if (x == y) {
        criteriaMet += 1;
    }
    if (y == z) {
        criteriaMet += 1;
    }
    if (x == z) {
        criteriaMet += 1;
    }
    return criteriaMet >= TRUSS_CRITERIA;
}

bool isGroundMaterial(Material material) {
    return material == Material.Dirt || material == Material.Grass || material == Material.MudGrass || material == Material.LushGrass || material == Material.TanGrass || material == Material.CoarseGrass;
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

float[3] voxelCenter(ubyte dimension, int x, int y, int z) {
    float d = cast(float) dimension;
    float[3] result = [
        (cast(float) x + 0.5f) / d,
        (cast(float) y + 0.5f) / d,
        (cast(float) z + 0.5f) / d,
    ];
    return result;
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
