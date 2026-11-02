module unit.vector3;

import base.vector3 : ZERO_VECTOR, cappedTo, cross, dot, magnitude, movedToward, rejectAlong;

enum float TOLERANCE = 1e-4f;

unittest {
    float[3] v = [3, 4, 0];
    assert(v.cappedTo(1).magnitude < 1 + TOLERANCE);
    float[3] z = [0, 0, 1];
    assert(v.cross(z).dot(v) == 0);
    float[3] reached = ZERO_VECTOR.movedToward(v, 10);
    assert(reached[0] == 3 && reached[1] == 4);
    float[3] partial = ZERO_VECTOR.movedToward(v, 1);
    assert(partial.magnitude < 1 + TOLERANCE && partial.magnitude > 1 - TOLERANCE);
    float[3] xAxis = [1, 0, 0];
    assert(v.rejectAlong(xAxis).dot(xAxis) == 0);
}
