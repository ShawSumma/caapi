module unit.molecule;

import common.biology.molecule : CENTER_CELL, Fragment, GRID_CELLS, Molecule, ROTATED_CELLS, ROTATION_COUNT, fragmentAt, fragmentCount, rotated, withFragment;

enum ubyte SAMPLE_PROPERTIES = 0b101;

unittest {
    foreach (rotation; 0 .. ROTATION_COUNT) {
        assert(ROTATED_CELLS[rotation][CENTER_CELL] == CENTER_CELL);
        bool[GRID_CELLS] seen;
        foreach (cell; 0 .. GRID_CELLS) {
            assert(!seen[ROTATED_CELLS[rotation][cell]]);
            seen[ROTATED_CELLS[rotation][cell]] = true;
        }
        foreach (other; rotation + 1 .. ROTATION_COUNT) {
            assert(ROTATED_CELLS[rotation] != ROTATED_CELLS[other]);
        }
    }
}

unittest {
    Molecule molecule;
    foreach (cell; 0 .. GRID_CELLS) {
        molecule = molecule.withFragment(cell, Fragment.of(cast(ubyte)(cell % 8)));
    }
    foreach (cell; 0 .. GRID_CELLS) {
        assert(molecule.fragmentAt(cell) == Fragment.of(cast(ubyte)(cell % 8)));
    }
    Molecule single = Molecule.init.withFragment(2, Fragment.of(SAMPLE_PROPERTIES));
    foreach (rotation; 0 .. ROTATION_COUNT) {
        Molecule turned = single.rotated(rotation);
        assert(turned.fragmentCount == 1);
        assert(turned.fragmentAt(ROTATED_CELLS[rotation][2]) == Fragment.of(SAMPLE_PROPERTIES));
    }
}
