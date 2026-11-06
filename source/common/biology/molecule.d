module common.biology.molecule;

import base.murmur : Hash128, murmurHash3;

enum uint GRID_SIDE = 3;
enum uint GRID_CELLS = GRID_SIDE * GRID_SIDE * GRID_SIDE;
enum uint CENTER_CELL = GRID_CELLS / 2;
enum uint FRAGMENT_BITS = 4;
enum uint CELLS_PER_WORD = 64 / FRAGMENT_BITS;
enum ubyte FRAGMENT_MASK = (1 << FRAGMENT_BITS) - 1;
enum ubyte PRESENT = 1 << 3;
enum ubyte PROPERTY_MASK = PRESENT - 1;
enum uint PROPERTY_COUNT = 3;
enum uint ROTATION_COUNT = 24;
enum uint AXES = 3;
enum ulong CONJUGATED_BIT = 1UL << (GRID_CELLS * FRAGMENT_BITS - 64);

enum Property : ubyte {
    bulky,
    charged,
    polar,
}

struct Fragment {
    ubyte bits;

    static Fragment of(ubyte properties) {
        return Fragment(cast(ubyte)(PRESENT | (properties & PROPERTY_MASK)));
    }

    bool isPresent() const {
        return (bits & PRESENT) != 0;
    }

    ubyte properties() const {
        return bits & PROPERTY_MASK;
    }

    bool has(Property property) const {
        return (bits & (1 << property)) != 0;
    }
}

ubyte propertyBit(Property property) {
    return cast(ubyte)(1 << property);
}

struct Molecule {
    ulong[2] packed;

    size_t toHash() const {
        Hash128 hash = murmurHash3((cast(const(ubyte)*) packed.ptr)[0 .. packed.sizeof]);
        return cast(size_t) hash.first;
    }
}

Fragment fragmentAt(Molecule molecule, uint cell) {
    return Fragment(cast(ubyte)((molecule.packed[cell / CELLS_PER_WORD] >> (FRAGMENT_BITS * (cell % CELLS_PER_WORD))) & FRAGMENT_MASK));
}

Molecule withFragment(Molecule molecule, uint cell, Fragment fragment) {
    Molecule made = molecule;
    uint shift = FRAGMENT_BITS * (cell % CELLS_PER_WORD);
    made.packed[cell / CELLS_PER_WORD] = (made.packed[cell / CELLS_PER_WORD] & ~(cast(ulong) FRAGMENT_MASK << shift)) | (cast(ulong) fragment.bits << shift);
    return made;
}

bool isConjugated(Molecule molecule) {
    return (molecule.packed[1] & CONJUGATED_BIT) != 0;
}

Molecule conjugated(Molecule molecule) {
    Molecule made = molecule;
    made.packed[1] |= CONJUGATED_BIT;
    return made;
}

uint fragmentCount(Molecule molecule) {
    uint count = 0;
    foreach (cell; 0 .. GRID_CELLS) {
        if (molecule.fragmentAt(cell).isPresent) {
            count += 1;
        }
    }
    return count;
}

struct GridPoint {
    int x;
    int y;
    int z;
}

GridPoint pointOf(uint cell) {
    return GridPoint(cast(int)(cell % GRID_SIDE) - 1, cast(int)(cell / GRID_SIDE % GRID_SIDE) - 1, cast(int)(cell / (GRID_SIDE * GRID_SIDE)) - 1);
}

uint cellOf(GridPoint point) {
    return cast(uint)((point.x + 1) + GRID_SIDE * (point.y + 1) + GRID_SIDE * GRID_SIDE * (point.z + 1));
}

GridPoint inverted(GridPoint point) {
    return GridPoint(-point.x, -point.y, -point.z);
}

struct SignedPermutation {
    uint[AXES] from;
    int[AXES] sign;

    GridPoint apply(GridPoint point) const {
        int[AXES] coordinates = [point.x, point.y, point.z];
        return GridPoint(sign[0] * coordinates[from[0]], sign[1] * coordinates[from[1]], sign[2] * coordinates[from[2]]);
    }

    int determinant() const {
        int inversions = 0;
        foreach (first; 0 .. AXES) {
            foreach (second; first + 1 .. AXES) {
                if (from[first] > from[second]) {
                    inversions += 1;
                }
            }
        }
        int result = sign[0] * sign[1] * sign[2];
        if (inversions % 2 == 1) {
            result = -result;
        }
        return result;
    }
}

immutable uint[AXES][6] AXIS_ORDERS = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]];

ubyte[GRID_CELLS][ROTATION_COUNT] rotationTable() {
    ubyte[GRID_CELLS][ROTATION_COUNT] table;
    uint found = 0;
    foreach (order; AXIS_ORDERS) {
        foreach (signs; 0 .. 8) {
            SignedPermutation turn = SignedPermutation(order, [1 - 2 * (signs & 1), 1 - 2 * ((signs >> 1) & 1), 1 - 2 * ((signs >> 2) & 1)]);
            if (turn.determinant() == 1) {
                foreach (cell; 0 .. GRID_CELLS) {
                    table[found][cell] = cast(ubyte) cellOf(turn.apply(pointOf(cell)));
                }
                found += 1;
            }
        }
    }
    assert(found == ROTATION_COUNT);
    return table;
}

immutable ubyte[GRID_CELLS][ROTATION_COUNT] ROTATED_CELLS = rotationTable();

Molecule rotated(Molecule molecule, uint rotation) {
    Molecule made;
    made.packed[1] = molecule.packed[1] & CONJUGATED_BIT;
    foreach (cell; 0 .. GRID_CELLS) {
        made = made.withFragment(ROTATED_CELLS[rotation][cell], molecule.fragmentAt(cell));
    }
    return made;
}
