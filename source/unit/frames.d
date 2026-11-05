module unit.frames;

import core.math : cos, sin, sqrt;
import core.stdc.math : fabs, round;
import base.vector3 : Vec3;
import client.frames : CameraStep, MouseCounts, MouseMotion, stepBetween;
import geometry.lorentz : Motion;

enum uint STEPS = 7;
enum MouseCounts COUNTS = MouseCounts(100, -23);
immutable Vec3!double START = Vec3!double(0.3, -0.1, 0.2);
immutable Vec3!double SHIFT = Vec3!double(0.004, 0.0, -0.01);
enum double TURN = 0.3;
enum double TOLERANCE = 1e-4;

unittest {
    MouseMotion motion = MouseMotion(COUNTS, MouseCounts.init, STEPS, 0);
    MouseCounts sum;
    while (motion.isActive()) {
        MouseCounts share = motion.next();
        assert(share.dx == round(share.dx) && share.dy == round(share.dy));
        sum.dx += share.dx;
        sum.dy += share.dy;
    }
    assert(sum == COUNTS);
    Motion!double start = Motion!double.shift(START);
    Motion!double turn = Motion!double.identity();
    turn.m.c[0][0] = cos(TURN);
    turn.m.c[0][2] = -sin(TURN);
    turn.m.c[2][0] = sin(TURN);
    turn.m.c[2][2] = cos(TURN);
    CameraStep step = stepBetween(start, start * turn * Motion!double.shift(SHIFT));
    double length = sqrt(SHIFT.x * SHIFT.x + SHIFT.y * SHIFT.y + SHIFT.z * SHIFT.z);
    assert(fabs(step.moved - length) < TOLERANCE && fabs(step.turned - TURN) < TOLERANCE);
}
