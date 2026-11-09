module common.worldgen.climate;

import base.maybe : Maybe;
import base.numbers : higherOf, lowerOf;
import base.splitmix : SplitMix;
import base.vector3 : Vec3;
import common.view : GraphView;
import common.worldgen.palette : laidBy, palette;
import geometry.honeycomb : Corner, Face, faces;
import plugins.api.api : Material;

enum float RUGGED_THRESHOLD = 0.4f;
enum float MOUNTAIN_HEIGHT = 2.5f;
enum float LAPSE_RATE = 0.3f;
enum float COVER_DEPTH = 0.06f;
enum float SOIL_DEPTH = 0.4f;
enum float WATER_LEVEL = -0.6f;
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

    static CubeClimate ensureAround(ref GraphView view, uint slot, Corner chunk) {
        Face[3] sides = chunk.faces;
        NodeClimate[8] around;
        foreach (crossed; 0 .. 8) {
            uint node = slot;
            foreach (axis; 0 .. 3) {
                if ((crossed & (1u << axis)) != 0) {
                    node = view.ensureNeighborSlot(node, sides[axis]);
                }
            }
            around[crossed] = view.ensureState(node).climate;
        }
        return fromAround(around);
    }

    Climate at(Vec3!float cube) const {
        Climate[4] alongX;
        foreach (index; 0 .. 4) {
            alongX[index] = Climate.lerp(corners[2 * index], corners[2 * index + 1], cube.x);
        }
        Climate low = Climate.lerp(alongX[0], alongX[1], cube.y);
        Climate high = Climate.lerp(alongX[2], alongX[3], cube.y);
        return Climate.lerp(low, high, cube.z);
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
        return palette.cover.slice().laidBy(warmth, climate.wetness, climate.relief);
    } else if (depth < SOIL_DEPTH) {
        return palette.soil.slice().laidBy(warmth, climate.wetness, climate.relief);
    } else {
        return palette.rocks[rockBand(depth + climate.strata)][wetnessClass(climate.wetness)][warmthClass(warmth)];
    }
}

Material openAt(float altitude, Climate climate) {
    if (altitude >= WATER_LEVEL) {
        return Material.none;
    } else {
        return palette.fluids.slice().laidBy(climate.warmth(), climate.wetness, climate.relief);
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
        return Maybe!Material.of(palette.rocks[rockBand(shallowest + lowest.strata)][wetnessClass(lowest.wetness)][warmthClass(coldest)]);
    } else {
        return Maybe!Material.init;
    }
}
