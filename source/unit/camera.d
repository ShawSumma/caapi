module unit.camera;

import core.math : cos, sqrt;
import core.stdc.math : fabsf;
import base.numbers : PI;
import base.units : Angle, Length;
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
    camera.follow(camera.position, Motion!float.identity(), [0.6f, 0.8f, 0]);
    float[3] up = camera.heading.rotate([0, 1, 0]);
    assert(fabsf(up[0] - 0.6f) + fabsf(up[1] - 0.8f) + fabsf(up[2]) < ANGLE_TOLERANCE.value);
    assert(fabsf(camera.elevation().value - 0.3f) < ANGLE_TOLERANCE.value);
}

unittest {
    Camera camera = Camera.make(Length(0));
    camera.turn(Angle(0), -PITCH_LIMIT);
    float[3] before = camera.heading.rotate(CAMERA_FORWARD);
    foreach (step; 0 .. 100) {
        float wobble = 1e-3f;
        if (step % 2 != 0) {
            wobble = -wobble;
        }
        float[3] up = [wobble, 1, wobble * 0.5f];
        float length = sqrt(up[0] * up[0] + up[1] * up[1] + up[2] * up[2]);
        camera.follow(camera.position, Motion!float.identity(), [up[0] / length, up[1] / length, up[2] / length]);
    }
    float[3] after = camera.heading.rotate(CAMERA_FORWARD);
    assert(before[0] * after[0] + before[1] * after[1] + before[2] * after[2] > cos(ANGLE_TOLERANCE.value * 10));
}
