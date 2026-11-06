module unit.genome;

import core.stdc.math : fabsf;
import base.array : Array;
import base.units : Ratio;
import common.biology.genome : Gene, Genome, Receptor, assembleReceptors, enzymeGene, enzymeOf, halfOf, receptorGene;
import common.biology.metabolism : Enzyme, MOTIF_CELLS, MotifCell, Operation, Presence;
import common.biology.molecule : Fragment;
import common.biology.pocket : HALF_CELLS, HalfPocket, PocketCell, PocketKind;

enum float AMOUNT_TOLERANCE = 1e-5f;

HalfPocket halfFrom(uint salt) {
    HalfPocket half;
    foreach (index; 0 .. HALF_CELLS) {
        half.cells[index] = PocketCell(cast(PocketKind)((index + salt) % 4), cast(ubyte)((index * 3 + salt) % 8), cast(ubyte)((index + 2 * salt) % 8), cast(ubyte)((index + salt) % 2));
    }
    return half;
}

unittest {
    HalfPocket half = halfFrom(5);
    Gene receptor = receptorGene(half, Ratio(1));
    assert(halfOf(receptor) == half);
    Enzyme enzyme;
    enzyme.operation = Operation.attach;
    enzyme.attached = Fragment.of(0b011);
    foreach (index; 0 .. MOTIF_CELLS) {
        enzyme.motif[index] = MotifCell(cast(ubyte)(index % 8), cast(ubyte)((index * 5) % 8), cast(Presence)(index % 3));
    }
    Gene encoded = enzymeGene(enzyme, Ratio(1));
    assert(enzymeOf(encoded) == enzyme);
}

unittest {
    Genome genome;
    genome.add(receptorGene(halfFrom(1), Ratio(1)));
    genome.add(receptorGene(halfFrom(2), Ratio(1)));
    Array!Receptor receptors;
    assembleReceptors(genome, receptors);
    assert(receptors.length == 3);
    assert(fabsf(receptors.ptr[0].amount.value - 0.5f) <= AMOUNT_TOLERANCE);
    assert(fabsf(receptors.ptr[1].amount.value - 1.0f) <= AMOUNT_TOLERANCE);
    assert(fabsf(receptors.ptr[2].amount.value - 0.5f) <= AMOUNT_TOLERANCE);
    receptors.release();
}
