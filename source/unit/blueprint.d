module unit.blueprint;

import common.worldgen.blueprint : Rhythm, canonicalRhythm, edgeOf;
import common.worldgen.structure : AxisOrder, LineTransform, edgeCells;

enum ubyte DIMENSION = 12;

unittest {
    int edge = edgeCells(DIMENSION);
    assert(edgeOf(-3, DIMENSION) == -1 && edgeOf(0, DIMENSION) == 0);
    assert(edgeOf(edge - 1, DIMENSION) == 0 && edgeOf(edge, DIMENSION) == 1);
    assert(edgeOf(-edge, DIMENSION) == -1 && edgeOf(-edge - 1, DIMENSION) == -2);
    LineTransform mirrored = LineTransform(2, 1, 1, -1, AxisOrder.straight);
    Rhythm local = Rhythm(8, 1, 3);
    Rhythm moved = canonicalRhythm(local, mirrored, DIMENSION);
    foreach (height; -20 .. 20) {
        assert(local.includes(height) == moved.includes(mirrored.offsetLevels * edge - 1 - height));
    }
}
