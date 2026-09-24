module common.worldgen.generation;

import core.bitop : rol;
import core.stdc.math : cosf, floorf, logf, powf, sqrtf;
import common.dodeca : Side, Vertex, sideAdjacentTo, vertexCanonicalSides;
import common.graph : Graph, NO_NODE, NodeId, ParentList, nodeSpice;
import common.margins : initializeMargins;
import common.math : PI;
import common.node : ChunkId, VoxelData;
import common.world : Material;
import common.worldgen.plane : Plane, planeFromSide;
import common.worldgen.terraingen : sqr, terraingenVoronoi;

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

enum float TERRAIN_SMOOTHNESS = 10.0f;
enum float ELEVATION_MARGIN = 0.7f;
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
enum ulong SPLITMIX_INCREMENT = 0x9e3779b97f4a7c15;
enum ulong SPLITMIX_MULTIPLIER_1 = 0xbf58476d1ce4e5b9;
enum ulong SPLITMIX_MULTIPLIER_2 = 0x94d049bb133111eb;
enum ulong UNIFORM_SEED_MULTIPLIER = 0x517cc1b727220a95;
enum ulong NORMAL_SEED_MULTIPLIER = 0x9e3779b97f4a7c15;
enum ulong CHUNK_HASH_MULTIPLIER = 0x517c_c1b7_2722_0a95;
enum float RANDOM_24_BIT_RANGE = cast(float)(1UL << 24);
enum float RANDOM_24_BIT_RANGE_PLUS_2 = cast(float)((1UL << 24) + 2);

immutable int[3][6] TREE_NEIGHBOR_OFFSETS = [
    [-1, 0, 0],
    [1, 0, 0],
    [0, -1, 0],
    [0, 1, 0],
    [0, 0, -1],
    [0, 0, 1],
];

struct EnviroFactors {
    float maxElevation = 0;
    float temperature = 0;
    float rainfall = 0;
    float blockiness = 0;
}

struct NodeState {
    EnviroFactors enviro;
    Plane surface;
    NodeStateKind kind;
    NodeStateRoad road;
}

struct ChunkIncidentEnviroFactors {
    float[8] maxElevations;
    float[8] temperatures;
    float[8] rainfalls;
    float[8] blockinesses;
}

struct ChunkParams {
    ulong nodeSpice;
    ChunkIncidentEnviroFactors env;
    Plane surface;
    ubyte dimension;
    Vertex chunk;
    bool isRoad;
    bool isRoadSupport;
    bool flat;
}

NodeStateKind childKind(NodeStateKind self, Side side) {
    NodeStateKind result = self;
    if (self == NodeStateKind.Sky && side == Side.A) {
        result = NodeStateKind.Land;
    } else if (self == NodeStateKind.Land && side == Side.A) {
        result = NodeStateKind.Sky;
    } else if (self == NodeStateKind.Sky && !sideAdjacentTo(side, Side.A)) {
        result = NodeStateKind.DeepSky;
    } else if (self == NodeStateKind.Land && !sideAdjacentTo(side, Side.A)) {
        result = NodeStateKind.DeepLand;
    }
    return result;
}

NodeStateRoad childRoad(NodeStateRoad self, Side side) {
    NodeStateRoad result = self;
    if (self == NodeStateRoad.East && side == Side.B) {
        result = NodeStateRoad.West;
    } else if (self == NodeStateRoad.West && side == Side.B) {
        result = NodeStateRoad.East;
    } else if (self == NodeStateRoad.East && !sideAdjacentTo(side, Side.B)) {
        result = NodeStateRoad.DeepEast;
    } else if (self == NodeStateRoad.West && !sideAdjacentTo(side, Side.B)) {
        result = NodeStateRoad.DeepWest;
    }
    return result;
}

NodeState createNodeState(Graph* graph, NodeId node) {
    ParentList parents = graph.parents(node);
    NodeState state;
    if (parents.count == 0) {
        state.kind = NodeStateKind.Land;
        state.road = NodeStateRoad.West;
    } else {
        const(NodeState)* first = graph.nodeState(parents.links[0].id);
        if (parents.count == 1) {
            state.enviro = variedFrom(first.enviro, nodeSpice(node));
        } else {
            const(NodeState)* second = graph.nodeState(parents.links[1].id);
            NodeId abNode = graph.neighbor(parents.links[0].id, parents.links[1].side);
            if (abNode != NO_NODE) {
                graph.ensureNodeState(abNode);
                state.enviro = continueFrom(first.enviro, second.enviro, graph.nodeState(abNode).enviro);
            } else {
                state.enviro = variedFrom(first.enviro, nodeSpice(node));
            }
        }
        state.kind = childKind(first.kind, parents.links[0].side);
        state.road = childRoad(first.road, parents.links[0].side);
    }

    if (state.kind == NodeStateKind.Land) {
        state.surface = planeFromSide(Side.A);
    } else if (state.kind == NodeStateKind.Sky) {
        state.surface = -planeFromSide(Side.A);
    } else if (parents.count > 0) {
        state.surface = graph.nodeState(parents.links[0].id).surface.reflectAcross(parents.links[0].side);
    } else {
        state.surface = planeFromSide(Side.A);
    }
    return state;
}

