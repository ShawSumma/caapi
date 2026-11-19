module plugins.pharmacology.catalog;

import plugins.pharmacology.molecule : CONJUGATED_BIT, Fragment, GRID_CELLS, Molecule, PROPERTY_MASK, ROTATION_COUNT, conjugated, fragmentAt, isConjugated, rotated, withFragment;

enum uint CALL_DIGITS = GRID_CELLS + 1;
enum uint CELL_STATES = PROPERTY_MASK + 2;

uint digitOf(Fragment fragment) {
    if (fragment.isPresent) {
        return fragment.properties + 1;
    } else {
        return 0;
    }
}

Fragment fragmentOf(uint digit) {
    if (digit == 0) {
        return Fragment.init;
    } else {
        return Fragment.of(cast(ubyte)(digit - 1));
    }
}

bool isBefore(Molecule first, Molecule second) {
    return first.packed[1] < second.packed[1] || (first.packed[1] == second.packed[1] && first.packed[0] < second.packed[0]);
}

Molecule canonical(Molecule molecule) {
    Molecule least = molecule;
    foreach (rotation; 0 .. ROTATION_COUNT) {
        Molecule turned = rotated(molecule, rotation);
        if (isBefore(turned, least)) {
            least = turned;
        }
    }
    return least;
}

char[CALL_DIGITS] callNumber(Molecule molecule) {
    Molecule shelf = canonical(molecule);
    char[CALL_DIGITS] digits;
    digits[0] = '0';
    if (isConjugated(shelf)) {
        digits[0] = '1';
    }
    foreach (cell; 0 .. GRID_CELLS) {
        digits[cell + 1] = cast(char)('0' + digitOf(shelf.fragmentAt(cell)));
    }
    return digits;
}

Molecule cycledAt(Molecule molecule, uint cell) {
    uint next = (digitOf(molecule.fragmentAt(cell)) + 1) % CELL_STATES;
    return molecule.withFragment(cell, fragmentOf(next));
}

Molecule toggledConjugation(Molecule molecule) {
    if (isConjugated(molecule)) {
        Molecule made = molecule;
        made.packed[1] = molecule.packed[1] & ~CONJUGATED_BIT;
        return made;
    } else {
        return conjugated(molecule);
    }
}
