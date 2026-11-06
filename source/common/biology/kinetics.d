module common.biology.kinetics;

import core.stdc.math : expf;
import base.units : Rate, Ratio, Time;
import common.biology.molecule : GRID_CELLS, Molecule, Property, fragmentAt, isConjugated;

enum uint MOST_SPECIES = 16;
enum Rate GUT_ABSORPTION = Rate(0.2f);
enum Rate LUNG_ABSORPTION = Rate(2.0f);
enum Rate BASE_CLEARANCE = Rate(0.02f);
enum Rate POLAR_CLEARANCE = Rate(0.01f);
enum Rate CONJUGATED_CLEARANCE = Rate(0.1f);

enum Route : ubyte {
    injected,
    inhaled,
    ingested,
}

struct Species {
    Molecule molecule;
    Ratio gut;
    Ratio lung;
    Ratio blood;
}

Rate clearanceOf(Molecule molecule) {
    uint polar = 0;
    foreach (cell; 0 .. GRID_CELLS) {
        if (molecule.fragmentAt(cell).isPresent && molecule.fragmentAt(cell).has(Property.polar)) {
            polar += 1;
        }
    }
    Rate clearance = BASE_CLEARANCE + POLAR_CLEARANCE * polar;
    if (molecule.isConjugated) {
        clearance = clearance + CONJUGATED_CLEARANCE;
    }
    return clearance;
}

float absorbedInto(float held, Rate absorption, Rate clearance, Time step) {
    float a = absorption.value;
    float k = clearance.value;
    float t = step.value;
    if (a == k) {
        return a * held * t * expf(-k * t);
    } else {
        return a * held * (expf(-a * t) - expf(-k * t)) / (k - a);
    }
}

struct Body {
    Species[MOST_SPECIES] species;
    uint count;

    uint indexOf(Molecule molecule) const {
        uint index = 0;
        while (index < count && species[index].molecule != molecule) {
            index += 1;
        }
        return index;
    }

    bool hasRoomFor(Molecule molecule) const {
        return indexOf(molecule) < count || count < MOST_SPECIES;
    }

    Species* speciesFor(Molecule molecule) {
        uint index = indexOf(molecule);
        if (index == count) {
            assert(count < MOST_SPECIES);
            species[index] = Species(molecule);
            count += 1;
        }
        return &species[index];
    }

    void dose(Molecule molecule, Ratio amount, Route route) {
        Species* held = speciesFor(molecule);
        final switch (route) {
            case Route.injected:
                held.blood = held.blood + amount;
                break;
            case Route.inhaled:
                held.lung = held.lung + amount;
                break;
            case Route.ingested:
                held.gut = held.gut + amount;
                break;
        }
    }

    void advance(Time step) {
        foreach (ref held; species[0 .. count]) {
            Rate clearance = clearanceOf(held.molecule);
            float blood = held.blood.value * expf(-(clearance * step).value) + absorbedInto(held.gut.value, GUT_ABSORPTION, clearance, step) + absorbedInto(held.lung.value, LUNG_ABSORPTION, clearance, step);
            held.gut = held.gut * expf(-(GUT_ABSORPTION * step).value);
            held.lung = held.lung * expf(-(LUNG_ABSORPTION * step).value);
            held.blood = Ratio(blood);
        }
    }

    Ratio bloodOf(Molecule molecule) const {
        uint index = indexOf(molecule);
        if (index < count) {
            return species[index].blood;
        } else {
            return Ratio(0);
        }
    }
}
