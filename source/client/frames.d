module client.frames;

import core.math : cos, sin, sqrt;
import core.stdc.math : atan2, fabs, round;
import core.stdc.stdio : FILE, fprintf;
import base.clock : MILLISECONDS_PER_SECOND, PhaseTimes;
import base.numbers : higherOf, lowerOf;
import client.images : ImageDifference;
import common.graph : Graph, NO_SLOT;
import common.position : Position;
import geometry.honeycomb : FACE_COUNT, Face, mirror;
import geometry.lorentz : Motion, Point;

immutable double[2] LATE_INTERVALS_MS = [20, 34];
enum double MOVING_DISTANCE = 1e-6;
enum uint TEST_STEPS = 7;
immutable double[2] TEST_COUNTS = [100, -23];
immutable double[3] TEST_START = [0.3, -0.1, 0.2];
immutable double[3] TEST_SHIFT = [0.004, 0.0, -0.01];
enum double TEST_TURN = 0.3;
enum double TEST_TOLERANCE = 1e-4;

struct CameraStep {
    double turned = 0;
    double moved = 0;
    bool isMeasured;
}

struct RenderTimes {
    double totalMs = 0;
    double fenceMs = 0;
    double updateMs = 0;
    double acquireMs = 0;
    double presentMs = 0;
    double gpuMs = 0;
}

struct FrameRecord {
    uint frame;
    double intervalMs = 0;
    double dtMs = 0;
    double stepMs = 0;
    RenderTimes render;
    double dx = 0;
    double dy = 0;
    CameraStep step;
    ImageDifference image;
    bool hasInterval;
    bool hasImage;

    void print(FILE* report) const {
        fprintf(report, "frame %u: interval %.2fms dt %.2fms step %.2fms render %.2fms (fence %.2f update %.2f present %.2f, gpu %.2f) input %+.0f %+.0f", frame, intervalMs, dtMs, stepMs, render.totalMs, render.fenceMs, render.updateMs, render.presentMs, render.gpuMs, dx, dy);
        if (step.isMeasured) {
            fprintf(report, " turned %.5f moved %.5f", step.turned, step.moved);
        } else {
            fprintf(report, " camera step unknown");
        }
        if (hasImage) {
            fprintf(report, " image changed %.4f mean %.2f largest %d", image.changed, image.meanDelta, image.largestDelta);
        }
        fprintf(report, "\n");
    }
}

struct MouseMotion {
    double[2] total = 0;
    double[2] sent = 0;
    uint steps;
    uint done;

    bool isActive() const {
        return done < steps;
    }

    // Whole counts, as a mouse reports them, spread so that the running sum stays on the straight line.
    double[2] next() {
        done += 1;
        double[2] share;
        foreach (axis; 0 .. 2) {
            double target = round(total[axis] * done / steps);
            share[axis] = target - sent[axis];
            sent[axis] = target;
        }
        return share;
    }
}

struct FrameSummary {
    PhaseTimes step;
    PhaseTimes render;
    PhaseTimes fence;
    PhaseTimes update;
    PhaseTimes acquire;
    PhaseTimes present;
    PhaseTimes gpu;
    double turnedTotal = 0;
    double countsTotal = 0;
    uint frames;
    uint[LATE_INTERVALS_MS.length] late;
    uint moving;
    uint imaged;
    uint stillImages;
    double intervalTotalMs = 0;
    double worstIntervalMs = 0;
    double stepErrorTotalMs = 0;
    double worstStepErrorMs = 0;
    double slowestSpeed = double.infinity;
    double fastestSpeed = 0;
    double speedTotal = 0;

    void add(ref const FrameRecord record) {
        step.add(record.stepMs);
        render.add(record.render.totalMs);
        fence.add(record.render.fenceMs);
        update.add(record.render.updateMs);
        acquire.add(record.render.acquireMs);
        present.add(record.render.presentMs);
        gpu.add(record.render.gpuMs);
        if (record.step.isMeasured) {
            turnedTotal += record.step.turned;
        }
        countsTotal += sqrt(record.dx * record.dx + record.dy * record.dy);
        if (record.hasInterval) {
            frames += 1;
            intervalTotalMs += record.intervalMs;
            worstIntervalMs = higherOf(record.intervalMs, worstIntervalMs);
            foreach (index, limit; LATE_INTERVALS_MS) {
                if (record.intervalMs > limit) {
                    late[index] += 1;
                }
            }
            double error = fabs(record.dtMs - record.intervalMs);
            stepErrorTotalMs += error;
            worstStepErrorMs = higherOf(error, worstStepErrorMs);
            if (record.step.isMeasured && record.step.moved > MOVING_DISTANCE && record.intervalMs > 0) {
                double speed = record.step.moved / (record.intervalMs / MILLISECONDS_PER_SECOND);
                moving += 1;
                speedTotal += speed;
                slowestSpeed = lowerOf(speed, slowestSpeed);
                fastestSpeed = higherOf(speed, fastestSpeed);
            }
        }
        if (record.hasImage) {
            imaged += 1;
            if (record.image.changed == 0) {
                stillImages += 1;
            }
        }
    }

