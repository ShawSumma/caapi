module unit.chemistry;

import base.splitmix : SplitMix;
import base.units : Ratio, Time;
import common.biology.breeding : productOf;
import common.biology.genome : Receptor;
import common.biology.kinetics : Route;
import common.biology.molecule : Molecule;
import common.biology.occupancy : occupanciesOf;
import common.biology.organism : Dose, Organism, starterGenome;
import common.biology.pocket : bindingOf;
import common.biology.wild : WildGenes;
import common.perception : Channel, Perception, felt;
import unit.named : blockNamed;

enum uint SAMPLES = 40;
enum ulong SAMPLE_SALT = 0xC4E3_15;
enum Ratio DOSE = Ratio(1);
enum Ratio CLOSING_DOSE = Ratio(4);
enum Time SETTLE = Time(4);
enum Ratio ACTING = Ratio(0.1f);
enum float FELT = 0.05f;
enum float LEAST_FAITHFUL = 0.7f;
enum float MOST_ACTING_UNTHEMED = 0.2f;
enum float MOST_DIRTY = 0.1f;
enum uint DIRTY_STRAYS = 2;
enum ubyte HALF_A = 1;
enum ubyte HALF_B = 2;
enum ubyte HALF_C = 4;

enum Direction : ubyte {
    raises,
    lowers,
}

struct Theme {
    string species;
    ubyte halves;
    Channel channel;
    Direction direction;
}

immutable Theme[] THEMES = [
    Theme("base:fern", HALF_A, Channel.revealMist, Direction.raises),
    Theme("base:mushroom-cap", HALF_B, Channel.afterimage, Direction.raises),
    Theme("base:cactus", HALF_B, Channel.fieldOfView, Direction.raises),
    Theme("base:flower", HALF_A | HALF_B, Channel.gravity, Direction.lowers),
    Theme("base:petals", HALF_A | HALF_B, Channel.jumpHeight, Direction.raises),
    Theme("base:pollen", HALF_A | HALF_B, Channel.gravity, Direction.lowers),
];

struct Closer {
    string species;
    ubyte halves;
}

immutable Closer[] CLOSERS = [
    Closer("base:thornbush", HALF_A),
    Closer("base:moss", HALF_C),
];

immutable string[] UNTHEMED = ["base:oak-leaves", "base:birch-leaves", "base:spruce-leaves", "base:jungle-leaves", "base:acacia-leaves", "base:cherry-leaves", "base:maple-leaves", "base:willow-leaves"];

WildGenes sampled(ref SplitMix draw) {
    WildGenes genes;
    foreach (ref seed; genes.seeds) {
        seed = draw.next();
    }
    return genes;
}

Ratio heldAt(Ratio level, Ratio affinity) {
    Ratio[1] concentrations = [level];
    Ratio[1] affinities = [affinity];
    Ratio[1] occupied;
    occupanciesOf(concentrations[], affinities[], occupied[]);
    return occupied[0];
}

ubyte bitOf(ubyte half) {
    return cast(ubyte)(1 << half);
}

bool isTargeted(ref const Receptor receptor, ubyte halves) {
    return (bitOf(receptor.firstHalf) & halves) != 0 || (bitOf(receptor.secondHalf) & halves) != 0;
}

bool isMainlyOn(ref const Organism organism, Molecule product, ubyte halves) {
    uint best = 0;
    foreach (index, ref receptor; organism.receptors.slice()) {
        if (bindingOf(receptor.pocket, product).affinity < bindingOf(organism.receptors.ptr[best].pocket, product).affinity) {
            best = cast(uint) index;
        }
    }
    return organism.isActing(product) && organism.receptors.ptr[best].isTargeted(halves);
}

bool isDirty(ref const Organism organism, Molecule product, ubyte halves) {
    uint astray = 0;
    foreach (ref receptor; organism.receptors.slice()) {
        if (heldAt(DOSE, bindingOf(receptor.pocket, product).affinity) > ACTING && !receptor.isTargeted(halves)) {
            astray += 1;
        }
    }
    return astray >= DIRTY_STRAYS;
}

bool isActing(ref const Organism organism, Molecule product) {
    uint index = 0;
    while (index < organism.receptors.length && !(heldAt(DOSE, bindingOf(organism.receptors.ptr[index].pocket, product).affinity) > ACTING)) {
        index += 1;
    }
    return index < organism.receptors.length;
}

float feltAfter(const(Dose)[] doses, Channel channel) {
    Organism organism = Organism.make(starterGenome());
    foreach (given; doses) {
        organism.dose(given);
    }
    organism.advance(SETTLE);
    Perception made = felt(Perception.init, organism.signaling.signals[]);
    organism.release();
    return made.level[channel].value;
}

bool isFeltAs(float level, Direction direction) {
    final switch (direction) {
        case Direction.raises:
            return level > FELT;
        case Direction.lowers:
            return level < -FELT;
    }
}

unittest {
    Organism organism = Organism.make(starterGenome());
    foreach (ref theme; THEMES) {
        SplitMix draw = SplitMix(SAMPLE_SALT);
        uint mainly = 0;
        uint dirty = 0;
        uint feltRight = 0;
        foreach (_; 0 .. SAMPLES) {
            Dose[1] taken = [Dose(productOf(blockNamed(theme.species), sampled(draw)), DOSE, Route.injected)];
            if (organism.isMainlyOn(taken[0].molecule, theme.halves)) {
                mainly += 1;
            }
            if (organism.isDirty(taken[0].molecule, theme.halves)) {
                dirty += 1;
            }
            if (isFeltAs(feltAfter(taken[], theme.channel), theme.direction)) {
                feltRight += 1;
            }
        }
        assert(mainly >= LEAST_FAITHFUL * SAMPLES);
        assert(dirty <= MOST_DIRTY * SAMPLES);
        assert(feltRight >= LEAST_FAITHFUL * SAMPLES);
    }
    organism.release();
}

unittest {
    Organism organism = Organism.make(starterGenome());
    foreach (species; UNTHEMED) {
        SplitMix draw = SplitMix(SAMPLE_SALT);
        uint acting = 0;
        foreach (_; 0 .. SAMPLES) {
            if (organism.isActing(productOf(blockNamed(species), sampled(draw)))) {
                acting += 1;
            }
        }
        assert(acting <= MOST_ACTING_UNTHEMED * SAMPLES);
    }
    organism.release();
}

unittest {
    Organism organism = Organism.make(starterGenome());
    foreach (ref closer; CLOSERS) {
        SplitMix draw = SplitMix(SAMPLE_SALT);
        uint mainly = 0;
        uint dirty = 0;
        uint closed = 0;
        foreach (_; 0 .. SAMPLES) {
            Dose[2] both = [Dose(productOf(blockNamed("base:fern"), sampled(draw)), DOSE, Route.injected), Dose(productOf(blockNamed(closer.species), sampled(draw)), CLOSING_DOSE, Route.injected)];
            if (organism.isMainlyOn(both[1].molecule, closer.halves)) {
                mainly += 1;
            }
            if (organism.isDirty(both[1].molecule, closer.halves)) {
                dirty += 1;
            }
            if (feltAfter(both[], Channel.revealMist) < feltAfter(both[0 .. 1], Channel.revealMist) - FELT) {
                closed += 1;
            }
        }
        assert(mainly >= LEAST_FAITHFUL * SAMPLES);
        assert(dirty <= MOST_DIRTY * SAMPLES);
        assert(closed >= LEAST_FAITHFUL * SAMPLES);
    }
    organism.release();
}
