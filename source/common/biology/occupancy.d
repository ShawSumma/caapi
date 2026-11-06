module common.biology.occupancy;

import base.units : Ratio;

void occupanciesOf(const(Ratio)[] concentrations, const(Ratio)[] affinities, Ratio[] occupancy) {
    assert(concentrations.length == affinities.length && occupancy.length == affinities.length);
    float denominator = 1;
    foreach (index, concentration; concentrations) {
        denominator += concentration.value / affinities[index].value;
    }
    foreach (index, concentration; concentrations) {
        occupancy[index] = Ratio(concentration.value / affinities[index].value / denominator);
    }
}
