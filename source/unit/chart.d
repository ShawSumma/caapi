module unit.chart;

import base.vector3 : Vec3;
import common.character.chart : Matrix3, applied, inverted;

enum float TOLERANCE = 1e-3f;

unittest {
    Matrix3 m = Matrix3(
        Vec3!float(2, 1, 0),
        Vec3!float(0, 1, 0),
        Vec3!float(0, 0, 3),
    );
    Vec3!float v = Vec3!float(1, 2, 3);
    Vec3!float back = applied(inverted(m), applied(m, v));
    foreach (axis; 0 .. 3) {
        assert(back[axis] - v[axis] < TOLERANCE && v[axis] - back[axis] < TOLERANCE);
    }
}
