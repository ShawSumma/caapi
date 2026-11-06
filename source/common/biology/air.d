module common.biology.air;

import core.stdc.math : expf;
import base.units : Ratio;
import common.biology.molecule : CENTER_CELL, Fragment, GridPoint, Molecule, Property, cellOf, propertyBit, withFragment;
import common.worldgen.climate : Climate;

enum uint GAS_COUNT = 3;
enum uint ASH_GAS = 2;
enum float AIR_STEEPNESS = 3;
enum float ASH_RELIEF = 1;

immutable string[GAS_COUNT] GAS_NAMES = ["mire", "frost", "ash"];

Molecule[GAS_COUNT] gasMolecules() {
    Molecule mire = Molecule.init.withFragment(CENTER_CELL, Fragment.of(propertyBit(Property.polar))).withFragment(cellOf(GridPoint(1, 0, 0)), Fragment.of(propertyBit(Property.charged)));
    Molecule frost = Molecule.init.withFragment(CENTER_CELL, Fragment.of(propertyBit(Property.bulky))).withFragment(cellOf(GridPoint(0, 1, 0)), Fragment.of(0));
    Molecule ash = Molecule.init.withFragment(CENTER_CELL, Fragment.of(cast(ubyte)(propertyBit(Property.bulky) | propertyBit(Property.charged)))).withFragment(cellOf(GridPoint(0, 0, 1)), Fragment.of(propertyBit(Property.polar))).withFragment(cellOf(GridPoint(-1, 0, 0)), Fragment.of(0));
    return [mire, frost, ash];
}

immutable Molecule[GAS_COUNT] GAS_MOLECULES = gasMolecules();

struct AirMix {
    Ratio[GAS_COUNT] fractions;
}

float rising(float value) {
    return 1 / (1 + expf(-AIR_STEEPNESS * value));
}

AirMix airOf(Climate climate) {
    return AirMix([Ratio(rising(climate.wetness + climate.heat)), Ratio(rising(-climate.warmth())), Ratio(rising(climate.relief - ASH_RELIEF + climate.strata))]);
}
