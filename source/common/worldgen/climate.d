module common.worldgen.climate;

import base.numbers : higherOf, lowerOf;
import common.material : Material;
import common.view : GraphView;
import geometry.honeycomb : Corner, Face, faces;

// Relief and climate are numbers each node carries for its center. A node takes a share of its parents' mean and
// adds noise drawn from its own id, so the values wander from node to node but always back toward zero: neighbors
// are close, distant nodes unrelated, and nothing grows without bound however far the world goes. Being numbers
// rather than geometry, they lose no precision with distance either.

// How strongly a value holds to its parents', how far it may step from them, and the salt of its noise.
struct Process {
    float keep;
    float spread;
    ulong salt;
}

// Relief, in units of distance above the ground's plane, is the sum of a broad slow swell and a local roughness.
immutable Process BROAD_RELIEF = Process(0.92f, 0.25f, 0x51ED2701);
immutable Process LOCAL_RELIEF = Process(0.5f, 0.25f, 0x7A3D9C11);
// Warmth and wetness mostly stay between about -1 and 1, wandering far enough within a few nodes that climates change
// over a short walk.
immutable Process HEAT = Process(0.94f, 0.3f, 0x2B992DD3);
immutable Process WETNESS = Process(0.94f, 0.3f, 0x6C8E9CF5);
// Shifts the depths at which one kind of rock gives way to the next, so the layers undulate.
immutable Process STRATA = Process(0.8f, 0.25f, 0x3C6EF372);
// Where ruggedness climbs past its threshold, mountains rise in proportion to how far past it is.
immutable Process RUGGEDNESS = Process(0.9f, 0.2f, 0x1F83D9AB);
enum float RUGGED_THRESHOLD = 0.4f;
enum float MOUNTAIN_HEIGHT = 2.5f;

float boundOf(Process process) {
    return process.spread / (1 - process.keep);
}

float mountainOf(float ruggedness) {
    return MOUNTAIN_HEIGHT * higherOf(0, ruggedness - RUGGED_THRESHOLD);
}

enum float RELIEF_BOUND = boundOf(BROAD_RELIEF) + boundOf(LOCAL_RELIEF) + MOUNTAIN_HEIGHT * (boundOf(RUGGEDNESS) - RUGGED_THRESHOLD);
// Within a node, relief strays from its value at the center by no more than two steps of each process: every point is
// a blend of nodes at most that far apart. Mountains change by at most their height times ruggedness's change.
enum float RELIEF_SLACK = 4 * (BROAD_RELIEF.spread + LOCAL_RELIEF.spread + MOUNTAIN_HEIGHT * RUGGEDNESS.spread);

struct NodeClimate {
    float broad = 0;
    float local = 0;
    float heat = 0;
    float wetness = 0;
    float strata = 0;
    float ruggedness = 0;

    static NodeClimate fromParents(const(NodeClimate)[] parents, ulong spice) {
        NodeClimate mean;
        foreach (parent; parents) {
            mean.broad += parent.broad / parents.length;
            mean.local += parent.local / parents.length;
            mean.heat += parent.heat / parents.length;
            mean.wetness += parent.wetness / parents.length;
            mean.strata += parent.strata / parents.length;
            mean.ruggedness += parent.ruggedness / parents.length;
        }
        return NodeClimate(stepped(mean.broad, BROAD_RELIEF, spice), stepped(mean.local, LOCAL_RELIEF, spice), stepped(mean.heat, HEAT, spice), stepped(mean.wetness, WETNESS, spice), stepped(mean.strata, STRATA, spice), stepped(mean.ruggedness, RUGGEDNESS, spice));
    }

    Climate climate() const {
        return Climate(broad + local + mountainOf(ruggedness), heat, wetness, strata);
    }
}

float stepped(float mean, Process process, ulong spice) {
    return process.keep * mean + process.spread * noiseOf(spice ^ process.salt);
}

// A value from -1 to 1 that the seed alone decides.
float noiseOf(ulong seed) {
    ulong z = seed + 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EB;
    z ^= z >> 31;
    return cast(float)(z >> 40) / cast(float)(1 << 23) - 1;
}

struct Climate {
    float relief = 0;
    float heat = 0;
    float wetness = 0;
    float strata = 0;

    static Climate lerp(Climate a, Climate b, float t) {
        return Climate(a.relief + (b.relief - a.relief) * t, a.heat + (b.heat - a.heat) * t, a.wetness + (b.wetness - a.wetness) * t, a.strata + (b.strata - a.strata) * t);
    }

    static Climate mean(const(Climate)[] values) {
        Climate sum;
        foreach (value; values) {
            sum = Climate(sum.relief + value.relief / values.length, sum.heat + value.heat / values.length, sum.wetness + value.wetness / values.length, sum.strata + value.strata / values.length);
        }
        return sum;
    }

    // High ground is colder.
    float warmth() const {
        return heat - LAPSE_RATE * relief;
    }
}

