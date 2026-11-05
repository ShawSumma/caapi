module unit.lorentz;

import core.math : sqrt;
import base.vector3 : Vec3;
import geometry.lorentz : Mat4, Motion, Normal, Point, Vec4;

enum double TOLERANCE = 1e-9;

bool isNear(double a, double b) {
    double difference = a - b;
    return difference < TOLERANCE && difference > -TOLERANCE;
}

unittest {
    Motion!double moved = Motion!double.shift(Vec3!double(0.3, -1.2, 0.7));
    Point!double there = moved * Point!double.origin();
    assert(isNear(there.distance(Point!double.origin()), sqrt(0.09 + 1.44 + 0.49)));
    Motion!double back = moved.inverse() * moved;
    foreach (col; 0 .. 4) {
        foreach (row; 0 .. 4) {
            assert(isNear(back.m.c[col][row], Mat4!double.identity().c[col][row]));
        }
    }
    Point!double start = Motion!double.shift(Vec3!double(1, 0, 0.5)) * Point!double.origin();
    Point!double end = Motion!double.shift(Vec3!double(-0.4, 2, 0)) * Point!double.origin();
    assert(isNear((Motion!double.carrying(start, end) * start).coshDistance(end), 1));
    Normal!double plane = Vec4!double([1, 0.5, 0, 0.25]).toNormal();
    Motion!double mirror = Motion!double.reflection(plane);
    Point!double mirrored = mirror * start;
    assert(isNear(start.coshDistance(mirror * mirrored), 1));
    assert(isNear(plane.minkowski(start.v), -plane.minkowski(mirrored.v)));
    assert(mirror.isMirroring() && !moved.isMirroring());
    Motion!double drifted = moved;
    drifted.m.c[0][1] += 1e-4;
    drifted.m.c[3][2] -= 1e-4;
    Motion!double repaired = drifted.orthonormalized();
    foreach (col; 0 .. 4) {
        foreach (other; 0 .. 4) {
            double expected = 0;
            if (col == other && col == 3) {
                expected = -1;
            } else if (col == other) {
                expected = 1;
            }
            assert(isNear(repaired.m.column(col).minkowski(repaired.m.column(other)), expected));
        }
    }
}
