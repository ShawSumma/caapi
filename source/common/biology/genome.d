module common.biology.genome;

import base.array : Array;
import base.units : Ratio;
import common.biology.metabolism : Enzyme, MOTIF_CELLS, MotifCell, Operation, Presence;
import common.biology.molecule : Fragment, PROPERTY_MASK;
import common.biology.pocket : HALF_CELLS, HalfPocket, Pocket, PocketCell, PocketKind, joined;

enum uint MOST_GENES = 16;
enum uint MOST_LETTERS = 16;
enum uint PROPERTY_FIELD_BITS = 3;
enum uint KIND_FIELD_BITS = 2;
enum ushort KIND_FIELD_MASK = (1 << KIND_FIELD_BITS) - 1;
enum uint RECEPTOR_WANTED_SHIFT = KIND_FIELD_BITS;
enum uint RECEPTOR_CARES_SHIFT = RECEPTOR_WANTED_SHIFT + PROPERTY_FIELD_BITS;
enum uint RECEPTOR_TRANSDUCER_SHIFT = RECEPTOR_CARES_SHIFT + PROPERTY_FIELD_BITS;
enum uint MOTIF_CARES_SHIFT = PROPERTY_FIELD_BITS;
enum uint MOTIF_PRESENCE_SHIFT = 2 * PROPERTY_FIELD_BITS;
enum uint ENZYME_ATTACHED_SHIFT = KIND_FIELD_BITS;
enum uint ENZYME_HEADER_LETTERS = 1;

alias Letter = ushort;

enum GeneKind : ubyte {
    receptorHalf,
    enzyme,
}

struct Gene {
    Letter[MOST_LETTERS] letters;
    Ratio expression;
    ubyte length;
    GeneKind kind;
}

struct Genome {
    Gene[MOST_GENES] genes;
    uint count;

    void add(Gene gene) {
        assert(count < MOST_GENES);
        genes[count] = gene;
        count += 1;
    }

    const(Gene)[] slice() const {
        return genes[0 .. count];
    }
}

Letter letterOf(PocketCell cell) {
    return cast(Letter)(cell.kind | (cell.wanted & PROPERTY_MASK) << RECEPTOR_WANTED_SHIFT | (cell.cares & PROPERTY_MASK) << RECEPTOR_CARES_SHIFT | (cell.transducer & 1) << RECEPTOR_TRANSDUCER_SHIFT);
}

PocketCell pocketCellOf(Letter letter) {
    return PocketCell(cast(PocketKind)(letter & KIND_FIELD_MASK), cast(ubyte)((letter >> RECEPTOR_WANTED_SHIFT) & PROPERTY_MASK), cast(ubyte)((letter >> RECEPTOR_CARES_SHIFT) & PROPERTY_MASK), cast(ubyte)((letter >> RECEPTOR_TRANSDUCER_SHIFT) & 1));
}

Gene receptorGene(HalfPocket half, Ratio expression) {
    Gene gene = Gene(Letter[MOST_LETTERS].init, expression, HALF_CELLS, GeneKind.receptorHalf);
    foreach (index, cell; half.cells) {
        gene.letters[index] = letterOf(cell);
    }
    return gene;
}

HalfPocket halfOf(ref const Gene gene) {
    assert(gene.kind == GeneKind.receptorHalf && gene.length == HALF_CELLS);
    HalfPocket half;
    foreach (index; 0 .. HALF_CELLS) {
        half.cells[index] = pocketCellOf(gene.letters[index]);
    }
    return half;
}

Letter motifLetterOf(MotifCell cell) {
    return cast(Letter)((cell.wanted & PROPERTY_MASK) | (cell.cares & PROPERTY_MASK) << MOTIF_CARES_SHIFT | cell.presence << MOTIF_PRESENCE_SHIFT);
}

MotifCell motifCellOf(Letter letter) {
    return MotifCell(cast(ubyte)(letter & PROPERTY_MASK), cast(ubyte)((letter >> MOTIF_CARES_SHIFT) & PROPERTY_MASK), cast(Presence)((letter >> MOTIF_PRESENCE_SHIFT) & KIND_FIELD_MASK));
}

Gene enzymeGene(Enzyme enzyme, Ratio expression) {
    Gene gene = Gene(Letter[MOST_LETTERS].init, expression, ENZYME_HEADER_LETTERS + MOTIF_CELLS, GeneKind.enzyme);
    gene.letters[0] = cast(Letter)(enzyme.operation | enzyme.attached.properties << ENZYME_ATTACHED_SHIFT);
    foreach (index, cell; enzyme.motif) {
        gene.letters[ENZYME_HEADER_LETTERS + index] = motifLetterOf(cell);
    }
    return gene;
}

Enzyme enzymeOf(ref const Gene gene) {
    assert(gene.kind == GeneKind.enzyme && gene.length == ENZYME_HEADER_LETTERS + MOTIF_CELLS);
    Enzyme enzyme;
    enzyme.operation = cast(Operation)(gene.letters[0] & KIND_FIELD_MASK);
    enzyme.attached = Fragment.of(cast(ubyte)((gene.letters[0] >> ENZYME_ATTACHED_SHIFT) & PROPERTY_MASK));
    foreach (index; 0 .. MOTIF_CELLS) {
        enzyme.motif[index] = motifCellOf(gene.letters[ENZYME_HEADER_LETTERS + index]);
    }
    return enzyme;
}

struct Receptor {
    Pocket pocket;
    Ratio amount;
    ubyte firstHalf;
    ubyte secondHalf;
}

void assembleReceptors(ref const Genome genome, ref Array!Receptor receptors) {
    receptors.clear();
    float total = 0;
    foreach (ref gene; genome.slice()) {
        if (gene.kind == GeneKind.receptorHalf) {
            total += gene.expression.value;
        }
    }
    ubyte firstHalf = 0;
    foreach (first, ref one; genome.slice()) {
        if (one.kind == GeneKind.receptorHalf) {
            ubyte secondHalf = firstHalf;
            foreach (second, ref other; genome.slice()[first .. $]) {
                if (other.kind == GeneKind.receptorHalf) {
                    float pairs = one.expression.value * other.expression.value / total;
                    if (secondHalf != firstHalf) {
                        pairs *= 2;
                    }
                    receptors.append(Receptor(joined(halfOf(one), halfOf(other)), Ratio(pairs), firstHalf, secondHalf));
                    secondHalf += 1;
                }
            }
            firstHalf += 1;
        }
    }
}

void enzymesOf(ref const Genome genome, ref Array!Enzyme enzymes) {
    enzymes.clear();
    foreach (ref gene; genome.slice()) {
        if (gene.kind == GeneKind.enzyme) {
            enzymes.append(enzymeOf(gene));
        }
    }
}
