module common.worldgen.climate;

import base.maybe : Maybe;
import base.numbers : higherOf, lowerOf;
import base.splitmix : SplitMix;
import base.vector3 : Vec3;
import common.view : GraphView;
import common.worldgen.palette : DRIFT_COUNT, Drift, laidBy, palette;
import geometry.honeycomb : Corner, Face, faces;
import plugins.api.api : Material;

enum float UNDERSIDE_SWING = 0.5f;
enum float SLACK_SPREADS = 4;

immutable ulong[DRIFT_COUNT] DRIFT_SALTS = [0x51ED2701, 0x7A3D9C11, 0x2B992DD3, 0x6C8E9CF5, 0x3C6EF372, 0x1F83D9AB, 0x5D1E7A3B];

float boundOf(Drift drift) {
    return palette.shape.spread[drift] / (1 - palette.shape.keep[drift]);
}

float mountainOf(float ruggedness) {
    return palette.shape.mountainHeight * higherOf(0, ruggedness - palette.shape.ruggedThreshold);
}

float reliefBound() {
    return boundOf(Drift.broad) + boundOf(Drift.local) + palette.shape.mountainHeight * (boundOf(Drift.ruggedness) - palette.shape.ruggedThreshold);
}

float reliefSlack() {
    return SLACK_SPREADS * (palette.shape.spread[Drift.broad] + palette.shape.spread[Drift.local] + palette.shape.mountainHeight * palette.shape.spread[Drift.ruggedness]);
}

float shieldSlack() {
    return SLACK_SPREADS * palette.shape.spread[Drift.shield];
}

struct NodeClimate {
    float broad = 0;
    float local = 0;
    float heat = 0;
    float wetness = 0;
    float strata = 0;
    float ruggedness = 0;
    float shield = 0;
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
            mean.shield += parent.shield / parents.length;
        }
        return NodeClimate(stepped(mean.broad, Drift.broad, spice), stepped(mean.local, Drift.local, spice), stepped(mean.heat, Drift.heat, spice), stepped(mean.wetness, Drift.wetness, spice), stepped(mean.strata, Drift.strata, spice), stepped(mean.ruggedness, Drift.ruggedness, spice), stepped(mean.shield, Drift.shield, spice));
    }

    Climate climate() const {
        return Climate(calm * (broad + local + mountainOf(ruggedness)), heat, wetness, strata, shield);
    }
}

float stepped(float mean, Drift drift, ulong spice) {
    return palette.shape.keep[drift] * mean + palette.shape.spread[drift] * noiseOf(spice ^ DRIFT_SALTS[drift]);
}

float noiseOf(ulong seed) {
    return SplitMix(seed).roll() * 2 - 1;
}

struct Climate {
    float relief = 0;
    float heat = 0;
    float wetness = 0;
    float strata = 0;
    float shield = 0;

    static Climate lerp(Climate a, Climate b, float t) {
        return Climate(a.relief + (b.relief - a.relief) * t, a.heat + (b.heat - a.heat) * t, a.wetness + (b.wetness - a.wetness) * t, a.strata + (b.strata - a.strata) * t, a.shield + (b.shield - a.shield) * t);
    }

    static Climate mean(const(Climate)[] values) {
        Climate sum;
        foreach (value; values) {
            sum = Climate(sum.relief + value.relief / values.length, sum.heat + value.heat / values.length, sum.wetness + value.wetness / values.length, sum.strata + value.strata / values.length, sum.shield + value.shield / values.length);
        }
        return sum;
    }

    float warmth() const {
        return heat - palette.shape.lapseRate * relief;
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
            cube.lowest = Climate(lowerOf(cube.lowest.relief, corner.relief), lowerOf(cube.lowest.heat, corner.heat), lowerOf(cube.lowest.wetness, corner.wetness), lowerOf(cube.lowest.strata, corner.strata), lowerOf(cube.lowest.shield, corner.shield));
            cube.highest = Climate(higherOf(cube.highest.relief, corner.relief), higherOf(cube.highest.heat, corner.heat), higherOf(cube.highest.wetness, corner.wetness), higherOf(cube.highest.strata, corner.strata), higherOf(cube.highest.shield, corner.shield));
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
    if (depth < higherOf(palette.shape.coverDepth, lowerOf(riser, palette.shape.soilDepth))) {
        return palette.cover.slice().laidBy(warmth, climate.wetness, climate.relief);
    } else if (depth < palette.shape.soilDepth) {
        return palette.soil.slice().laidBy(warmth, climate.wetness, climate.relief);
    } else {
        return palette.rocks[rockBand(depth + climate.strata)][wetnessClass(climate.wetness)][warmthClass(warmth)];
    }
}

Material underAt(float depth, Climate climate) {
    if (depth < palette.shape.soilDepth) {
        return palette.flatFill;
    } else {
        return palette.rocks[rockBand(depth + climate.strata)][wetnessClass(climate.wetness)][warmthClass(climate.warmth())];
    }
}

Material openAt(float altitude, Climate climate) {
    if (altitude >= palette.shape.waterLevel) {
        return Material.none;
    } else {
        return palette.fluids.slice().laidBy(climate.warmth(), climate.wetness, climate.relief);
    }
}

uint rockBand(float depth) {
    uint band = 0;
    while (band < palette.shape.rockBandDepths.length && depth >= palette.shape.rockBandDepths[band]) {
        band += 1;
    }
    return band;
}

uint wetnessClass(float wetness) {
    uint index = 0;
    while (index < palette.shape.wetnessClassLimits.length && wetness >= palette.shape.wetnessClassLimits[index]) {
        index += 1;
    }
    return index;
}

uint warmthClass(float warmth) {
    if (warmth >= palette.shape.warmthClassLimit) {
        return 1;
    } else {
        return 0;
    }
}

Maybe!Material uniformRock(float shallowest, float deepest, Climate lowest, Climate highest) {
    float coldest = lowest.heat - palette.shape.lapseRate * highest.relief;
    float warmest = highest.heat - palette.shape.lapseRate * lowest.relief;
    if (shallowest >= palette.shape.soilDepth && rockBand(shallowest + lowest.strata) == rockBand(deepest + highest.strata) && wetnessClass(lowest.wetness) == wetnessClass(highest.wetness) && warmthClass(coldest) == warmthClass(warmest)) {
        return Maybe!Material.of(palette.rocks[rockBand(shallowest + lowest.strata)][wetnessClass(lowest.wetness)][warmthClass(coldest)]);
    } else {
        return Maybe!Material.init;
    }
}
