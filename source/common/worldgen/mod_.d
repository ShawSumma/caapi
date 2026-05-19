module common.worldgen.mod_;

import common.dodeca;
import common.graph;
import common.margins;
import common.math;
import common.node;
import common.voxel_math;
import common.world;
import common.worldgen.plane;
import common.worldgen.terraingen : terraingenVoronoi;
import std.math;
import core.bitop : rol;

private enum NodeStateKind { Sky, DeepSky, Land, DeepLand }
private enum NodeStateRoad { East, DeepEast, West, DeepWest }

private enum float TERRAIN_SMOOTHNESS = 10.0f;

private NodeStateKind childKind(NodeStateKind self, Side side) {
    if (self == NodeStateKind.Sky && side == Side.A) {
        return NodeStateKind.Land;
    }
    if (self == NodeStateKind.Land && side == Side.A) {
        return NodeStateKind.Sky;
    }
    if (self == NodeStateKind.Sky && !sideAdjacentTo(side, Side.A)) {
        return NodeStateKind.DeepSky;
    }
    if (self == NodeStateKind.Land && !sideAdjacentTo(side, Side.A)) {
        return NodeStateKind.DeepLand;
    }
    return self;
}

private NodeStateRoad childRoad(NodeStateRoad self, Side side) {
    if (self == NodeStateRoad.East && side == Side.B) {
        return NodeStateRoad.West;
    }
    if (self == NodeStateRoad.West && side == Side.B) {
        return NodeStateRoad.East;
    }
    if (self == NodeStateRoad.East && !sideAdjacentTo(side, Side.B)) {
        return NodeStateRoad.DeepEast;
    }
    if (self == NodeStateRoad.West && !sideAdjacentTo(side, Side.B)) {
        return NodeStateRoad.DeepWest;
    }
    return self;
}

/// Contains all information about a node used for world generation
struct NodeState {
    NodeStateKind kind;
    NodeStateRoad roadState;
    EnviroFactors enviro;
    Plane surface;

    static NodeState* create(ref Graph graph, NodeId node) {
        int pcount;
        auto ps = graph.parents(node, pcount);

        EnviroFactors env;
        NodeStateKind kind;
        NodeStateRoad road;

        if (pcount == 0) {
            env = EnviroFactors(0, 0, 0, 0);
            kind = NodeStateKind.Land;
            road = NodeStateRoad.West;
        } else if (pcount == 1) {
            auto parentState = graph.nodeState(ps[0].id);
            ulong spice = graph.hashOf(node);
            env = EnviroFactors.variedFrom(parentState.enviro, spice);
            kind = childKind(parentState.kind, ps[0].side);
            road = childRoad(parentState.roadState, ps[0].side);
        } else {
            auto pA = graph.nodeState(ps[0].id);
            auto pB = graph.nodeState(ps[1].id);
            auto abNode = graph.neighbor(ps[0].id, ps[1].side);
            if (abNode != NodeId.init) {
                graph.ensureNodeState(abNode);
                auto abState = graph.nodeState(abNode);
                env = EnviroFactors.continueFrom(pA.enviro, pB.enviro, abState.enviro);
            } else {
                ulong spice = graph.hashOf(node);
                env = EnviroFactors.variedFrom(pA.enviro, spice);
            }
            kind = childKind(pA.kind, ps[0].side);
            road = childRoad(pA.roadState, ps[0].side);
        }

        Plane surf;
        if (kind == NodeStateKind.Land) {
            surf = Plane.fromSide(Side.A);
        } else if (kind == NodeStateKind.Sky) {
            surf = -Plane.fromSide(Side.A);
        } else if (pcount > 0) {
            auto pState = graph.nodeState(ps[0].id);
            surf = pState.surface.reflectAcross(ps[0].side);
        } else {
            surf = Plane.fromSide(Side.A);
        }

        auto state = new NodeState;
        state.kind = kind;
        state.roadState = road;
        state.enviro = env;
        state.surface = surf;
        return state;
    }
}

struct EnviroFactors {
    float maxElevation = 0;
    float temperature = 0;
    float rainfall = 0;
    float blockiness = 0;

    static EnviroFactors variedFrom(EnviroFactors parent, ulong spice) {
        float normalSample = hashToNormal(spice, 0) * 4.0f;
        float u1 = hashToUniform(spice, 1);
        float u2 = hashToUniform(spice, 2);
        float u3 = hashToUniform(spice, 3);

        return EnviroFactors(
            parent.maxElevation + normalSample,
            parent.temperature + u1,
            parent.rainfall + u2,
            parent.blockiness + u3,
        );
    }

    static EnviroFactors continueFrom(EnviroFactors a, EnviroFactors b, EnviroFactors ab) {
        return EnviroFactors(
            a.maxElevation + (b.maxElevation - ab.maxElevation),
            a.temperature + (b.temperature - ab.temperature),
            a.rainfall + (b.rainfall - ab.rainfall),
            a.blockiness + (b.blockiness - ab.blockiness),
        );
    }
}

