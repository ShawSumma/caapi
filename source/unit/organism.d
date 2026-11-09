module unit.organism;

import base.maybe : Maybe;
import base.splitmix : SplitMix;
import base.units : Ratio;
import common.biology.genome : Genome, Receptor, halfOf;
import common.biology.molecule : Molecule;
import common.biology.occupancy : occupanciesOf;
import common.biology.organism : BULKY, CHARGED, Organism, POLAR, brake, cellNamed, open, starterDoses, starterGenome, trigger, wall;
import common.biology.pocket : HalfPocket, bindingOf;
import common.biology.wild : WildGenes, productFrom;

enum uint STARTER_GENES = 5;
enum uint STARTER_DOSES = 3;
enum float FAINT_EXPRESSION = 0.5f;
enum uint WILD_SAMPLES = 2000;
enum ulong WILD_SALT = 0x5A_4D1E;
enum Ratio WILD_DOSE = Ratio(1);
enum Ratio ACTING = Ratio(0.1f);
enum float LEAST_ACTING_SHARE = 0.01f;
enum float MOST_ACTING_SHARE = 0.15f;
enum uint SELECTIVE_RECEPTORS = 2;
enum float LEAST_SELECTIVE_SHARE = 0.5f;

unittest {
    assert(cellNamed("wall").value == wall());
    assert(cellNamed("brake").value == brake());
    assert(cellNamed("trigger-1").value == trigger(1));
    assert(cellNamed("open-polar+bulky").value == open(POLAR | BULKY));
    assert(!cellNamed("trigger-2").exists);
    assert(!cellNamed("open-sticky").exists);
    assert(!cellNamed("open-").exists);
}

unittest {
    Genome genome = starterGenome();
    assert(genome.count == STARTER_GENES);
    HalfPocket expected = HalfPocket([wall(), open(POLAR), wall(), trigger(0), open(BULKY), trigger(0), wall(), open(CHARGED), wall(), open(POLAR), wall(), trigger(0), wall()]);
    assert(halfOf(genome.genes[0]) == expected);
    assert(genome.genes[2].expression.value == FAINT_EXPRESSION);
    assert(starterDoses.length == STARTER_DOSES);
}

uint receptorsActedOn(ref const Organism organism, Molecule molecule) {
    uint count = 0;
    foreach (ref receptor; organism.receptors.slice()) {
        if (occupancyAlone(WILD_DOSE, bindingOf(receptor.pocket, molecule).affinity) > ACTING) {
            count += 1;
        }
    }
    return count;
}

Ratio occupancyAlone(Ratio level, Ratio affinity) {
    Ratio[1] concentrations = [level];
    Ratio[1] affinities = [affinity];
    Ratio[1] occupied;
    occupanciesOf(concentrations[], affinities[], occupied[]);
    return occupied[0];
}

unittest {
    Organism organism = Organism.make(starterGenome());
    SplitMix draw = SplitMix(WILD_SALT);
    uint acting = 0;
    uint selective = 0;
    foreach (_; 0 .. WILD_SAMPLES) {
        WildGenes genes;
        foreach (ref seed; genes.seeds) {
            seed = draw.next();
        }
        uint reach = organism.receptorsActedOn(productFrom(Maybe!Molecule.init, genes));
        if (reach > 0) {
            acting += 1;
        }
        if (reach > 0 && reach <= SELECTIVE_RECEPTORS) {
            selective += 1;
        }
    }
    float share = cast(float) acting / WILD_SAMPLES;
    assert(share > LEAST_ACTING_SHARE && share < MOST_ACTING_SHARE);
    assert(cast(float) selective / acting >= LEAST_SELECTIVE_SHARE);
    organism.release();
}

unittest {
    Organism organism = Organism.make(starterGenome());
    foreach (ref given; starterDoses.slice()) {
        uint target = 0;
        foreach (index, ref receptor; organism.receptors.slice()) {
            if (bindingOf(receptor.pocket, given.molecule).affinity < bindingOf(organism.receptors.ptr[target].pocket, given.molecule).affinity) {
                target = cast(uint) index;
            }
        }
        Receptor aimed = organism.receptors.ptr[target];
        assert(aimed.firstHalf == aimed.secondHalf);
        Ratio level = bindingOf(aimed.pocket, given.molecule).affinity;
        foreach (ref receptor; organism.receptors.slice()) {
            if (receptor.firstHalf != aimed.firstHalf && receptor.secondHalf != aimed.firstHalf) {
                assert(!(occupancyAlone(level, bindingOf(receptor.pocket, given.molecule).affinity) > ACTING));
            }
        }
    }
    organism.release();
}
