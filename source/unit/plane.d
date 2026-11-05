module unit.plane;

import core.stdc.math : fabsf;
import base.vector3 : Vec3;
import common.worldgen.plane : Plane;
import geometry.honeycomb : FACE_DISTANCE, Face, opposite;
import geometry.lorentz : Motion, Point, Vec4;

enum float TOLERANCE = 1e-3f;
enum uint STEPS = 8;

Face alternatingFace(uint step) {
    if (step % 2 == 0) {
        return Face.first;
    } else {
        return Face.first.opposite;
    }
}

unittest {
    Plane ground = Plane.ofFace(Face.first);
    assert(fabsf(ground.distanceTo(Point!float.origin()) + FACE_DISTANCE) < TOLERANCE);
    Plane across = ground.reflectAcross(Face.first);
    assert(fabsf(across.distanceTo(Point!float.origin()) - FACE_DISTANCE) < TOLERANCE);
    Point!float point = Motion!float.shift(Vec3!float(0.3f, -0.2f, 0.4f)) * Point!float.origin();
    Plane far = ground;
    foreach (step; 0 .. STEPS) {
        far = far.reflectAcross(alternatingFace(step));
    }
    assert(far.height > STEPS / 2);
    Plane back = far;
    foreach_reverse (step; 0 .. STEPS) {
        back = back.reflectAcross(alternatingFace(step));
    }
    assert(fabsf(back.distanceTo(point) - ground.distanceTo(point)) < TOLERANCE);
    Plane nudged = Plane(Vec3!float(ground.up.x + 1e-3f, ground.up.y, ground.up.z), ground.height + 1e-3f);
    Plane snapped = nudged.snappedToFaces();
    assert(snapped.height == ground.height && snapped.up == ground.up);
    assert((-nudged).snappedToFaces().height == -ground.height);
    Plane fromItsNormal = Plane.fromNormal(Vec4!float([ground.up.x * 1.2f, ground.up.y * 1.2f, ground.up.z * 1.2f, 0.0f]).toNormal().v);
    assert(fabsf(fromItsNormal.height) < TOLERANCE);
}