EnviroFactors variedFrom(EnviroFactors parent, ulong spice) {
    EnviroFactors result;
    result.maxElevation = parent.maxElevation + hashToNormal(spice, 0) * ELEVATION_VARIATION;
    result.temperature = parent.temperature + hashToUniform(spice, 1);
    result.rainfall = parent.rainfall + hashToUniform(spice, 2);
    result.blockiness = parent.blockiness + hashToUniform(spice, 3);
    return result;
}

EnviroFactors continueFrom(EnviroFactors a, EnviroFactors b, EnviroFactors ab) {
    EnviroFactors result;
    result.maxElevation = a.maxElevation + (b.maxElevation - ab.maxElevation);
    result.temperature = a.temperature + (b.temperature - ab.temperature);
    result.rainfall = a.rainfall + (b.rainfall - ab.rainfall);
    result.blockiness = a.blockiness + (b.blockiness - ab.blockiness);
    return result;
}

ChunkParams createChunkParams(Graph* graph, ChunkId chunkId, bool flat) {
    graph.ensureNodeState(chunkId.node);
    const(NodeState)* state = graph.nodeState(chunkId.node);
    bool onRoadLine = state.road == NodeStateRoad.East || state.road == NodeStateRoad.West;
    ChunkParams params;
    params.dimension = graph.layout.dimension;
    params.chunk = chunkId.vertex;
    params.env = chunkIncidentEnviroFactors(graph, chunkId);
    params.surface = state.surface;
    params.isRoad = state.kind == NodeStateKind.Sky && onRoadLine;
    params.isRoadSupport = (state.kind == NodeStateKind.Land || state.kind == NodeStateKind.DeepLand) && onRoadLine;
    params.flat = flat;
    params.nodeSpice = nodeSpice(chunkId.node);
    return params;
}

VoxelData generateVoxels(const(ChunkParams)* params) {
    VoxelData voxels = VoxelData.solid(Material.Void);
    if (params.flat) {
        voxels = generateFlatVoxels(params);
    } else {
        ulong rngState = hash(params.nodeSpice, params.chunk);
        generateTerrain(params, &voxels, &rngState);
        if (params.isRoad) {
            generateRoad(params, &voxels);
        } else if (params.isRoadSupport) {
            generateRoadSupport(params, &voxels);
        }
        generateTrees(params, &voxels, &rngState);
        initializeMargins(params.dimension, &voxels);
    }
    return voxels;
}

VoxelData generateFlatVoxels(const(ChunkParams)* params) {
    ubyte dimension = params.dimension;
    float centerElevation = params.surface.distanceToChunk(params.chunk, [0.5f, 0.5f, 0.5f]);
    VoxelData voxels = VoxelData.solid(Material.Void);
    if (centerElevation + ELEVATION_MARGIN < 0) {
        voxels = VoxelData.solid(Material.Dirt);
    } else if (!(centerElevation - ELEVATION_MARGIN > 0)) {
        foreach (x; 0 .. dimension) {
            foreach (y; 0 .. dimension) {
                foreach (z; 0 .. dimension) {
                    if (params.surface.distanceToChunk(params.chunk, voxelCenter(dimension, x, y, z)) < 0) {
                        voxels.dataMut(dimension)[voxelIndex(dimension, x, y, z)] = Material.Dirt;
                    }
                }
            }
        }
        initializeMargins(dimension, &voxels);
    }
    return voxels;
}

void generateTerrain(const(ChunkParams)* params, VoxelData* voxels, ulong* rng) {
    ubyte dimension = params.dimension;
    float minElevation = params.env.maxElevations[0];
    float maxElevation = params.env.maxElevations[0];
    foreach (elevation; params.env.maxElevations[1 .. 8]) {
        if (elevation < minElevation) {
            minElevation = elevation;
        }
        if (elevation > maxElevation) {
            maxElevation = elevation;
        }
    }

    float centerElevation = params.surface.distanceToChunk(params.chunk, [0.5f, 0.5f, 0.5f]);
    if (centerElevation - ELEVATION_MARGIN > maxElevation / TERRAIN_SMOOTHNESS) {
        *voxels = VoxelData.solid(Material.Void);
    } else if (centerElevation + ELEVATION_MARGIN < minElevation / TERRAIN_SMOOTHNESS && !params.isRoad) {
        *voxels = VoxelData.solid(Material.Dirt);
    } else {
        foreach (x; 0 .. dimension) {
            foreach (y; 0 .. dimension) {
                foreach (z; 0 .. dimension) {
                    generateTerrainVoxel(params, voxels, rng, voxelCenter(dimension, x, y, z), voxelIndex(dimension, x, y, z));
                }
            }
        }
    }
}

