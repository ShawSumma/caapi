module unit.occupancy;

import core.stdc.math : fabsf;
import base.units : Ratio;
import common.biology.occupancy : occupanciesOf;

enum float OCCUPANCY_TOLERANCE = 1e-5f;
enum Ratio AGONIST_AFFINITY = Ratio(0.3f);
enum Ratio COMPETITOR_AFFINITY = Ratio(0.05f);
enum Ratio COMPETITOR_LEVEL = Ratio(0.2f);

unittest {
    Ratio[1] concentrations = [AGONIST_AFFINITY];
    Ratio[1] affinities = [AGONIST_AFFINITY];
    Ratio[1] occupancy;
    occupanciesOf(concentrations[], affinities[], occupancy[]);
    assert(fabsf(occupancy[0].value - 0.5f) <= OCCUPANCY_TOLERANCE);
}

unittest {
    float shift = 1 + COMPETITOR_LEVEL.value / COMPETITOR_AFFINITY.value;
    Ratio[2] concentrations = [AGONIST_AFFINITY * shift, COMPETITOR_LEVEL];
    Ratio[2] affinities = [AGONIST_AFFINITY, COMPETITOR_AFFINITY];
    Ratio[2] occupancy;
    occupanciesOf(concentrations[], affinities[], occupancy[]);
    assert(fabsf(occupancy[0].value - 0.5f) <= OCCUPANCY_TOLERANCE);
}
