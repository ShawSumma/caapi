module unit.kinetics;

import core.stdc.math : fabsf;
import base.numbers : LN_TWO;
import base.units : Ratio, Time;
import common.biology.kinetics : Body, MOST_SPECIES, Route, clearanceOf;
import common.biology.molecule : CENTER_CELL, Fragment, Molecule, withFragment;

enum float LEVEL_TOLERANCE = 1e-4f;
enum Ratio DOSE = Ratio(1);
enum ubyte POLAR = 0b100;
enum uint SHORT_STEPS = 400;
enum Time LONG_STEP = Time(8);
enum Time CLEARING_STEP = Time(2000);

unittest {
    Molecule molecule = Molecule.init.withFragment(CENTER_CELL, Fragment.of(POLAR));
    Body body;
    body.dose(molecule, DOSE, Route.injected);
    body.advance(Time(cast(float)(LN_TWO / clearanceOf(molecule).value)));
    assert(fabsf(body.bloodOf(molecule).value - DOSE.value / 2) <= LEVEL_TOLERANCE);
}

unittest {
    Molecule molecule = Molecule.init.withFragment(CENTER_CELL, Fragment.of(0));
    Body once;
    once.dose(molecule, DOSE, Route.ingested);
    once.dose(molecule, DOSE, Route.inhaled);
    once.advance(LONG_STEP);
    Body often;
    often.dose(molecule, DOSE, Route.ingested);
    often.dose(molecule, DOSE, Route.inhaled);
    foreach (_; 0 .. SHORT_STEPS) {
        often.advance(LONG_STEP / SHORT_STEPS);
    }
    assert(fabsf(once.bloodOf(molecule).value - often.bloodOf(molecule).value) <= LEVEL_TOLERANCE);
    assert(once.bloodOf(molecule).value > 0);
}

unittest {
    Body body;
    foreach (cell; 0 .. MOST_SPECIES) {
        body.dose(Molecule.init.withFragment(cell, Fragment.of(POLAR)), DOSE, Route.injected);
    }
    Molecule late = Molecule.init.withFragment(CENTER_CELL, Fragment.of(0));
    assert(!body.hasRoomFor(late));
    body.advance(CLEARING_STEP);
    assert(body.count == 0 && body.hasRoomFor(late));
}