struct ChunkIncidentEnviroFactors {
    float[8] maxElevations;
    float[8] temperatures;
    float[8] rainfalls;
    float[8] blockinesses;
}

/// Data needed to generate a chunk
struct ChunkParams {
    ubyte dimension;
    Vertex chunk;
    ChunkIncidentEnviroFactors env;
    Plane surface;
    bool isRoad;
    bool isRoadSupport;
    ulong nodeSpice;

    static ChunkParams create(ref Graph graph, ChunkId chunkId) {
        graph.ensureNodeState(chunkId.node);
        auto env = chunkIncidentEnviroFactors(graph, chunkId);
        auto ns = graph.nodeState(chunkId.node);

        ChunkParams p;
        p.dimension = graph.layout().dimension;
        p.chunk = chunkId.vertex;
        p.env = env;
        p.surface = ns.surface;
        p.isRoad = (ns.kind == NodeStateKind.Sky) &&
                   (ns.roadState == NodeStateRoad.East || ns.roadState == NodeStateRoad.West);
        p.isRoadSupport = (ns.kind == NodeStateKind.Land || ns.kind == NodeStateKind.DeepLand) &&
                          (ns.roadState == NodeStateRoad.East || ns.roadState == NodeStateRoad.West);
        p.nodeSpice = graph.hashOf(chunkId.node);
        return p;
    }
}

/// Generate voxels for a chunk
VoxelData generateVoxels(const ref ChunkParams params) {
    auto voxels = VoxelData.solid(Material.Void);
    ulong rngState = hash(params.nodeSpice, params.chunk);

    generateTerrain(params, voxels, rngState);

    if (params.isRoad) {
        generateRoad(params, voxels);
    } else if (params.isRoadSupport) {
        generateRoadSupport(params, voxels);
    }

    generateTrees(params, voxels, rngState);

    initializeMargins(params.dimension, voxels);
    return voxels;
}

private void generateTerrain(const ref ChunkParams params, ref VoxelData voxels, ref ulong rng) {
    ubyte dim = params.dimension;

    float meMin = params.env.maxElevations[0];
    float meMax = params.env.maxElevations[0];
    foreach (me; params.env.maxElevations[1 .. $]) {
        if (me < meMin) {
            meMin = me;
        }
        if (me > meMax) {
            meMax = me;
        }
    }

    enum float ELEVATION_MARGIN = 0.7f;

    float centerElevation = params.surface.distanceToChunk(params.chunk, [0.5f, 0.5f, 0.5f]);
    if (centerElevation - ELEVATION_MARGIN > meMax / TERRAIN_SMOOTHNESS) {
        voxels = VoxelData.solid(Material.Void);
        return;
    }
    if (centerElevation + ELEVATION_MARGIN < meMin / TERRAIN_SMOOTHNESS && !params.isRoad) {
        voxels = VoxelData.solid(Material.Dirt);
        return;
    }

    foreach (x; 0 .. dim) {
        foreach (y; 0 .. dim) {
            foreach (z; 0 .. dim) {
                float[3] center = voxelCenter(dim, x, y, z);
                float[3] trilerpCoords = [
                    (1.0f - center[0]) * 0.5f,
                    (1.0f - center[1]) * 0.5f,
                    (1.0f - center[2]) * 0.5f,
                ];

                float rain = trilerp(params.env.rainfalls, trilerpCoords) + rngNormal(&rng, 0.03f);
                float temp = trilerp(params.env.temperatures, trilerpCoords) + rngNormal(&rng, 0.03f);

                float elevPreTerracing = trilerp(params.env.maxElevations, trilerpCoords);
                float block = trilerp(params.env.blockinesses, trilerpCoords);
                float voxelElevation = params.surface.distanceToChunk(params.chunk, center);
                float strength = 0.4f / (1.0f + sqr(voxelElevation));
                float terracingSmall = terracingDiff(elevPreTerracing, block, 5.0f, strength, 2.0f);
                float terracingBig = terracingDiff(elevPreTerracing, block, 15.0f, strength, -1.0f);
                float elevPreNoise = elevPreTerracing + 0.6f * terracingSmall + 0.4f * terracingBig;

                float distPreNoise = elevPreNoise / TERRAIN_SMOOTHNESS - voxelElevation;

                float elev = elevPreNoise + TERRAIN_SMOOTHNESS * rngNormal(&rng, 0.03f);

                float dist;
                if (distPreNoise > 0.0f) {
                    float d = elev / TERRAIN_SMOOTHNESS - voxelElevation;
                    dist = d > 0.0f ? d : 0.0f;
                } else {
                    dist = distPreNoise;
                }

                if (dist >= 0.0f) {
                    auto mat = terraingenVoronoi(elev, rain, temp, dist);
                    size_t idx = index(dim, x, y, z);
                    voxels.dataMut(dim)[idx] = mat;
                }
            }
        }
    }
}

