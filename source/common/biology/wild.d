module common.biology.wild;

import base.maybe : Maybe;
import base.splitmix : SplitMix;
import common.biology.metabolism : Enzyme, MotifCell, Operation, Presence, SITE_CELL, productOf;
import common.biology.molecule : Fragment, GRID_CELLS, Molecule, PROPERTY_MASK, withFragment;

enum uint WILD_GENES = 4;
enum uint SCAFFOLD_GENE = 0;
enum uint FIRST_ENZYME_GENE = 1;
enum uint ENZYME_GENES = 2;
enum uint FORM_GENE = 3;
enum ulong ROOT_WILD_SALT = 0x77_11D5_EED5;
enum ulong MUTATION_SALT = 0x0B5E_55ED_CA75;
enum ulong PARENT_SALT = 0x9A2E_7A15;
enum ulong CELL_SALT = 0xCE11_5A17;
enum float NODE_MUTATION_ODDS = 0.04f;
enum float CELL_MUTATION_ODDS = 0.1f;
enum uint LEAST_SCAFFOLD_FRAGMENTS = 4;
enum uint SCAFFOLD_FRAGMENT_CHOICES = 5;
enum uint OPERATION_COUNT = Operation.max + 1;

struct WildGenes {
    ulong[WILD_GENES] seeds;

    static WildGenes ofRoot(ulong worldSalt) {
        WildGenes genes;
        foreach (index; 0 .. WILD_GENES) {
            genes.seeds[index] = SplitMix(ROOT_WILD_SALT ^ worldSalt ^ index).next();
        }
        return genes;
    }
}

WildGenes inheritedGenes(const(WildGenes)[] parents, ulong spice) {
    WildGenes genes;
    foreach (index; 0 .. WILD_GENES) {
        size_t pick = cast(size_t)(SplitMix(spice ^ PARENT_SALT ^ index).next() % parents.length);
        genes.seeds[index] = mutated(parents[pick].seeds[index], spice ^ index, NODE_MUTATION_ODDS);
    }
    return genes;
}

ulong mutated(ulong seed, ulong spice, float odds) {
    SplitMix roll = SplitMix(spice ^ MUTATION_SALT);
    if (roll.roll() < odds) {
        return SplitMix(seed ^ roll.next()).next();
    } else {
        return seed;
    }
}

WildGenes cellGenes(WildGenes node, ulong cellHash) {
    WildGenes genes = node;
    uint gene = cast(uint)(SplitMix(cellHash ^ CELL_SALT).next() % WILD_GENES);
    genes.seeds[gene] = mutated(genes.seeds[gene], cellHash ^ CELL_SALT, CELL_MUTATION_ODDS);
    return genes;
}

uint differingGenes(WildGenes a, WildGenes b) {
    uint count = 0;
    foreach (index; 0 .. WILD_GENES) {
        if (a.seeds[index] != b.seeds[index]) {
            count += 1;
        }
    }
    return count;
}

Molecule scaffoldOf(ulong seed) {
    SplitMix rng = SplitMix(seed);
    uint fragments = LEAST_SCAFFOLD_FRAGMENTS + cast(uint)(rng.next() % SCAFFOLD_FRAGMENT_CHOICES);
    Molecule molecule;
    foreach (_; 0 .. fragments) {
        uint cell = cast(uint)(rng.next() % GRID_CELLS);
        molecule = molecule.withFragment(cell, Fragment.of(cast(ubyte)(rng.next() & PROPERTY_MASK)));
    }
    return molecule;
}

Enzyme enzymeFromSeed(ulong seed) {
    SplitMix rng = SplitMix(seed);
    Enzyme enzyme;
    enzyme.operation = cast(Operation)(rng.next() % OPERATION_COUNT);
    enzyme.attached = Fragment.of(cast(ubyte)(rng.next() & PROPERTY_MASK));
    enzyme.motif[SITE_CELL] = MotifCell(cast(ubyte)(rng.next() & PROPERTY_MASK), cast(ubyte)(rng.next() & PROPERTY_MASK), Presence.filled);
    return enzyme;
}

Molecule productOfGenes(WildGenes genes) {
    Molecule product = scaffoldOf(genes.seeds[SCAFFOLD_GENE]);
    foreach (index; 0 .. ENZYME_GENES) {
        Maybe!Molecule changed = enzymeFromSeed(genes.seeds[FIRST_ENZYME_GENE + index]).productOf(product);
        if (changed.exists) {
            product = changed.value;
        }
    }
    return product;
}
