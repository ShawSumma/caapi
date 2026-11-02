module unit.plane;

import core.stdc.math : fabsf;
import common.worldgen.plane : Plane;
import geometry.honeycomb : FACE_DISTANCE, Face, opposite;
import geometry.lorentz : Motion, Point, Vec4;

enum float TOLERANCE = 1e-3f;
enum uint STEPS = 8;

Face alternatingFace(uint step) {
    if (step % 2 == 0) {
        return Face.f0;
    } else {
        return Face.f0.opposite;
    }
}

unittest {
    Plane ground = Plane.ofFace(Face.f0);
    assert(fabsf(ground.distanceTo(Point!float.origin()) + FACE_DISTANCE) < TOLERANCE);
    Plane across = ground.reflectAcross(Face.f0);
    assert(fabsf(across.distanceTo(Point!float.origin()) - FACE_DISTANCE) < TOLERANCE);
    Point!float point = Motion!float.shift([0.3f, -0.2f, 0.4f]) * Point!float.origin();
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
    Plane nudged = Plane([ground.up[0] + 1e-3f, ground.up[1], ground.up[2]], ground.height + 1e-3f);
    Plane snapped = nudged.snappedToFaces();
    assert(snapped.height == ground.height && snapped.up[0] == ground.up[0] && snapped.up[1] == ground.up[1] && snapped.up[2] == ground.up[2]);
    assert((-nudged).snappedToFaces().height == -ground.height);
    Plane fromItsNormal = Plane.fromNormal(Vec4!float([ground.up[0] * 1.2f, ground.up[1] * 1.2f, ground.up[2] * 1.2f, 0.0f]).toNormal().v);
    assert(fabsf(fromItsNormal.height) < TOLERANCE);
}