private void generateRoad(const ref ChunkParams params, ref VoxelData voxels) {
    auto plane = -Plane.fromSide(Side.B);
    ubyte dim = params.dimension;

    foreach (x; 0 .. dim) {
        foreach (y; 0 .. dim) {
            foreach (z; 0 .. dim) {
                float[3] center = voxelCenter(dim, x, y, z);
                float horizontalDistance = plane.distanceToChunk(params.chunk, center);
                float elevation = params.surface.distanceToChunk(params.chunk, center);

                if (horizontalDistance > 0.3f || elevation > 0.9f) {
                    continue;
                }

                Material mat = Material.Void;
                if (elevation < 0.075f) {
                    if (horizontalDistance < 0.15f) {
                        mat = Material.WhiteBrick;
                    } else {
                        mat = Material.GreyBrick;
                    }
                }

                voxels.dataMut(dim)[index(dim, x, y, z)] = mat;
            }
        }
    }
}

private void generateRoadSupport(const ref ChunkParams params, ref VoxelData voxels) {
    if (voxels.isSolid() && voxels.get(0) != Material.Void) {
        return;
    }

    auto plane = -Plane.fromSide(Side.B);
    ubyte dim = params.dimension;

    foreach (x; 0 .. dim) {
        foreach (y; 0 .. dim) {
            foreach (z; 0 .. dim) {
                float[3] center = voxelCenter(dim, x, y, z);
                float horizontalDistance = plane.distanceToChunk(params.chunk, center);

                if (horizontalDistance > 0.3f) {
                    continue;
                }

                Material mat;
                if (trussingAt(params.dimension, cast(ubyte) x, cast(ubyte) y, cast(ubyte) z)) {
                    mat = Material.WoodPlanks;
                } else {
                    mat = Material.Void;
                }

                if (mat != Material.Void) {
                    voxels.dataMut(dim)[index(dim, x, y, z)] = mat;
                }
            }
        }
    }
}

private bool trussingAt(ubyte dimension, ubyte x, ubyte y, ubyte z) {
    uint criteriaMet = 0;
    ubyte offset = dimension / 3;
    criteriaMet += (x == offset) ? 1 : 0;
    criteriaMet += (y == offset) ? 1 : 0;
    criteriaMet += (z == offset) ? 1 : 0;
    criteriaMet += (x == y) ? 1 : 0;
    criteriaMet += (y == z) ? 1 : 0;
    criteriaMet += (x == z) ? 1 : 0;
    return criteriaMet >= 2;
}

private void generateTrees(const ref ChunkParams params, ref VoxelData voxels, ref ulong rng) {
    if (voxels.isSolid()) {
        return;
    }
    ubyte dim = params.dimension;
    if (dim <= 4) {
        return;
    }

    float rain = params.env.rainfalls[0];
    float density = rain / 100.0f;
    if (density < 0.0f) {
        density = 0.0f;
    }
    if (density > 0.5f) {
        density = 0.5f;
    }
    uint treeCandidateCount = cast(uint)(cast(float)((dim - 2) * (dim - 2) * (dim - 2)) * density);

    foreach (_; 0 .. treeCandidateCount) {
        ubyte lx = cast(ubyte)(1 + (rngNext(&rng) % (dim - 2)));
        ubyte ly = cast(ubyte)(1 + (rngNext(&rng) % (dim - 2)));
        ubyte lz = cast(ubyte)(1 + (rngNext(&rng) % (dim - 2)));

        size_t locIdx = index(dim, lx, ly, lz);
        if (voxels.get(locIdx) != Material.Void) {
            continue;
        }

        int numVoidNeighbors = 0;
        int groundDir = -1;
        static immutable int[3][6] offsets = [
            [-1, 0, 0], [1, 0, 0],
            [0, -1, 0], [0, 1, 0],
            [0, 0, -1], [0, 0, 1],
        ];
        foreach (d; 0 .. 6) {
            int nx = lx + offsets[d][0];
            int ny = ly + offsets[d][1];
            int nz = lz + offsets[d][2];
            auto nmat = voxels.get(index(dim, nx, ny, nz));
            if (nmat == Material.Void) {
                numVoidNeighbors++;
            } else if (nmat == Material.Dirt || nmat == Material.Grass ||
                       nmat == Material.MudGrass || nmat == Material.LushGrass ||
                       nmat == Material.TanGrass || nmat == Material.CoarseGrass) {
                groundDir = d;
            }
        }

        if (numVoidNeighbors == 5 && groundDir >= 0) {
            voxels.dataMut(dim)[locIdx] = Material.Wood;
            int ox = lx - offsets[groundDir][0];
            int oy = ly - offsets[groundDir][1];
            int oz = lz - offsets[groundDir][2];
            if (ox >= 0 && ox < dim && oy >= 0 && oy < dim && oz >= 0 && oz < dim) {
                voxels.dataMut(dim)[index(dim, ox, oy, oz)] = Material.Leaves;
            }
        }
    }
}

