module common.biology.metabolism;

import core.stdc.math : expf;
import base.maybe : Maybe;
import base.units : Rate, Ratio, Time;
import common.biology.kinetics : Body, MOST_SPECIES, Species;
import common.biology.molecule : Fragment, GRID_SIDE, GridPoint, Molecule, Property, ROTATION_COUNT, cellOf, conjugated, fragmentAt, propertyBit, rotated, withFragment;

enum uint MOTIF_SIDE = 2;
enum uint MOTIF_CELLS = MOTIF_SIDE * MOTIF_SIDE * MOTIF_SIDE;
enum uint MOTIF_PLACES = GRID_SIDE - MOTIF_SIDE + 1;
enum uint SITE_CELL = 0;
enum Rate ENZYME_RATE = Rate(0.1f);

enum Operation : ubyte {
    cleave,
    attach,
    oxidize,
    conjugate,
}

enum Presence : ubyte {
    any,
    filled,
    empty,
}

struct MotifCell {
    ubyte wanted;
    ubyte cares;
    Presence presence;
}

struct Enzyme {
    MotifCell[MOTIF_CELLS] motif;
    Fragment attached;
    Operation operation;
}

GridPoint motifPoint(uint index, GridPoint corner) {
    return GridPoint(corner.x + cast(int)(index % MOTIF_SIDE), corner.y + cast(int)(index / MOTIF_SIDE % MOTIF_SIDE), corner.z + cast(int)(index / (MOTIF_SIDE * MOTIF_SIDE)));
}

bool isMotifCellMatched(MotifCell wanted, Fragment fragment) {
    final switch (wanted.presence) {
        case Presence.empty:
            return !fragment.isPresent;
        case Presence.filled:
            return fragment.isPresent && ((fragment.properties ^ wanted.wanted) & wanted.cares) == 0;
        case Presence.any:
            return !fragment.isPresent || ((fragment.properties ^ wanted.wanted) & wanted.cares) == 0;
    }
}

bool isMotifAt(Enzyme enzyme, Molecule molecule, GridPoint corner) {
    uint index = 0;
    while (index < MOTIF_CELLS && isMotifCellMatched(enzyme.motif[index], molecule.fragmentAt(cellOf(motifPoint(index, corner))))) {
        index += 1;
    }
    return index == MOTIF_CELLS;
}

Maybe!Molecule productOf(Enzyme enzyme, Molecule molecule) {
    foreach (rotation; 0 .. ROTATION_COUNT) {
        Molecule turned = molecule.rotated(rotation);
        foreach (z; 0 .. MOTIF_PLACES) {
            foreach (y; 0 .. MOTIF_PLACES) {
                foreach (x; 0 .. MOTIF_PLACES) {
                    GridPoint corner = GridPoint(x - 1, y - 1, z - 1);
                    if (enzyme.isMotifAt(turned, corner)) {
                        Molecule changed = enzyme.applied(turned, cellOf(motifPoint(SITE_CELL, corner)));
                        if (changed != turned) {
                            return Maybe!Molecule.of(changed);
                        }
                    }
                }
            }
        }
    }
    return Maybe!Molecule.init;
}

Molecule applied(Enzyme enzyme, Molecule molecule, uint site) {
    Fragment at = molecule.fragmentAt(site);
    final switch (enzyme.operation) {
        case Operation.cleave:
            return molecule.withFragment(site, Fragment.init);
        case Operation.attach:
            if (at.isPresent) {
                return molecule;
            } else {
                return molecule.withFragment(site, enzyme.attached);
            }
        case Operation.oxidize:
            if (at.isPresent) {
                return molecule.withFragment(site, Fragment.of(cast(ubyte)(at.properties ^ propertyBit(Property.polar))));
            } else {
                return molecule;
            }
        case Operation.conjugate:
            return molecule.conjugated();
    }
}

void metabolize(ref Body body, const(Enzyme)[] enzymes, Time step) {
    float converted = 1 - expf(-(ENZYME_RATE * step).value);
    uint existing = body.count;
    foreach (enzyme; enzymes) {
        foreach (index; 0 .. existing) {
            Maybe!Molecule product = enzyme.productOf(body.species[index].molecule);
            if (product.exists && body.hasRoomFor(product.value)) {
                Ratio gut = body.species[index].gut * converted;
                Ratio blood = body.species[index].blood * converted;
                body.species[index].gut = body.species[index].gut - gut;
                body.species[index].blood = body.species[index].blood - blood;
                Species* made = body.speciesFor(product.value);
                made.gut = made.gut + gut;
                made.blood = made.blood + blood;
            }
        }
    }
}
