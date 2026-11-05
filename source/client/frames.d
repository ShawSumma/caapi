module client.frames;

import core.math : sqrt;
import core.stdc.math : atan2, fabs, round;
import core.stdc.stdio : FILE, fprintf;
import base.clock : MILLISECONDS_PER_SECOND, PhaseTimes;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : higherOf, lowerOf;
import base.vector3 : Vec3;
import client.images : ImageDifference;
import common.graph : Graph;
import common.position : Position;
import geometry.honeycomb : FACE_COUNT, Face, mirror;
import geometry.lorentz : Motion, Point;

immutable double[2] LATE_INTERVALS_MS = [20, 34];
enum double MOVING_DISTANCE = 1e-6;

struct CameraStep {
    double turned = 0;
    double moved = 0;
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
    Maybe!double intervalMs;
    double dtMs = 0;
    double stepMs = 0;
    RenderTimes render;
    double dx = 0;
    double dy = 0;
    Maybe!CameraStep step;
    Maybe!ImageDifference image;

    void print(FILE* report) const {
        fprintf(report, "frame %u:", frame);
        if (intervalMs.exists) {
            fprintf(report, " interval %.2fms", intervalMs.value);
        } else {
            fprintf(report, " first frame");
        }
        fprintf(report, " dt %.2fms step %.2fms render %.2fms (fence %.2f update %.2f present %.2f, gpu %.2f) input %+.0f %+.0f", dtMs, stepMs, render.totalMs, render.fenceMs, render.updateMs, render.presentMs, render.gpuMs, dx, dy);
        if (step.exists) {
            fprintf(report, " turned %.5f moved %.5f", step.value.turned, step.value.moved);
        } else {
            fprintf(report, " camera step unknown");
        }
        if (image.exists) {
            fprintf(report, " image changed %.4f mean %.2f largest %d", image.value.changed, image.value.meanDelta, image.value.largestDelta);
        }
        fprintf(report, "\n");
    }
}

struct MouseCounts {
    double dx = 0;
    double dy = 0;
}

struct MouseMotion {
    MouseCounts total;
    MouseCounts sent;
    uint steps;
    uint done;

    bool isActive() const {
        return done < steps;
    }

    MouseCounts next() {
        done += 1;
        MouseCounts target = MouseCounts(round(total.dx * done / steps), round(total.dy * done / steps));
        MouseCounts share = MouseCounts(target.dx - sent.dx, target.dy - sent.dy);
        sent = target;
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
    double slowestSpeed = 0;
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
        if (record.step.exists) {
            turnedTotal += record.step.value.turned;
        }
        countsTotal += sqrt(record.dx * record.dx + record.dy * record.dy);
        if (record.intervalMs.exists) {
            double interval = record.intervalMs.value;
            frames += 1;
            intervalTotalMs += interval;
            worstIntervalMs = higherOf(interval, worstIntervalMs);
            foreach (index, limit; LATE_INTERVALS_MS) {
                if (interval > limit) {
                    late[index] += 1;
                }
            }
            double error = fabs(record.dtMs - interval);
            stepErrorTotalMs += error;
            worstStepErrorMs = higherOf(error, worstStepErrorMs);
            if (record.step.exists && record.step.value.moved > MOVING_DISTANCE && interval > 0) {
                double speed = record.step.value.moved / (interval / MILLISECONDS_PER_SECOND);
                if (moving == 0) {
                    slowestSpeed = speed;
                }
                moving += 1;
                speedTotal += speed;
                slowestSpeed = lowerOf(speed, slowestSpeed);
                fastestSpeed = higherOf(speed, fastestSpeed);
            }
        }
        if (record.image.exists) {
            imaged += 1;
            if (record.image.value.changed == 0) {
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

Maybe!CameraStep cameraStep(ref const Graph graph, Position before, Position after) {
    MaybeIndex!uint from = graph.slotOf(before.node);
    MaybeIndex!uint to = graph.slotOf(after.node);
    if (!from.exists || !to.exists) {
        return Maybe!CameraStep.init;
    } else if (from == to) {
        return Maybe!CameraStep.of(stepBetween(before.local.as!double(), after.local.as!double()));
    } else {
        foreach (face; 0 .. FACE_COUNT) {
            if (graph.neighborSlot(to.value, cast(Face) face) == from) {
                return Maybe!CameraStep.of(stepBetween((cast(Face) face).mirror.as!double() * before.local.as!double(), after.local.as!double()));
            }
        }
        return Maybe!CameraStep.init;
    }
}

CameraStep stepBetween(Motion!double before, Motion!double after) {
    Motion!double step = before.inverse() * after;
    Point!double reached = step * Point!double.origin();
    Motion!double turn = Motion!double.shiftTo(reached).inverse() * step;
    double cosine = (turn.m.c[0][0] + turn.m.c[1][1] + turn.m.c[2][2] - 1) / 2;
    Vec3!double axis = Vec3!double(turn.m.c[1][2] - turn.m.c[2][1], turn.m.c[2][0] - turn.m.c[0][2], turn.m.c[0][1] - turn.m.c[1][0]);
    double sine = sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z) / 2;
    return CameraStep(atan2(sine, cosine), reached.distance(Point!double.origin()));
}
