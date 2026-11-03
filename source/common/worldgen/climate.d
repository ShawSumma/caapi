module common.worldgen.climate;

import base.maybe : Maybe;
import base.numbers : higherOf, lowerOf;
import base.splitmix : SplitMix;
import common.view : GraphView;
import geometry.honeycomb : Corner, Face, faces;
import plugins.api.api : Material;

enum float RUGGED_THRESHOLD = 0.4f;
enum float MOUNTAIN_HEIGHT = 2.5f;
enum float LAPSE_RATE = 0.3f;
enum float COVER_DEPTH = 0.06f;
enum float SOIL_DEPTH = 0.4f;
enum float SNOW_WARMTH = -0.45f;
enum float WATER_LEVEL = -0.6f;
enum float BEACH_HEIGHT = 0.08f;
enum float DEEP_WATER = 0.5f;
enum float ROCKY_RELIEF = 2.2f;
enum float WARMTH_CLASS_LIMIT = 0.35f;

struct Process {
    float keep;
    float spread;
    ulong salt;
}

immutable Process BROAD_RELIEF = Process(0.92f, 0.25f, 0x51ED2701);
immutable Process LOCAL_RELIEF = Process(0.5f, 0.25f, 0x7A3D9C11);
immutable Process HEAT = Process(0.94f, 0.3f, 0x2B992DD3);
immutable Process WETNESS = Process(0.94f, 0.3f, 0x6C8E9CF5);
immutable Process STRATA = Process(0.8f, 0.25f, 0x3C6EF372);
immutable Process RUGGEDNESS = Process(0.9f, 0.2f, 0x1F83D9AB);
immutable float[3] ROCK_BAND_DEPTHS = [1.2f, 2.6f, 4.5f];
immutable float[2] WETNESS_CLASS_LIMITS = [-0.2f, 0.3f];

immutable Material[2][3][4] ROCKS = [
    [[Material.sandstone, Material.redSandstone], [Material.shale, Material.shale], [Material.limestone, Material.limestone]],
    [[Material.slate, Material.slate], [Material.dolomite, Material.marble], [Material.marble, Material.marble]],
    [[Material.granite, Material.granite], [Material.diorite, Material.diorite], [Material.andesite, Material.andesite]],
    [[Material.gabbro, Material.olivine], [Material.basalt, Material.basalt], [Material.gabbro, Material.gabbro]],
];

float boundOf(Process process) {
    return process.spread / (1 - process.keep);
}

float mountainOf(float ruggedness) {
    return MOUNTAIN_HEIGHT * higherOf(0, ruggedness - RUGGED_THRESHOLD);
}

enum float RELIEF_BOUND = boundOf(BROAD_RELIEF) + boundOf(LOCAL_RELIEF) + MOUNTAIN_HEIGHT * (boundOf(RUGGEDNESS) - RUGGED_THRESHOLD);
enum float RELIEF_SLACK = 4 * (BROAD_RELIEF.spread + LOCAL_RELIEF.spread + MOUNTAIN_HEIGHT * RUGGEDNESS.spread);

struct NodeClimate {
    float broad = 0;
    float local = 0;
    float heat = 0;
    float wetness = 0;
    float strata = 0;
    float ruggedness = 0;
    float calm = 1;

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
        return Climate(calm * (broad + local + mountainOf(ruggedness)), heat, wetness, strata);
    }
}

float stepped(float mean, Process process, ulong spice) {
    return process.keep * mean + process.spread * noiseOf(spice ^ process.salt);
}

float noiseOf(ulong seed) {
    return SplitMix(seed).roll() * 2 - 1;
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

    float warmth() const {
        return heat - LAPSE_RATE * relief;
    }
}

struct CubeClimate {
    Climate[8] corners;
    Climate lowest;
    Climate highest;

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

    CubeClimate reachingFlat() const {
        CubeClimate reaching = this;
        reaching.lowest.relief = lowerOf(lowest.relief, 0.0f);
        reaching.highest.relief = higherOf(highest.relief, 0.0f);
        return reaching;
    }
}

Material groundAt(float depth, float riser, Climate climate) {
    float warmth = climate.warmth();
    if (depth < higherOf(COVER_DEPTH, lowerOf(riser, SOIL_DEPTH))) {
        return coverOf(warmth, climate.wetness, climate.relief);
    } else if (depth < SOIL_DEPTH) {
        return soilOf(warmth, climate.wetness, climate.relief);
    } else {
        return ROCKS[rockBand(depth + climate.strata)][wetnessClass(climate.wetness)][warmthClass(warmth)];
    }
}

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
    } else if (warmth < -0.15f && wetness < -0.2f) {
        return Material.gravel;
    } else if (warmth < -0.15f) {
        return Material.coarseGrass;
    } else if (isRedDesert(warmth, wetness)) {
        return Material.redSand;
    } else if (isDesert(warmth, wetness)) {
        return Material.sand;
    } else if (wetness > 0.75f && warmth > 0.1f) {
        return Material.mud;
    } else if (wetness > 0.45f && warmth > 0.1f) {
        return Material.lushGrass;
    } else if (wetness > 0.45f) {
        return Material.mudGrass;
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
    if (warmth >= WARMTH_CLASS_LIMIT) {
        return 1;
    } else {
        return 0;
    }
}

Maybe!Material uniformRock(float shallowest, float deepest, Climate lowest, Climate highest) {
    float coldest = lowest.heat - LAPSE_RATE * highest.relief;
    float warmest = highest.heat - LAPSE_RATE * lowest.relief;
    if (shallowest >= SOIL_DEPTH && rockBand(shallowest + lowest.strata) == rockBand(deepest + highest.strata) && wetnessClass(lowest.wetness) == wetnessClass(highest.wetness) && warmthClass(coldest) == warmthClass(warmest)) {
        return Maybe!Material.of(ROCKS[rockBand(shallowest + lowest.strata)][wetnessClass(lowest.wetness)][warmthClass(coldest)]);
    } else {
        return Maybe!Material.init;
    }
}
