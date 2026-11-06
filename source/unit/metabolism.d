module unit.metabolism;

import core.stdc.math : fabsf;
import base.maybe : Maybe;
import base.units : Ratio, Time;
import common.biology.kinetics : Body, Route, clearanceOf;
import common.biology.metabolism : Enzyme, MotifCell, Operation, Presence, SITE_CELL, metabolize, productOf;
import common.biology.molecule : CENTER_CELL, Fragment, GRID_CELLS, GridPoint, Molecule, Property, cellOf, fragmentAt, fragmentCount, isConjugated, propertyBit, withFragment;

enum float AMOUNT_TOLERANCE = 1e-5f;
enum Ratio DOSE = Ratio(1);
enum Time TICK = Time(0.5f);

Enzyme enzymeAtFilled(Operation operation, ubyte wanted, ubyte cares) {
    Enzyme enzyme;
    enzyme.operation = operation;
    enzyme.motif[SITE_CELL] = MotifCell(wanted, cares, Presence.filled);
    return enzyme;
}

uint countWith(Molecule molecule, Property property) {
    uint count = 0;
    foreach (cell; 0 .. GRID_CELLS) {
        if (molecule.fragmentAt(cell).isPresent && molecule.fragmentAt(cell).has(property)) {
            count += 1;
        }
    }
    return count;
}

unittest {
    Molecule plain = Molecule.init.withFragment(CENTER_CELL, Fragment.of(0)).withFragment(cellOf(GridPoint(1, 0, 0)), Fragment.of(propertyBit(Property.bulky)));
    Maybe!Molecule oxidized = enzymeAtFilled(Operation.oxidize, 0, propertyBit(Property.bulky)).productOf(plain);
    assert(oxidized.exists && oxidized.value.fragmentCount == 2 && countWith(oxidized.value, Property.polar) == 1 && countWith(oxidized.value, Property.bulky) == 1);
    Maybe!Molecule cleaved = enzymeAtFilled(Operation.cleave, propertyBit(Property.bulky), propertyBit(Property.bulky)).productOf(plain);
    assert(cleaved.exists && cleaved.value.fragmentCount == 1 && countWith(cleaved.value, Property.bulky) == 0);
    assert(!enzymeAtFilled(Operation.cleave, propertyBit(Property.charged), propertyBit(Property.charged)).productOf(plain).exists);
    Maybe!Molecule marked = enzymeAtFilled(Operation.conjugate, 0, 0).productOf(plain);
    assert(marked.exists && marked.value.isConjugated && clearanceOf(marked.value).value > clearanceOf(plain).value);
}

unittest {
    Molecule plain = Molecule.init.withFragment(CENTER_CELL, Fragment.of(0));
    Enzyme[1] enzymes = [enzymeAtFilled(Operation.oxidize, 0, propertyBit(Property.polar))];
    Body body;
    body.dose(plain, DOSE, Route.ingested);
    body.dose(plain, DOSE, Route.injected);
    float before = body.species[0].gut.value + body.species[0].blood.value;
    metabolize(body, enzymes[], TICK);
    assert(body.count == 2);
    float after = 0;
    foreach (ref held; body.species[0 .. body.count]) {
        after += held.gut.value + held.blood.value;
    }
    assert(fabsf(after - before) <= AMOUNT_TOLERANCE);
    assert(body.species[1].blood.value > 0 && body.species[1].gut.value > 0);
}
