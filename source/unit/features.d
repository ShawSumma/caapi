module unit.features;

import core.math : sqrt;
import core.stdc.math : fabsf;
import common.character.features : CELL_CORNERS, Hexahedron, Quad;

enum float TOLERANCE = 1e-5f;

unittest {
    Hexahedron cube;
    foreach (corner; 0 .. CELL_CORNERS) {
        cube.corners[corner] = [cast(float)(corner & 1), cast(float)((corner >> 1) & 1), cast(float)((corner >> 2) & 1)];
    }
    Quad top = cube.face(1, 1);
    assert(top.normal[1] > 1 - TOLERANCE);
    float[3] above = [0.5f, 2.0f, 0.5f];
    assert(top.isAbove(above));
    float[3] aside = [1.5f, 2.0f, 0.5f];
    assert(!top.isAbove(aside));
    Quad bottom = cube.face(1, -1);
    assert(bottom.normal[1] < -1 + TOLERANCE);
    float[3] inside = [0.5f, 0.5f, 0.5f];
    assert(cube.distanceTo(inside) == 0);
    assert(fabsf(cube.distanceTo(above) - 1) < TOLERANCE);
    float[3] diagonal = [2.0f, 2.0f, 0.5f];
    assert(fabsf(cube.distanceTo(diagonal) - sqrt(2.0f)) < TOLERANCE);
}
