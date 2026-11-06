module common.biology.organism;

import base.array : Array;
import base.units : Ratio, Time;
import common.biology.genome : Genome, Receptor, assembleReceptors, enzymeGene, enzymesOf, receptorGene;
import common.biology.kinetics : Body, MOST_SPECIES, Route;
import common.biology.metabolism : Enzyme, MotifCell, Operation, Presence, SITE_CELL, metabolize;
import common.biology.molecule : Fragment, GRID_CELLS, Molecule, Property, propertyBit, withFragment;
import common.biology.occupancy : occupanciesOf;
import common.biology.pocket : Binding, BindingCache, HalfPocket, Pocket, PocketCell, PocketKind, TRANSDUCER_COUNT, joined;
import common.biology.signaling : Signaling;

enum Time BIOLOGY_TICK = Time(0.05f);
enum ubyte BULKY = 1 << Property.bulky;
enum ubyte CHARGED = 1 << Property.charged;
enum ubyte POLAR = 1 << Property.polar;
enum ubyte ALL_PROPERTIES = BULKY | CHARGED | POLAR;

PocketCell wall() {
    return PocketCell(PocketKind.wall, 0, 0, 0);
}

PocketCell open(ubyte wanted) {
    return PocketCell(PocketKind.open, wanted, ALL_PROPERTIES, 0);
}

PocketCell trigger(ubyte transducer) {
    return PocketCell(PocketKind.trigger, 0, 0, transducer);
}

PocketCell brake() {
    return PocketCell(PocketKind.brake, 0, 0, 0);
}

immutable HalfPocket[3] STARTER_HALVES = [
    HalfPocket([wall(), open(POLAR), wall(), trigger(0), open(BULKY), trigger(0), wall(), open(CHARGED), wall(), open(POLAR), wall(), trigger(0), wall()]),
    HalfPocket([wall(), open(CHARGED), wall(), trigger(1), open(POLAR | BULKY), trigger(1), wall(), open(BULKY), wall(), wall(), open(CHARGED), wall(), trigger(1)]),
    HalfPocket([wall(), open(BULKY | CHARGED), wall(), brake(), open(POLAR), wall(), wall(), open(BULKY), wall(), open(CHARGED), wall(), wall(), brake()]),
];

immutable Ratio[3] STARTER_EXPRESSION = [Ratio(1), Ratio(1), Ratio(0.5f)];

Enzyme enzymeAt(Operation operation, ubyte wanted) {
    Enzyme enzyme;
    enzyme.operation = operation;
    enzyme.motif[SITE_CELL] = MotifCell(wanted, ALL_PROPERTIES, Presence.filled);
    return enzyme;
}

immutable Enzyme[2] STARTER_ENZYMES = [enzymeAt(Operation.oxidize, BULKY | CHARGED), enzymeAt(Operation.conjugate, POLAR | CHARGED)];
immutable Ratio STARTER_ENZYME_EXPRESSION = Ratio(1);

Genome starterGenome() {
    Genome genome;
    foreach (index, half; STARTER_HALVES) {
        genome.add(receptorGene(half, STARTER_EXPRESSION[index]));
    }
    foreach (enzyme; STARTER_ENZYMES) {
        genome.add(enzymeGene(enzyme, STARTER_ENZYME_EXPRESSION));
    }
    return genome;
}

Molecule complementOf(ref const Pocket pocket, PocketKind skipped) {
    Molecule molecule;
    foreach (cell; 0 .. GRID_CELLS) {
        PocketCell place = pocket.cells[cell];
        if (place.kind != PocketKind.wall && place.kind != skipped) {
            molecule = molecule.withFragment(cell, Fragment.of(place.wanted));
        }
    }
    return molecule;
}

struct Dose {
    Molecule molecule;
    Ratio amount;
    Route route;
}

enum Ratio DOSE_AMOUNT = Ratio(2);

Dose[3] starterDoses() {
    Pocket first = joined(STARTER_HALVES[0], STARTER_HALVES[0]);
    Pocket second = joined(STARTER_HALVES[1], STARTER_HALVES[1]);
    Pocket third = joined(STARTER_HALVES[2], STARTER_HALVES[2]);
    return [Dose(complementOf(first, PocketKind.brake), DOSE_AMOUNT, Route.ingested), Dose(complementOf(second, PocketKind.brake), DOSE_AMOUNT, Route.inhaled), Dose(complementOf(third, PocketKind.trigger), DOSE_AMOUNT, Route.injected)];
}

immutable Dose[3] STARTER_DOSES = starterDoses();

struct Organism {
    Genome genome;
    Array!Receptor receptors;
    Array!Enzyme enzymes;
    Array!Ratio occupancy;
    Body body;
    Signaling signaling;
    BindingCache cache;
    Ratio[TRANSDUCER_COUNT] activation;
    Time owed;

    static Organism make(Genome chosen) {
        Organism organism;
        organism.genome = chosen;
        assembleReceptors(organism.genome, organism.receptors);
        enzymesOf(organism.genome, organism.enzymes);
        organism.occupancy.resize(organism.receptors.length);
        organism.signaling = Signaling.atRest();
        return organism;
    }

    void dose(Dose given) {
        if (body.hasRoomFor(given.molecule)) {
            body.dose(given.molecule, given.amount, given.route);
        }
    }

    void advance(Time elapsed) {
        owed = owed + elapsed;
        while (owed >= BIOLOGY_TICK) {
            tick(BIOLOGY_TICK);
            owed = owed - BIOLOGY_TICK;
        }
    }

    void tick(Time step) {
        metabolize(body, enzymes.slice(), step);
        body.advance(step);
        Ratio[MOST_SPECIES] concentrations;
        Ratio[MOST_SPECIES] affinities;
        Ratio[MOST_SPECIES] occupied;
        Binding[MOST_SPECIES] bindings;
        activation = Ratio(0);
        foreach (index, ref receptor; receptors.slice()) {
            foreach (held; 0 .. body.count) {
                bindings[held] = cache.bindingOf(receptor.pocket, body.species[held].molecule);
                concentrations[held] = body.species[held].blood;
                affinities[held] = bindings[held].affinity;
            }
            occupanciesOf(concentrations[0 .. body.count], affinities[0 .. body.count], occupied[0 .. body.count]);
            float total = 0;
            foreach (held; 0 .. body.count) {
                total += occupied[held].value;
                foreach (transducer; 0 .. TRANSDUCER_COUNT) {
                    activation[transducer] = activation[transducer] + Ratio(receptor.amount.value * occupied[held].value * bindings[held].efficacy[transducer].value);
                }
            }
            occupancy.ptr[index] = Ratio(total);
        }
        signaling.advance(activation, step);
    }

    void release() {
        receptors.release();
        enzymes.release();
        occupancy.release();
        cache.release();
    }
}