void generateTerrainVoxel(const(ChunkParams)* params, VoxelData* voxels, ulong* rng, float[3] center, size_t index) {
    float[3] trilerpCoords = [
        (1.0f - center[0]) * 0.5f,
        (1.0f - center[1]) * 0.5f,
        (1.0f - center[2]) * 0.5f,
    ];
    float rain = trilerp(params.env.rainfalls, trilerpCoords) + rngNormal(rng, NOISE_STDDEV);
    float temperature = trilerp(params.env.temperatures, trilerpCoords) + rngNormal(rng, NOISE_STDDEV);
    float elevationPreTerracing = trilerp(params.env.maxElevations, trilerpCoords);
    float blockiness = trilerp(params.env.blockinesses, trilerpCoords);
    float voxelElevation = params.surface.distanceToChunk(params.chunk, center);
    float strength = TERRACE_STRENGTH / (1.0f + sqr(voxelElevation));
    float terracingSmall = terracingDiff(elevationPreTerracing, blockiness, SMALL_TERRACE_SCALE, strength, SMALL_TERRACE_LIMITER);
    float terracingBig = terracingDiff(elevationPreTerracing, blockiness, BIG_TERRACE_SCALE, strength, BIG_TERRACE_LIMITER);
    float elevationPreNoise = elevationPreTerracing + SMALL_TERRACE_WEIGHT * terracingSmall + BIG_TERRACE_WEIGHT * terracingBig;
    float distancePreNoise = elevationPreNoise / TERRAIN_SMOOTHNESS - voxelElevation;
    float elevation = elevationPreNoise + TERRAIN_SMOOTHNESS * rngNormal(rng, NOISE_STDDEV);

    float distance = distancePreNoise;
    if (distancePreNoise > 0.0f) {
        distance = elevation / TERRAIN_SMOOTHNESS - voxelElevation;
        if (!(distance > 0.0f)) {
            distance = 0.0f;
        }
    }
    if (distance >= 0.0f) {
        voxels.dataMut(params.dimension)[index] = terraingenVoronoi(elevation, rain, temperature, distance);
    }
}

void generateRoad(const(ChunkParams)* params, VoxelData* voxels) {
    Plane plane = -planeFromSide(Side.B);
    ubyte dimension = params.dimension;
    foreach (x; 0 .. dimension) {
        foreach (y; 0 .. dimension) {
            foreach (z; 0 .. dimension) {
                float[3] center = voxelCenter(dimension, x, y, z);
                float horizontalDistance = plane.distanceToChunk(params.chunk, center);
                float elevation = params.surface.distanceToChunk(params.chunk, center);
                if (!(horizontalDistance > ROAD_HALF_WIDTH || elevation > ROAD_CLEARANCE)) {
                    Material material = Material.Void;
                    if (elevation < ROAD_THICKNESS) {
                        if (horizontalDistance < ROAD_CENTER_HALF_WIDTH) {
                            material = Material.WhiteBrick;
                        } else {
                            material = Material.GreyBrick;
                        }
                    }
                    voxels.dataMut(dimension)[voxelIndex(dimension, x, y, z)] = material;
                }
            }
        }
    }
}

void generateRoadSupport(const(ChunkParams)* params, VoxelData* voxels) {
    if (!(voxels.isSolid() && voxels.get(0) != Material.Void)) {
        Plane plane = -planeFromSide(Side.B);
        ubyte dimension = params.dimension;
        foreach (x; 0 .. dimension) {
            foreach (y; 0 .. dimension) {
                foreach (z; 0 .. dimension) {
                    float horizontalDistance = plane.distanceToChunk(params.chunk, voxelCenter(dimension, x, y, z));
                    if (!(horizontalDistance > ROAD_HALF_WIDTH) && trussingAt(dimension, x, y, z)) {
                        voxels.dataMut(dimension)[voxelIndex(dimension, x, y, z)] = Material.WoodPlanks;
                    }
                }
            }
        }
    }
}

