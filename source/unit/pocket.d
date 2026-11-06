module unit.pocket;

import core.stdc.math : fabsf;
import common.biology.molecule : CENTER_CELL, Fragment, GRID_CELLS, GridPoint, Molecule, ROTATION_COUNT, cellOf, inverted, pointOf, rotated, withFragment;
import common.biology.pocket : Binding, HALF_CELLS, HalfPocket, Pocket, PocketCell, PocketKind, bindingOf, joined;

enum float SCORE_TOLERANCE = 1e-5f;
enum ubyte POLAR = 0b100;
enum ubyte BULKY = 0b001;

HalfPocket sampleHalf(ubyte salt) {
    HalfPocket half;
    foreach (index; 0 .. HALF_CELLS) {
        uint kind = (index * 7 + salt) % 4;
        half.cells[index] = PocketCell(cast(PocketKind) kind, cast(ubyte)((index + salt) % 8), cast(ubyte)((index * 3 + salt) % 8), cast(ubyte)(index % 2));
    }
    return half;
}

unittest {
    Pocket homomer = joined(sampleHalf(1), sampleHalf(1));
    foreach (cell; 0 .. GRID_CELLS) {
        assert(homomer.cells[cell] == homomer.cells[cellOf(inverted(pointOf(cell)))]);
    }
    Pocket heteromer = joined(sampleHalf(1), sampleHalf(2));
    uint different = 0;
    foreach (cell; 0 .. GRID_CELLS) {
        if (heteromer.cells[cell] != heteromer.cells[cellOf(inverted(pointOf(cell)))]) {
            different += 1;
        }
    }
    assert(different > 0);
}

unittest {
    Pocket pocket = joined(sampleHalf(3), sampleHalf(5));
    Molecule molecule = Molecule.init.withFragment(CENTER_CELL, Fragment.of(POLAR)).withFragment(cellOf(GridPoint(1, 0, 0)), Fragment.of(BULKY)).withFragment(cellOf(GridPoint(0, 1, -1)), Fragment.of(POLAR | BULKY));
    Binding plain = bindingOf(pocket, molecule);
    foreach (rotation; 0 .. ROTATION_COUNT) {
        assert(fabsf(bindingOf(pocket, molecule.rotated(rotation)).score - plain.score) <= SCORE_TOLERANCE);
    }
}

unittest {
    Pocket pocket;
    foreach (cell; 0 .. GRID_CELLS) {
        pocket.cells[cell] = PocketCell(PocketKind.wall, 0, 0, 0);
    }
    uint trigger = cellOf(GridPoint(1, 0, 0));
    uint brake = cellOf(GridPoint(-1, 0, 0));
    pocket.cells[CENTER_CELL] = PocketCell(PocketKind.open, POLAR, POLAR, 0);
    pocket.cells[trigger] = PocketCell(PocketKind.trigger, 0, 0, 0);
    pocket.cells[brake] = PocketCell(PocketKind.brake, 0, 0, 0);
    Molecule agonist = Molecule.init.withFragment(CENTER_CELL, Fragment.of(POLAR)).withFragment(trigger, Fragment.of(0));
    Molecule antagonist = Molecule.init.withFragment(CENTER_CELL, Fragment.of(POLAR));
    Molecule inverse = Molecule.init.withFragment(CENTER_CELL, Fragment.of(POLAR)).withFragment(brake, Fragment.of(0));
    Binding agonistBinding = bindingOf(pocket, agonist);
    Binding antagonistBinding = bindingOf(pocket, antagonist);
    assert(agonistBinding.efficacy[0].value > 0);
    assert(antagonistBinding.efficacy[0].value == 0);
    Binding inverseBinding = bindingOf(pocket, inverse);
    assert(inverseBinding.efficacy[0].value <= 0);
    Molecule clashing = antagonist.withFragment(cellOf(GridPoint(0, 1, 0)), Fragment.of(0)).withFragment(cellOf(GridPoint(0, -1, 0)), Fragment.of(0)).withFragment(cellOf(GridPoint(0, 0, 1)), Fragment.of(0));
    assert(bindingOf(pocket, clashing).affinity.value > antagonistBinding.affinity.value);
}
