module unit.camera;

import core.math : cos;
import core.stdc.math : fabsf;
import base.numbers : PI;
import base.units : Angle, Length;
import base.vector3 : Vec3, dot, magnitude, scaled;
import client.camera : CAMERA_FORWARD, Camera, PITCH_LIMIT;
import geometry.lorentz : Motion;

enum Angle ANGLE_TOLERANCE = Angle(1e-3f);

unittest {
    Camera camera = Camera.make(Length(0));
    camera.turn(Angle(0), Angle(PI));
    assert(camera.elevation() <= PITCH_LIMIT + ANGLE_TOLERANCE);
    camera.turn(Angle(0), Angle(-2 * PI));
    assert(camera.elevation() >= -PITCH_LIMIT - ANGLE_TOLERANCE);
    Angle before = camera.elevation();
    camera.turn(Angle(PI / 2), Angle(0));
    assert(fabsf((camera.elevation() - before).value) < ANGLE_TOLERANCE.value);
}

unittest {
    Camera camera = Camera.make(Length(0));
    camera.turn(Angle(0), Angle(0.3f));
    camera.follow(camera.position, Motion!float.identity(), Vec3!float(0.6f, 0.8f, 0));
    Vec3!float up = camera.heading.rotate(Vec3!float(0, 1, 0));
    assert(fabsf(up.x - 0.6f) + fabsf(up.y - 0.8f) + fabsf(up.z) < ANGLE_TOLERANCE.value);
    assert(fabsf(camera.elevation().value - 0.3f) < ANGLE_TOLERANCE.value);
}

unittest {
    Camera camera = Camera.make(Length(0));
    camera.turn(Angle(0), -PITCH_LIMIT);
    Vec3!float before = camera.heading.rotate(CAMERA_FORWARD);
    foreach (step; 0 .. 100) {
        float wobble = 1e-3f;
        if (step % 2 != 0) {
            wobble = -wobble;
        }
        Vec3!float up = Vec3!float(wobble, 1, wobble * 0.5f);
        camera.follow(camera.position, Motion!float.identity(), up.scaled(1 / up.magnitude));
    }
    Vec3!float after = camera.heading.rotate(CAMERA_FORWARD);
    assert(before.dot(after) > cos(ANGLE_TOLERANCE.value * 10));
}