// The climate inside one of a node's cubes. Each corner of the cube takes the mean of the nodes that share that
// point: the dodecahedron's corner is shared by the eight nodes around it, the middle of an edge by four, the middle
// of a face by two, and the node's center is its own. Neighboring cubes therefore agree wherever they meet, the
// inside is interpolated between the corners, and the corners bound every value inside exactly.
struct CubeClimate {
    Climate[8] corners;
    Climate lowest;
    Climate highest;

    // Around the dodecahedron's corner, the node reached by crossing the cube's faces whose bits are set.
    static CubeClimate fromAround(ref const NodeClimate[8] around) {
        CubeClimate cube;
        foreach (index; 0 .. 8) {
            uint onFaces = ~index & 7;
            Climate[8] sharing;
            uint count = 0;
            foreach (crossed; 0 .. 8) {
                if ((crossed & ~onFaces) == 0) {
                    sharing[count] = around[crossed].climate();
                    count += 1;
                }
            }
            cube.corners[index] = Climate.mean(sharing[0 .. count]);
        }
        cube.lowest = cube.corners[0];
        cube.highest = cube.corners[0];
        foreach (corner; cube.corners[1 .. $]) {
            cube.lowest = Climate(lowerOf(cube.lowest.relief, corner.relief), lowerOf(cube.lowest.heat, corner.heat), lowerOf(cube.lowest.wetness, corner.wetness), lowerOf(cube.lowest.strata, corner.strata));
            cube.highest = Climate(higherOf(cube.highest.relief, corner.relief), higherOf(cube.highest.heat, corner.heat), higherOf(cube.highest.wetness, corner.wetness), higherOf(cube.highest.strata, corner.strata));
        }
        return cube;
    }

    static CubeClimate around(ref GraphView view, uint slot, Corner chunk) {
        Face[3] sides = chunk.faces;
        NodeClimate[8] around;
        foreach (crossed; 0 .. 8) {
            uint node = slot;
            foreach (axis; 0 .. 3) {
                if ((crossed & (1u << axis)) != 0) {
                    node = view.ensureNeighborSlot(node, sides[axis]);
                }
            }
            around[crossed] = view.stateAt(node).climate;
        }
        return fromAround(around);
    }

    // Cube coordinates run from the dodecahedron's corner at 0 to the node's center at 1.
    Climate at(float[3] cube) const {
        Climate[4] alongX;
        foreach (index; 0 .. 4) {
            alongX[index] = Climate.lerp(corners[2 * index], corners[2 * index + 1], cube[0]);
        }
        Climate low = Climate.lerp(alongX[0], alongX[1], cube[1]);
        Climate high = Climate.lerp(alongX[2], alongX[3], cube[1]);
        return Climate.lerp(low, high, cube[2]);
    }

    Climate mean() const {
        return Climate.mean(corners[]);
    }
}

enum float LAPSE_RATE = 0.3f;
enum float COVER_DEPTH = 0.06f;
enum float SOIL_DEPTH = 0.4f;
enum float SNOW_WARMTH = -0.45f;
// Below this height above the ground's plane, whatever the terrain leaves open is water; ice where it is cold.
enum float WATER_LEVEL = -0.6f;
enum float BEACH_HEIGHT = 0.08f;
enum float DEEP_WATER = 0.5f;
// Above this height, ground that is not snowed over is bare rock.
enum float ROCKY_RELIEF = 2.2f;

// What lies at a depth below the ground's surface, the surface being as high as the climate's relief.
Material groundAt(float depth, Climate climate) {
    float warmth = climate.warmth();
    if (depth < COVER_DEPTH) {
        return coverOf(warmth, climate.wetness, climate.relief);
    } else if (depth < SOIL_DEPTH) {
        return soilOf(warmth, climate.wetness, climate.relief);
    } else {
        return ROCKS[rockBand(depth + climate.strata)][wetnessClass(climate.wetness)][warmthClass(warmth)];
    }
}

// What fills the open space at a height above the ground's plane: water below the water level, otherwise nothing.
Material openAt(float altitude, Climate climate) {
    if (altitude >= WATER_LEVEL) {
        return Material.none;
    } else if (climate.warmth() < SNOW_WARMTH) {
        return Material.ice;
    } else {
        return Material.water;
    }
}

bool isDesert(float warmth, float wetness) {
    return warmth > 0.45f && wetness < -0.35f;
}

bool isRedDesert(float warmth, float wetness) {
    return isDesert(warmth, wetness) && wetness < -0.65f;
}

bool isShore(float relief) {
    return relief < WATER_LEVEL + BEACH_HEIGHT;
}

Material coverOf(float warmth, float wetness, float relief) {
    if (warmth < SNOW_WARMTH) {
        return Material.snow;
    } else if (relief > ROCKY_RELIEF) {
        return Material.andesite;
    } else if (relief < WATER_LEVEL - DEEP_WATER) {
        return Material.gravel;
    } else if (isShore(relief)) {
        return Material.sand;
    } else if (warmth < -0.15f) {
        return wetness < -0.2f ? Material.gravel : Material.coarseGrass;
    } else if (isDesert(warmth, wetness)) {
        return isRedDesert(warmth, wetness) ? Material.redSand : Material.sand;
    } else if (wetness > 0.75f && warmth > 0.1f) {
        return Material.mud;
    } else if (wetness > 0.45f) {
        return warmth > 0.1f ? Material.lushGrass : Material.mudGrass;
    } else if (warmth > 0.25f && wetness < -0.05f) {
        return Material.tanGrass;
    } else {
        return Material.grass;
    }
}

