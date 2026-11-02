module unit.chart;

import common.character.chart : applied, inverted;

enum float TOLERANCE = 1e-3f;

unittest {
    float[3][3] m = [
        [2, 1, 0],
        [0, 1, 0],
        [0, 0, 3],
    ];
    float[3] v = [1, 2, 3];
    float[3] back = applied(inverted(m), applied(m, v));
    foreach (axis; 0 .. 3) {
        assert(back[axis] - v[axis] < TOLERANCE && v[axis] - back[axis] < TOLERANCE);
    }
}
