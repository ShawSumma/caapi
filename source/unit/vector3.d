module unit.vector3;

import base.vector3 : Vec3, ZERO_VECTOR, cappedTo, cross, dot, magnitude, movedToward, rejectAlong;

enum float TOLERANCE = 1e-4f;

unittest {
    Vec3!float v = Vec3!float(3, 4, 0);
    assert(v.cappedTo(1).magnitude < 1 + TOLERANCE);
    Vec3!float z = Vec3!float(0, 0, 1);
    assert(v.cross(z).dot(v) == 0);
    Vec3!float reached = ZERO_VECTOR.movedToward(v, 10);
    assert(reached.x == 3 && reached.y == 4);
    Vec3!float partial = ZERO_VECTOR.movedToward(v, 1);
    assert(partial.magnitude < 1 + TOLERANCE && partial.magnitude > 1 - TOLERANCE);
    Vec3!float xAxis = Vec3!float(1, 0, 0);
    assert(v.rejectAlong(xAxis).dot(xAxis) == 0);
    assert(v[0] == v.x && v[1] == v.y && v[2] == v.z);
    v[1] = 7;
    assert(v.y == 7);
    assert(v.as!int() == Vec3!int(3, 7, 0));
}