bool trussingAt(ubyte dimension, int x, int y, int z) {
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

void generateTrees(const(ChunkParams)* params, VoxelData* voxels, ulong* rng) {
    ubyte dimension = params.dimension;
    if (!voxels.isSolid() && dimension > MIN_TREE_DIMENSION) {
        float density = params.env.rainfalls[0] / RAINFALL_PER_TREE_DENSITY;
        if (density < 0.0f) {
            density = 0.0f;
        }
        if (density > MAX_TREE_DENSITY) {
            density = MAX_TREE_DENSITY;
        }
        uint interior = dimension - 2;
        uint candidateCount = cast(uint)(cast(float)(interior * interior * interior) * density);
        foreach (_; 0 .. candidateCount) {
            int x = cast(int)(1 + (rngNext(rng) % interior));
            int y = cast(int)(1 + (rngNext(rng) % interior));
            int z = cast(int)(1 + (rngNext(rng) % interior));
            placeTree(dimension, voxels, x, y, z);
        }
    }
}

void placeTree(ubyte dimension, VoxelData* voxels, int x, int y, int z) {
    size_t location = voxelIndex(dimension, x, y, z);
    if (voxels.get(location) == Material.Void) {
        int voidNeighbors = 0;
        int groundDirection = -1;
        foreach (direction; 0 .. 6) {
            Material neighbor = voxels.get(voxelIndex(dimension, x + TREE_NEIGHBOR_OFFSETS[direction][0], y + TREE_NEIGHBOR_OFFSETS[direction][1], z + TREE_NEIGHBOR_OFFSETS[direction][2]));
            if (neighbor == Material.Void) {
                voidNeighbors += 1;
            } else if (isGroundMaterial(neighbor)) {
                groundDirection = direction;
            }
        }
        if (voidNeighbors == 5 && groundDirection >= 0) {
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

float serp(float v0, float v1, float t, float threshold) {
    float result = v1;
    if (t < threshold) {
        result = v0;
    } else if (t < 1.0f - threshold) {
        float s = (t - threshold) / ((1.0f - threshold) - threshold);
        result = v0 * (1.0f - s) + v1 * s;
    }
    return result;
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

ChunkIncidentEnviroFactors chunkIncidentEnviroFactors(Graph* graph, ChunkId chunk) {
    Side[3] sides = vertexCanonicalSides(chunk.vertex);
    ChunkIncidentEnviroFactors result;
    foreach (corner; 0 .. 8) {
        NodeId node = chunk.node;
        if ((corner & 4) != 0) {
            node = graph.ensureNeighbor(node, sides[0]);
        }
        if ((corner & 2) != 0) {
            node = graph.ensureNeighbor(node, sides[1]);
        }
        if ((corner & 1) != 0) {
            node = graph.ensureNeighbor(node, sides[2]);
        }
        graph.ensureNodeState(node);
        EnviroFactors enviro = graph.nodeState(node).enviro;
        result.maxElevations[corner] = enviro.maxElevation;
        result.temperatures[corner] = enviro.temperature;
        result.rainfalls[corner] = enviro.rainfall;
        result.blockinesses[corner] = enviro.blockiness;
    }
    return result;
}

ulong rngNext(ulong* state) {
    *state += SPLITMIX_INCREMENT;
    ulong z = *state;
    z = (z ^ (z >> 30)) * SPLITMIX_MULTIPLIER_1;
    z = (z ^ (z >> 27)) * SPLITMIX_MULTIPLIER_2;
    return z ^ (z >> 31);
}

float boxMuller(ulong first, ulong second) {
    float u1 = cast(float)((first >> 40) + 1) / RANDOM_24_BIT_RANGE_PLUS_2;
    float u2 = cast(float)(second >> 40) / RANDOM_24_BIT_RANGE;
    return sqrtf(-2.0f * logf(u1)) * cosf(2.0f * PI * u2);
}

float rngNormal(ulong* state, float stddev) {
    ulong first = rngNext(state);
    ulong second = rngNext(state);
    return boxMuller(first, second) * stddev;
}

float hashToUniform(ulong seed, uint index) {
    ulong state = seed ^ (cast(ulong) index * UNIFORM_SEED_MULTIPLIER);
    ulong value = rngNext(&state);
    return (cast(float)(value >> 40) / RANDOM_24_BIT_RANGE) * 2.0f - 1.0f;
}

float hashToNormal(ulong seed, uint index) {
    ulong state = seed ^ (cast(ulong) index * NORMAL_SEED_MULTIPLIER);
    ulong first = rngNext(&state);
    ulong second = rngNext(&state);
    return boxMuller(first, second);
}

ulong hash(ulong a, ulong b) {
    return (rol(a, 5) ^ b) * CHUNK_HASH_MULTIPLIER;
}
