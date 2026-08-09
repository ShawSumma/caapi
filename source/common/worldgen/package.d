module common.worldgen;

public import common.worldgen.plane;
public import common.worldgen.horosphere;
public import common.worldgen.terraingen;

import core.bitop : rol;
import core.stdc.stdlib : calloc;
import common.math : PI, cos, floor, log, pow, sqrt;
import common.dodeca : Side, Vertex, vertexCanonicalSides, sideAdjacentTo;
import common.graph : Graph, NodeId;
import common.margins : initializeMargins;
import common.node : ChunkId, VoxelData;
import common.world : Material;
import common.worldgen.plane : Plane;
import common.worldgen.terraingen : terraingenVoronoi;

enum NodeStateKind {
    Sky,
    DeepSky,
    Land,
    DeepLand,
}

enum NodeStateRoad {
    East,
    DeepEast,
    West,
    DeepWest,
}

enum float TERRAIN_SMOOTHNESS = 10.0f;

NodeStateKind childKind(NodeStateKind self, Side side) {
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

NodeStateRoad childRoad(NodeStateRoad self, Side side) {
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

// Contains all information about a node used for world generation
struct NodeState {
    NodeStateKind kind;
    NodeStateRoad roadState;
    EnviroFactors enviro;
    Plane surface;

    static NodeState* create(ref Graph graph, NodeId node) {
        Graph.ParentList parentList = graph.parents(node);
        int pcount = parentList.count;
        Graph.ParentResult[3] ps = parentList.items;

        EnviroFactors env;
        NodeStateKind kind;
        NodeStateRoad road;

        if (pcount == 0) {
            env = EnviroFactors(0, 0, 0, 0);
            kind = NodeStateKind.Land;
            road = NodeStateRoad.West;
        } else if (pcount == 1) {
            const(NodeState)* parentState = graph.nodeState(ps[0].id);
            ulong spice = graph.hashOf(node);
            env = EnviroFactors.variedFrom(parentState.enviro, spice);
            kind = childKind(parentState.kind, ps[0].side);
            road = childRoad(parentState.roadState, ps[0].side);
        } else {
            const(NodeState)* pA = graph.nodeState(ps[0].id);
            const(NodeState)* pB = graph.nodeState(ps[1].id);
            NodeId abNode = graph.neighbor(ps[0].id, ps[1].side);
            if (abNode != NodeId.init) {
                graph.ensureNodeState(abNode);
                const(NodeState)* abState = graph.nodeState(abNode);
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
            const(NodeState)* pState = graph.nodeState(ps[0].id);
            surf = pState.surface.reflectAcross(ps[0].side);
        } else {
            surf = Plane.fromSide(Side.A);
        }

        // Owned by the node it hangs off, which lives as long as the graph.
        NodeState* state = cast(NodeState*) calloc(1, NodeState.sizeof);
        assert(state !is null, "node state allocation failed");
        *state = NodeState.init;
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
    // Debug worldgen: fill strictly below the unmodified surface plane. The
    // base plane is lattice-aligned, so this produces a genuinely flat voxel
    // floor with gravity exactly perpendicular to it.
    bool flat;
    ulong nodeSpice;

    static ChunkParams create(ref Graph graph, ChunkId chunkId, bool flat = false) {
        graph.ensureNodeState(chunkId.node);
        ChunkIncidentEnviroFactors env = chunkIncidentEnviroFactors(graph, chunkId);
        const(NodeState)* ns = graph.nodeState(chunkId.node);

        ChunkParams p;
        p.dimension = graph.layout().dimension;
        p.chunk = chunkId.vertex;
        p.env = env;
        p.surface = ns.surface;
        p.isRoad = (ns.kind == NodeStateKind.Sky) &&
                   (ns.roadState == NodeStateRoad.East || ns.roadState == NodeStateRoad.West);
        p.isRoadSupport = (ns.kind == NodeStateKind.Land || ns.kind == NodeStateKind.DeepLand) &&
                          (ns.roadState == NodeStateRoad.East || ns.roadState == NodeStateRoad.West);
        p.flat = flat;
        p.nodeSpice = graph.hashOf(chunkId.node);
        return p;
    }
}

// The seed for a chunk's noise stream. Shared so the GPU generator derives it
// the same way rather than reimplementing it.
ulong chunkRngSeed(const ref ChunkParams params) {
    return hash(params.nodeSpice, params.chunk);
}

// Whether generateVoxels would hand back a solid chunk: the terrain collapsed
// and nothing afterwards promoted it to dense. The renderer skips solid chunks
// outright, so a GPU-generated chunk has to reach the same representation, not
// merely the same voxel values.
bool producesSolidChunk(const ref ChunkParams params) {
    TerrainMode mode = terrainModeFor(params);
    if (mode == TerrainMode.Dense) {
        return false;
    }
    // generateRoad writes unconditionally, so a road chunk always goes dense.
    if (params.isRoad) {
        return false;
    }
    // Road support skips a solid non-void chunk but fills trussing into a
    // solid void one.
    if (params.isRoadSupport && mode == TerrainMode.SolidVoid) {
        return false;
    }
    return true;
}

Material solidChunkMaterial(const ref ChunkParams params) {
    if (terrainModeFor(params) == TerrainMode.SolidDirt) {
        return Material.Dirt;
    }
    return Material.Void;
}

// Runs the tree pass over terrain produced elsewhere (the GPU). Trees are
// sequential and order-dependent, so a single GPU thread has to walk hundreds
// of dependent neighbour reads and the rest of the batch waits on it; the host
// does the same work far faster.
//
// splitmix64 advances by a constant per draw, so the state terrain left behind
// is just the seed plus its draw count. Only the dense path draws at all, and
// only the dense path grows trees, which is why the mode is checked here.
void generateTreesAfterTerrain(const ref ChunkParams params, ref VoxelData voxels) {
    if (terrainModeFor(params) != TerrainMode.Dense) {
        return;
    }
    ulong dim = params.dimension;
    ulong drawsUsed = 6 * dim * dim * dim;
    ulong rng = chunkRngSeed(params) + drawsUsed * 0x9e3779b97f4a7c15;
    generateTrees(params, voxels, rng);
}

/// Generate voxels for a chunk
VoxelData generateVoxels(const ref ChunkParams params) {
    if (params.flat) {
        return generateFlatVoxels(params);
    }

    VoxelData voxels = VoxelData.solid(Material.Void);
    ulong rngState = chunkRngSeed(params);

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

VoxelData generateFlatVoxels(const ref ChunkParams params) {
    ubyte dim = params.dimension;
    enum float MARGIN = 0.7f;

    float centerElevation = params.surface.distanceToChunk(params.chunk, [0.5f, 0.5f, 0.5f]);
    if (centerElevation - MARGIN > 0) {
        return VoxelData.solid(Material.Void);
    }
    if (centerElevation + MARGIN < 0) {
        return VoxelData.solid(Material.Dirt);
    }

    VoxelData voxels = VoxelData.solid(Material.Void);
    foreach (x; 0 .. dim) {
        foreach (y; 0 .. dim) {
            foreach (z; 0 .. dim) {
                if (params.surface.distanceToChunk(params.chunk, voxelCenter(dim, x, y, z)) < 0) {
                    voxels.dataMut(dim)[index(dim, x, y, z)] = Material.Dirt;
                }
            }
        }
    }
    initializeMargins(dim, voxels);
    return voxels;
}

// Whether a chunk's terrain collapses to a single material before any
// per-voxel work. Shared with the GPU generator, which needs the same answer
// host-side because it depends on whole-chunk values rather than per-voxel
// ones; keeping one implementation stops the two drifting.
enum TerrainMode : uint {
    Dense = 0,
    SolidVoid = 1,
    SolidDirt = 2,
}

enum float ELEVATION_MARGIN = 0.7f;

TerrainMode terrainModeFor(const ref ChunkParams params) {
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

    float centerElevation = params.surface.distanceToChunk(params.chunk, [0.5f, 0.5f, 0.5f]);
    if (centerElevation - ELEVATION_MARGIN > meMax / TERRAIN_SMOOTHNESS) {
        return TerrainMode.SolidVoid;
    }
    if (centerElevation + ELEVATION_MARGIN < meMin / TERRAIN_SMOOTHNESS && !params.isRoad) {
        return TerrainMode.SolidDirt;
    }
    return TerrainMode.Dense;
}

void generateTerrain(const ref ChunkParams params, ref VoxelData voxels, ref ulong rng) {
    ubyte dim = params.dimension;

    TerrainMode mode = terrainModeFor(params);
    if (mode == TerrainMode.SolidVoid) {
        voxels = VoxelData.solid(Material.Void);
        return;
    }
    if (mode == TerrainMode.SolidDirt) {
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
                    Material mat = terraingenVoronoi(elev, rain, temp, dist);
                    size_t idx = index(dim, x, y, z);
                    voxels.dataMut(dim)[idx] = mat;
                }
            }
        }
    }
}

void generateRoad(const ref ChunkParams params, ref VoxelData voxels) {
    Plane plane = -Plane.fromSide(Side.B);
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

void generateRoadSupport(const ref ChunkParams params, ref VoxelData voxels) {
    if (voxels.isSolid() && voxels.get(0) != Material.Void) {
        return;
    }

    Plane plane = -Plane.fromSide(Side.B);
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

bool trussingAt(ubyte dimension, ubyte x, ubyte y, ubyte z) {
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

void generateTrees(const ref ChunkParams params, ref VoxelData voxels, ref ulong rng) {
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
            Material nmat = voxels.get(index(dim, nx, ny, nz));
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

float terracingDiff(float elevRaw, float block, float scale, float strength, float limiter) {
    float threshold = strength / (1.0f + pow(2.0f, limiter - block));
    float elevFloor = floor(elevRaw / scale);
    float elevRem = elevRaw / scale - elevFloor;
    return scale * elevFloor + serp(0.0f, scale, elevRem, threshold) - elevRaw;
}

float sqr(float x) {
    return x * x;
}

float[3] voxelCenter(ubyte dimension, int x, int y, int z) {
    float d = cast(float) dimension;
    return [
        (cast(float) x + 0.5f) / d,
        (cast(float) y + 0.5f) / d,
        (cast(float) z + 0.5f) / d,
    ];
}

size_t index(ubyte dimension, int x, int y, int z) {
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

ChunkIncidentEnviroFactors chunkIncidentEnviroFactors(ref Graph graph, ChunkId chunk) {
    Side[3] sides = vertexCanonicalSides(chunk.vertex);
    Side a = sides[0];
    Side b = sides[1];
    Side c = sides[2];

    ChunkIncidentEnviroFactors result;

    // The eight samples are the corners of the chunk's dual cube: index i
    // selects a subset of {a, b, c}, applied in that order. Bit 2 is a, bit 1
    // is b, bit 0 is c.
    foreach (i; 0 .. 8) {
        NodeId node = chunk.node;
        if ((i & 4) != 0) {
            node = graph.ensureNeighbor(node, a);
        }
        if ((i & 2) != 0) {
            node = graph.ensureNeighbor(node, b);
        }
        if ((i & 1) != 0) {
            node = graph.ensureNeighbor(node, c);
        }
        graph.ensureNodeState(node);
        const(NodeState)* ns = graph.nodeState(node);
        EnviroFactors enviro = ns.enviro;
        result.maxElevations[i] = enviro.maxElevation;
        result.temperatures[i] = enviro.temperature;
        result.rainfalls[i] = enviro.rainfall;
        result.blockinesses[i] = enviro.blockiness;
    }

    return result;
}

// Simple splitmix64-based RNG
ulong rngNext(ulong* state) {
    *state = *state + 0x9e3779b97f4a7c15;
    ulong z = *state;
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) * 0x94d049bb133111eb;
    return z ^ (z >> 31);
}

float rngNormal(ulong* state, float stddev) {
    ulong v1 = rngNext(state);
    ulong v2 = rngNext(state);
    float u1 = (cast(float)((v1 >> 40) + 1)) / cast(float)((1UL << 24) + 2);
    float u2 = cast(float)(v2 >> 40) / cast(float)(1UL << 24);
    return sqrt(-2.0f * log(u1)) * cos(2.0f * PI * u2) * stddev;
}

float hashToUniform(ulong seed, uint idx) {
    ulong s = seed ^ (cast(ulong) idx * 0x517cc1b727220a95);
    ulong v = rngNext(&s);
    return (cast(float)(v >> 40) / cast(float)(1UL << 24)) * 2.0f - 1.0f;
}

float hashToNormal(ulong seed, uint idx) {
    ulong s = seed ^ (cast(ulong) idx * 0x9e3779b97f4a7c15);
    ulong v1 = rngNext(&s);
    ulong v2 = rngNext(&s);
    float u1 = (cast(float)((v1 >> 40) + 1)) / cast(float)((1UL << 24) + 2);
    float u2 = cast(float)(v2 >> 40) / cast(float)(1UL << 24);
    return sqrt(-2.0f * log(u1)) * cos(2.0f * PI * u2);
}

ulong hash(ulong a, ulong b) {
    return (rol(a, 5) ^ b) * 0x517c_c1b7_2722_0a95;
}
