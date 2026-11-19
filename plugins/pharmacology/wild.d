module plugins.pharmacology.wild;

import base.maybe : Maybe;
import base.splitmix : SplitMix;
import common.worldgen.lineage : LINEAGE_SEEDS, Lineage, mutated;
import plugins.pharmacology.metabolism : Enzyme, MotifCell, Operation, Presence, SITE_CELL, productOf;
import plugins.pharmacology.molecule : Fragment, GRID_CELLS, Molecule, PROPERTY_MASK, fragmentAt, withFragment;

enum uint SCAFFOLD_GENE = 0;
enum uint FIRST_ENZYME_GENE = 1;
enum uint ENZYME_GENES = 2;
enum uint FORM_GENE = 3;
enum ulong CELL_SALT = 0xCE11_5A17;
enum ulong SPECIES_SALT = 0x5BEC_1E5A_17ED;
enum float SPECIES_DIVERGENCE = 0.5f;
enum float CELL_MUTATION_ODDS = 0.1f;
enum uint LEAST_SCAFFOLD_FRAGMENTS = 4;
enum uint SCAFFOLD_FRAGMENT_CHOICES = 5;
enum uint OPERATION_COUNT = Operation.max + 1;
enum float CORE_LOSS_ODDS = 0.25f;

static assert(FORM_GENE < LINEAGE_SEEDS);

Lineage speciesGenes(Lineage node, ulong species) {
    Lineage genes;
    foreach (index; 0 .. LINEAGE_SEEDS) {
        genes.seeds[index] = mutated(node.seeds[index], species * SPECIES_SALT ^ index, SPECIES_DIVERGENCE);
    }
    return genes;
}

Lineage cellGenes(Lineage node, ulong cellHash) {
    Lineage genes = node;
    uint gene = cast(uint)(SplitMix(cellHash ^ CELL_SALT).next() % LINEAGE_SEEDS);
    genes.seeds[gene] = mutated(genes.seeds[gene], cellHash ^ CELL_SALT, CELL_MUTATION_ODDS);
    return genes;
}

uint differingGenes(Lineage a, Lineage b) {
    uint count = 0;
    foreach (index; 0 .. LINEAGE_SEEDS) {
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

Molecule variantOf(Molecule core, ulong seed) {
    SplitMix rng = SplitMix(seed);
    Molecule made = core;
    foreach (cell; 0 .. GRID_CELLS) {
        if (core.fragmentAt(cell).isPresent && rng.roll() < CORE_LOSS_ODDS) {
            made = made.withFragment(cell, Fragment.init);
        }
    }
    return made;
}

Molecule productFrom(Maybe!Molecule core, Lineage genes) {
    Molecule product = scaffoldOf(genes.seeds[SCAFFOLD_GENE]);
    if (core.exists) {
        product = variantOf(core.value, genes.seeds[SCAFFOLD_GENE]);
    }
    foreach (index; 0 .. ENZYME_GENES) {
        Maybe!Molecule changed = enzymeFromSeed(genes.seeds[FIRST_ENZYME_GENE + index]).productOf(product);
        if (changed.exists) {
            product = changed.value;
        }
    }
    return product;
}