    void print(FILE* report) const {
        if (frames == 0) {
            fprintf(report, "frames: none timed\n");
        } else {
            fprintf(report, "frames: %u, interval avg %.2fms worst %.2fms, %u over %.0fms, %u over %.0fms\n", frames, intervalTotalMs / frames, worstIntervalMs, late[0], LATE_INTERVALS_MS[0], late[1], LATE_INTERVALS_MS[1]);
            fprintf(report, "frames: stepped dt against the wall interval, avg off %.2fms, worst off %.2fms\n", stepErrorTotalMs / frames, worstStepErrorMs);
        }
        fprintf(report, "frames: avg/worst ms step %.2f/%.2f render %.2f/%.2f (fence %.2f/%.2f update %.2f/%.2f present %.2f/%.2f of which acquire %.2f/%.2f, gpu %.2f/%.2f)\n", step.averageMs(), step.worstMs, render.averageMs(), render.worstMs, fence.averageMs(), fence.worstMs, update.averageMs(), update.worstMs, present.averageMs(), present.worstMs, acquire.averageMs(), acquire.worstMs, gpu.averageMs(), gpu.worstMs);
        fprintf(report, "frames: turned %.5f radians in all for %.0f mouse counts\n", turnedTotal, countsTotal);
        if (moving > 0) {
            fprintf(report, "frames: camera speed over wall time in %u moving frames, avg %.4f slowest %.4f fastest %.4f units/s\n", moving, speedTotal / moving, slowestSpeed, fastestSpeed);
        }
        if (imaged > 0) {
            fprintf(report, "frames: %u compared with the frame before, %u unchanged\n", imaged, stillImages);
        }
    }
}

// How far the camera turned and moved between two frames, measured in the node it is in now.
CameraStep cameraStep(ref const Graph graph, Position before, Position after) {
    uint from = graph.slotOf(before.node);
    uint to = graph.slotOf(after.node);
    Motion!double carried = before.local.as!double();
    bool isNear = from == to && from != NO_SLOT;
    uint face = 0;
    while (!isNear && from != NO_SLOT && to != NO_SLOT && face < FACE_COUNT) {
        if (graph.neighborSlot(to, cast(Face) face) == from) {
            carried = (cast(Face) face).mirror.as!double() * carried;
            isNear = true;
        }
        face += 1;
    }
    if (isNear) {
        return stepBetween(carried, after.local.as!double());
    } else {
        return CameraStep.init;
    }
}

CameraStep stepBetween(Motion!double before, Motion!double after) {
    Motion!double step = before.inverse() * after;
    Point!double reached = step * Point!double.origin();
    Motion!double turn = Motion!double.shiftTo(reached).inverse() * step;
    double cosine = (turn.m.c[0][0] + turn.m.c[1][1] + turn.m.c[2][2] - 1) / 2;
    double[3] axis = [turn.m.c[1][2] - turn.m.c[2][1], turn.m.c[2][0] - turn.m.c[0][2], turn.m.c[0][1] - turn.m.c[1][0]];
    double sine = sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]) / 2;
    return CameraStep(atan2(sine, cosine), reached.distance(Point!double.origin()), true);
}

unittest {
    MouseMotion motion = MouseMotion(TEST_COUNTS, [0, 0], TEST_STEPS, 0);
    double[2] sum = 0;
    while (motion.isActive()) {
        double[2] share = motion.next();
        foreach (axis; 0 .. 2) {
            assert(share[axis] == round(share[axis]));
            sum[axis] += share[axis];
        }
    }
    assert(sum[0] == TEST_COUNTS[0] && sum[1] == TEST_COUNTS[1]);
    Motion!double start = Motion!double.shift(TEST_START);
    Motion!double turn = Motion!double.identity();
    turn.m.c[0][0] = cos(TEST_TURN);
    turn.m.c[0][2] = -sin(TEST_TURN);
    turn.m.c[2][0] = sin(TEST_TURN);
    turn.m.c[2][2] = cos(TEST_TURN);
    CameraStep step = stepBetween(start, start * turn * Motion!double.shift(TEST_SHIFT));
    double length = sqrt(TEST_SHIFT[0] * TEST_SHIFT[0] + TEST_SHIFT[1] * TEST_SHIFT[1] + TEST_SHIFT[2] * TEST_SHIFT[2]);
    assert(step.isMeasured && fabs(step.moved - length) < TEST_TOLERANCE && fabs(step.turned - TEST_TURN) < TEST_TOLERANCE);
}
