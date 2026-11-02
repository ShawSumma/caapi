module unit.frames;

import core.math : cos, sin, sqrt;
import core.stdc.math : fabs, round;
import client.frames : CameraStep, MouseMotion, stepBetween;
import geometry.lorentz : Motion;

enum uint STEPS = 7;
immutable double[2] COUNTS = [100, -23];
immutable double[3] START = [0.3, -0.1, 0.2];
immutable double[3] SHIFT = [0.004, 0.0, -0.01];
enum double TURN = 0.3;
enum double TOLERANCE = 1e-4;

unittest {
    MouseMotion motion = MouseMotion(COUNTS, [0, 0], STEPS, 0);
    double[2] sum = 0;
    while (motion.isActive()) {
        double[2] share = motion.next();
        foreach (axis; 0 .. 2) {
            assert(share[axis] == round(share[axis]));
            sum[axis] += share[axis];
        }
    }
    assert(sum[0] == COUNTS[0] && sum[1] == COUNTS[1]);
    Motion!double start = Motion!double.shift(START);
    Motion!double turn = Motion!double.identity();
    turn.m.c[0][0] = cos(TURN);
    turn.m.c[0][2] = -sin(TURN);
    turn.m.c[2][0] = sin(TURN);
    turn.m.c[2][2] = cos(TURN);
    CameraStep step = stepBetween(start, start * turn * Motion!double.shift(SHIFT));
    double length = sqrt(SHIFT[0] * SHIFT[0] + SHIFT[1] * SHIFT[1] + SHIFT[2] * SHIFT[2]);
    assert(fabs(step.moved - length) < TOLERANCE && fabs(step.turned - TURN) < TOLERANCE);
}