private float serp(float v0, float v1, float t, float threshold) {
    if (t < threshold) {
        return v0;
    } else if (t < 1.0f - threshold) {
        float s = (t - threshold) / ((1.0f - threshold) - threshold);
        return v0 * (1.0f - s) + v1 * s;
    } else {
        return v1;
    }
}

private float terracingDiff(float elevRaw, float block, float scale, float strength, float limiter) {
    float threshold = strength / (1.0f + pow(2.0f, limiter - block));
    float elevFloor = floor(elevRaw / scale);
    float elevRem = elevRaw / scale - elevFloor;
    return scale * elevFloor + serp(0.0f, scale, elevRem, threshold) - elevRaw;
}

private float sqr(float x) {
    return x * x;
}

private float[3] voxelCenter(ubyte dimension, int x, int y, int z) {
    float d = cast(float) dimension;
    return [
        (cast(float) x + 0.5f) / d,
        (cast(float) y + 0.5f) / d,
        (cast(float) z + 0.5f) / d,
    ];
}

private size_t index(ubyte dimension, int x, int y, int z) {
    size_t lwm = dimension + 2;
    return (x + 1) + (y + 1) * lwm + (z + 1) * lwm * lwm;
}

float trilerp(const ref float[8] values, float[3] t) {
    float lerp(float v0, float v1, float s) { return v0 * (1.0f - s) + v1 * s; }
    float bilerp(float v00, float v01, float v10, float v11, float tx, float ty) {
        return lerp(lerp(v00, v01, tx), lerp(v10, v11, tx), ty);
    }
    return lerp(
        bilerp(values[0], values[4], values[2], values[6], t[0], t[1]),
        bilerp(values[1], values[5], values[3], values[7], t[0], t[1]),
        t[2]
    );
}

private ChunkIncidentEnviroFactors chunkIncidentEnviroFactors(ref Graph graph, ChunkId chunk) {
    auto sides = vertexCanonicalSides(chunk.vertex);
    Side a = sides[0], b = sides[1], c = sides[2];

    Side[][] paths = [
        [],
        [c],
        [b],
        [b, c],
        [a],
        [a, c],
        [a, b],
        [a, b, c],
    ];

    ChunkIncidentEnviroFactors result;

    foreach (i; 0 .. 8) {
        NodeId node = chunk.node;
        foreach (side; paths[i]) {
            node = graph.ensureNeighbor(node, side);
        }
        graph.ensureNodeState(node);
        auto ns = graph.nodeState(node);
        auto enviro = ns.enviro;
        result.maxElevations[i] = enviro.maxElevation;
        result.temperatures[i] = enviro.temperature;
        result.rainfalls[i] = enviro.rainfall;
        result.blockinesses[i] = enviro.blockiness;
    }

    return result;
}

// Simple splitmix64-based RNG
private ulong rngNext(ulong* state) {
    *state += 0x9e3779b97f4a7c15;
    ulong z = *state;
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) * 0x94d049bb133111eb;
    return z ^ (z >> 31);
}

private float rngNormal(ulong* state, float stddev) {
    ulong v1 = rngNext(state);
    ulong v2 = rngNext(state);
    float u1 = (cast(float)((v1 >> 40) + 1)) / cast(float)((1UL << 24) + 2);
    float u2 = cast(float)(v2 >> 40) / cast(float)(1UL << 24);
    return sqrt(-2.0f * log(u1)) * cos(2.0f * PI * u2) * stddev;
}

private float hashToUniform(ulong seed, uint idx) {
    ulong s = seed ^ (cast(ulong) idx * 0x517cc1b727220a95);
    ulong v = rngNext(&s);
    return (cast(float)(v >> 40) / cast(float)(1UL << 24)) * 2.0f - 1.0f;
}

private float hashToNormal(ulong seed, uint idx) {
    ulong s = seed ^ (cast(ulong) idx * 0x9e3779b97f4a7c15);
    ulong v1 = rngNext(&s);
    ulong v2 = rngNext(&s);
    float u1 = (cast(float)((v1 >> 40) + 1)) / cast(float)((1UL << 24) + 2);
    float u2 = cast(float)(v2 >> 40) / cast(float)(1UL << 24);
    return sqrt(-2.0f * log(u1)) * cos(2.0f * PI * u2);
}

private ulong hash(ulong a, ulong b) {
    return (rol(a, 5) ^ b) * 0x517c_c1b7_2722_0a95;
}