Material soilOf(float warmth, float wetness, float relief) {
    if (relief > ROCKY_RELIEF) {
        return Material.andesite;
    } else if (isShore(relief)) {
        return Material.sand;
    } else if (isRedDesert(warmth, wetness)) {
        return Material.redSand;
    } else if (isDesert(warmth, wetness)) {
        return Material.sand;
    } else if (wetness > 0.5f) {
        return Material.clay;
    } else if (wetness > 0.2f) {
        return Material.clayLoam;
    } else if (wetness > -0.1f) {
        return Material.dirt;
    } else {
        return Material.sandyLoam;
    }
}

// Rock is chosen by three classes that each only grow with their value, so one kind fills a range of depths and
// climates exactly when both ends of the range land in the same classes.
immutable float[3] ROCK_BAND_DEPTHS = [1.2f, 2.6f, 4.5f];
immutable float[2] WETNESS_CLASS_LIMITS = [-0.2f, 0.3f];
enum float WARMTH_CLASS_LIMIT = 0.35f;

immutable Material[2][3][4] ROCKS = [
    [[Material.sandstone, Material.redSandstone], [Material.shale, Material.shale], [Material.limestone, Material.limestone]],
    [[Material.slate, Material.slate], [Material.dolomite, Material.marble], [Material.marble, Material.marble]],
    [[Material.granite, Material.granite], [Material.diorite, Material.diorite], [Material.andesite, Material.andesite]],
    [[Material.gabbro, Material.olivine], [Material.basalt, Material.basalt], [Material.gabbro, Material.gabbro]],
];

uint rockBand(float depth) {
    uint band = 0;
    while (band < ROCK_BAND_DEPTHS.length && depth >= ROCK_BAND_DEPTHS[band]) {
        band += 1;
    }
    return band;
}

uint wetnessClass(float wetness) {
    uint index = 0;
    while (index < WETNESS_CLASS_LIMITS.length && wetness >= WETNESS_CLASS_LIMITS[index]) {
        index += 1;
    }
    return index;
}

uint warmthClass(float warmth) {
    return warmth >= WARMTH_CLASS_LIMIT;
}

struct UniformRock {
    Material material;
    bool isProven;
}

// The one rock filling every depth and climate in the given ranges, when there is one.
UniformRock uniformRock(float shallowest, float deepest, Climate lowest, Climate highest) {
    float coldest = lowest.heat - LAPSE_RATE * highest.relief;
    float warmest = highest.heat - LAPSE_RATE * lowest.relief;
    bool isSame = shallowest >= SOIL_DEPTH;
    isSame = isSame && rockBand(shallowest + lowest.strata) == rockBand(deepest + highest.strata);
    isSame = isSame && wetnessClass(lowest.wetness) == wetnessClass(highest.wetness);
    isSame = isSame && warmthClass(coldest) == warmthClass(warmest);
    if (isSame) {
        return UniformRock(ROCKS[rockBand(shallowest + lowest.strata)][wetnessClass(lowest.wetness)][warmthClass(coldest)], true);
    } else {
        return UniformRock(Material.none, false);
    }
}

enum uint TEST_SAMPLES = 50;
enum uint TEST_GENERATIONS = 2000;
enum float TEST_TOLERANCE = 1e-4f;

unittest {
    NodeClimate[8] around;
    foreach (index; 0 .. 8) {
        around[index] = NodeClimate.fromParents(around[0 .. index], index * 977);
    }
    CubeClimate cube = CubeClimate.fromAround(around);
    assert(cube.corners[7].relief == around[0].climate().relief);
    foreach (sample; 0 .. TEST_SAMPLES) {
        float t = cast(float) sample / TEST_SAMPLES;
        Climate inside = cube.at([t, 1 - t, t * t]);
        assert(inside.relief >= cube.lowest.relief - TEST_TOLERANCE && inside.relief <= cube.highest.relief + TEST_TOLERANCE);
        UniformRock rock = uniformRock(SOIL_DEPTH + t * 4, SOIL_DEPTH + t * 4, inside, inside);
        assert(rock.isProven && rock.material == groundAt(SOIL_DEPTH + t * 4, inside));
    }
    NodeClimate walked;
    foreach (generation; 0 .. TEST_GENERATIONS) {
        NodeClimate[1] parent = [walked];
        walked = NodeClimate.fromParents(parent[], generation * 0x9E37);
        assert(walked.broad <= boundOf(BROAD_RELIEF) && walked.broad >= -boundOf(BROAD_RELIEF));
        assert(walked.heat <= boundOf(HEAT) && walked.heat >= -boundOf(HEAT));
    }
}
