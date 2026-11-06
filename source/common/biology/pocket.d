module common.biology.pocket;

import core.stdc.math : expf;
import base.hashmap : HashMap;
import base.murmur : Hash128, murmurHash3;
import base.numbers : clamped;
import base.units : Ratio;
import common.biology.molecule : CENTER_CELL, Fragment, GRID_CELLS, GridPoint, Molecule, PROPERTY_COUNT, ROTATION_COUNT, cellOf, fragmentAt, inverted, pointOf, rotated;

enum uint TRANSDUCER_COUNT = 2;
enum uint HALF_CELLS = 13;
enum float FILL_SCORE = 1;
enum float MATCH_SCORE = 1;
enum float MISMATCH_SCORE = 1;
enum float CLASH_PENALTY = 4;
enum float BINDING_SCALE = 0.5f;
enum float REFERENCE_SCORE = 30;
enum Ratio EFFICACY_LIMIT = Ratio(1);

enum PocketKind : ubyte {
    wall,
    open,
    trigger,
    brake,
}

struct PocketCell {
    PocketKind kind;
    ubyte wanted;
    ubyte cares;
    ubyte transducer;
}

struct Pocket {
    PocketCell[GRID_CELLS] cells;

    size_t toHash() const {
        Hash128 hash = murmurHash3((cast(const(ubyte)*) cells.ptr)[0 .. cells.sizeof]);
        return cast(size_t) hash.first;
    }
}

struct HalfPocket {
    PocketCell[HALF_CELLS] cells;
}

immutable GridPoint[HALF_CELLS] HALF_POINTS = halfPoints();

GridPoint[HALF_CELLS] halfPoints() {
    GridPoint[HALF_CELLS] points;
    uint index = 0;
    foreach (y; -1 .. 2) {
        foreach (x; -1 .. 2) {
            points[index] = GridPoint(x, y, -1);
            index += 1;
        }
    }
    immutable GridPoint[4] ring = [GridPoint(1, 0, 0), GridPoint(1, 1, 0), GridPoint(0, 1, 0), GridPoint(-1, 1, 0)];
    foreach (point; ring) {
        points[index] = point;
        index += 1;
    }
    return points;
}

Pocket joined(HalfPocket first, HalfPocket second) {
    Pocket pocket;
    foreach (index, point; HALF_POINTS) {
        pocket.cells[cellOf(point)] = first.cells[index];
        pocket.cells[cellOf(inverted(point))] = second.cells[index];
    }
    pocket.cells[CENTER_CELL] = PocketCell(PocketKind.open, 0, 0, 0);
    return pocket;
}

struct Binding {
    Ratio affinity;
    Ratio[TRANSDUCER_COUNT] efficacy;
    float score;
    ubyte pose;
}

uint matchedBits(ubyte wanted, ubyte cares, ubyte properties) {
    uint matched = 0;
    foreach (bit; 0 .. PROPERTY_COUNT) {
        if ((cares & (1 << bit)) != 0 && ((wanted ^ properties) & (1 << bit)) == 0) {
            matched += 1;
        }
    }
    return matched;
}

uint caredBits(ubyte cares) {
    uint count = 0;
    foreach (bit; 0 .. PROPERTY_COUNT) {
        if ((cares & (1 << bit)) != 0) {
            count += 1;
        }
    }
    return count;
}

float poseScore(ref const Pocket pocket, Molecule pose) {
    float score = 0;
    foreach (cell; 0 .. GRID_CELLS) {
        Fragment fragment = pose.fragmentAt(cell);
        if (fragment.isPresent) {
            PocketCell place = pocket.cells[cell];
            if (place.kind == PocketKind.wall) {
                score -= CLASH_PENALTY;
            } else {
                uint matched = matchedBits(place.wanted, place.cares, fragment.properties);
                score += FILL_SCORE + MATCH_SCORE * matched - MISMATCH_SCORE * (caredBits(place.cares) - matched);
            }
        }
    }
    return score;
}

Ratio[TRANSDUCER_COUNT] efficacyOf(ref const Pocket pocket, Molecule pose) {
    uint[TRANSDUCER_COUNT] triggers;
    uint[TRANSDUCER_COUNT] touched;
    uint brakes = 0;
    uint braked = 0;
    foreach (cell; 0 .. GRID_CELLS) {
        PocketCell place = pocket.cells[cell];
        bool filled = pose.fragmentAt(cell).isPresent;
        if (place.kind == PocketKind.trigger) {
            triggers[place.transducer] += 1;
            if (filled) {
                touched[place.transducer] += 1;
            }
        } else if (place.kind == PocketKind.brake) {
            brakes += 1;
            if (filled) {
                braked += 1;
            }
        }
    }
    float brake = 0;
    if (brakes > 0) {
        brake = cast(float) braked / brakes;
    }
    Ratio[TRANSDUCER_COUNT] efficacy;
    foreach (transducer; 0 .. TRANSDUCER_COUNT) {
        float driven = 0;
        if (triggers[transducer] > 0) {
            driven = cast(float) touched[transducer] / triggers[transducer];
        }
        efficacy[transducer] = Ratio(clamped(driven - brake, -EFFICACY_LIMIT.value, EFFICACY_LIMIT.value));
    }
    return efficacy;
}

Binding bindingOf(ref const Pocket pocket, Molecule molecule) {
    uint best = 0;
    float bestScore = poseScore(pocket, molecule);
    foreach (rotation; 1 .. ROTATION_COUNT) {
        float score = poseScore(pocket, molecule.rotated(rotation));
        if (score > bestScore) {
            best = rotation;
            bestScore = score;
        }
    }
    Molecule pose = molecule.rotated(best);
    return Binding(Ratio(expf((REFERENCE_SCORE - bestScore) * BINDING_SCALE)), efficacyOf(pocket, pose), bestScore, cast(ubyte) best);
}

struct BindingKey {
    Molecule molecule;
    Pocket pocket;

    size_t toHash() const {
        return molecule.toHash() ^ (pocket.toHash() * 31);
    }
}

struct BindingCache {
    HashMap!(BindingKey, Binding) known;

    Binding bindingOf(ref const Pocket pocket, Molecule molecule) {
        BindingKey key = BindingKey(molecule, pocket);
        Binding* found = known.find(key);
        if (found !is null) {
            return *found;
        } else {
            Binding made = .bindingOf(pocket, molecule);
            known.insert(key, made);
            return made;
        }
    }

    void release() {
        known.release();
    }
}
