module common.worldgen.plane;

import core.stdc.math : asinh, exp, fabs, fabsf, log, log1p, sqrt, sqrtf, tanh;
import common.character.chart : applied, gridJacobian;
import common.node : ChunkLayout;
import geometry.honeycomb : Corner, FACE_COUNT, FACE_DISTANCE, Face, cubeToNode, direction, mirror, nodeToCorner, opposite;
import geometry.lorentz : Mat4, Motion, Point, Vec4;

enum double LARGEST_DIRECT_SCALE = 600;
enum float SNAP_TOLERANCE = 0.05f;
enum float SNAP_ALIGNMENT = 0.99f;
enum float TEST_TOLERANCE = 1e-3f;
enum uint TEST_STEPS = 8;

struct Plane {
    float[3] up;
    float height;

    static Plane ofFace(Face face) {
        return Plane(face.direction, -FACE_DISTANCE);
    }

    static Plane fromNormal(Vec4!float normal) {
        double[3] spatial = [normal.c[0], normal.c[1], normal.c[2]];
        return Plane(unit(spatial), cast(float) asinh(-normal.c[3]));
    }

    Plane opUnary(string op)() const if (op == "-") {
        return Plane([-up[0], -up[1], -up[2]], -height);
    }

    Plane reflectAcross(Face face) const {
        return transformBy(face.mirror);
    }

    Plane snappedToFaces() const {
        Plane snapped = this;
        if (fabsf(fabsf(height) - FACE_DISTANCE) < SNAP_TOLERANCE) {
            foreach (index; 0 .. FACE_COUNT) {
                Face face = cast(Face) index;
                float[3] outward = face.direction;
                float along = up[0] * outward[0] + up[1] * outward[1] + up[2] * outward[2];
                if (height < 0 && along > SNAP_ALIGNMENT) {
                    snapped = Plane.ofFace(face);
                } else if (height > 0 && along < -SNAP_ALIGNMENT) {
                    snapped = -Plane.ofFace(face);
                }
            }
        }
        return snapped;
    }

    Plane carriedAlong(const(Face)[] path) const {
        Plane carried = this;
        foreach_reverse (side; path) {
            carried = carried.reflectAcross(side).snappedToFaces();
        }
        return carried;
    }

    Plane transformBy(Motion!float motion) const {
        PlaneMeasure measured = measure();
        Vec4!double moved = motion.as!double() * measured.normal;
        return Plane(unit(moved.spatial()), measured.distanceTo(motion.inverse() * Point!float.origin()));
    }

    Vec4!double scaledNormal() const {
        return Vec4!double([up[0], up[1], up[2], -tanh(height)]);
    }

    PlaneMeasure measure() const {
        double logScale = logCosh(height);
        return PlaneMeasure(scaledNormal(), logScale, exp(logScale));
    }

    float distanceTo(Point!float point) const {
        return measure().distanceTo(point);
    }

    float distanceToChunk(Corner chunk, float[3] coord) const {
        return distanceTo(chunkPoint(chunk, coord));
    }

    float[3] upAt(Motion!float local) const {
        Vec4!double away = local.inverse().as!double() * scaledNormal();
        double[3] spatial = away.spatial();
        return unit(spatial);
    }

    float[3] gridUpAt(Corner chunk, ref const ChunkLayout layout, float[3] grid) const {
        Point!float point = (chunk.cubeToNode * Vec4!float([layout.gridToCube(grid[0]), layout.gridToCube(grid[1]), layout.gridToCube(grid[2]), 1.0f])).toPoint();
        Motion!float local = Motion!float.shiftTo(point);
        float[3] up = applied(gridJacobian(layout, chunk.nodeToCorner * local), upAt(local));
        float length = sqrtf(up[0] * up[0] + up[1] * up[1] + up[2] * up[2]);
        return [up[0] / length, up[1] / length, up[2] / length];
    }

    int risingNeighbor(Corner chunk, ref const ChunkLayout layout, int[3] cell) const {
        float[3] up = gridUpAt(chunk, layout, [cell[0] + 0.5f, cell[1] + 0.5f, cell[2] + 0.5f]);
        int rising = 0;
        float steepest = -float.infinity;
        foreach (axis; 0 .. 3) {
            if (fabsf(up[axis]) > steepest) {
                steepest = fabsf(up[axis]);
                rising = cast(int)(2 * axis);
                if (up[axis] > 0) {
                    rising += 1;
                }
            }
        }
        return rising;
    }
}

struct PlaneMeasure {
    Vec4!double normal;
    double logScale;
    double scale;

    float distanceTo(Point!float point) const {
        double value = normal.minkowski(point.v.as!double());
        if (logScale < LARGEST_DIRECT_SCALE) {
            return cast(float) asinh(value * scale);
        } else {
            double magnitude = logScale + log(2 * fabs(value));
            if (value < 0) {
                return cast(float) -magnitude;
            } else {
                return cast(float) magnitude;
            }
        }
    }
}

Point!float chunkPoint(Corner chunk, float[3] coord) {
    return cubePoint(chunk.cubeToNode, coord);
}

Point!float cubePoint(Mat4!float cubeToNode, float[3] coord) {
    return (cubeToNode * Vec4!float([coord[0], coord[1], coord[2], 1.0f])).toPoint();
}

double logCosh(double x) {
    double size = fabs(x);
    return size + log1p(exp(-2 * size)) - log(2.0);
}

float[3] unit(double[3] v) {
    double length = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    return [cast(float)(v[0] / length), cast(float)(v[1] / length), cast(float)(v[2] / length)];
}

Face alternatingFace(uint step) {
    if (step % 2 == 0) {
        return Face.f0;
    } else {
        return Face.f0.opposite;
    }
}

unittest {
    Plane ground = Plane.ofFace(Face.f0);
    assert(fabsf(ground.distanceTo(Point!float.origin()) + FACE_DISTANCE) < TEST_TOLERANCE);
    Plane across = ground.reflectAcross(Face.f0);
    assert(fabsf(across.distanceTo(Point!float.origin()) - FACE_DISTANCE) < TEST_TOLERANCE);
    Point!float point = Motion!float.shift([0.3f, -0.2f, 0.4f]) * Point!float.origin();
    Plane far = ground;
    foreach (step; 0 .. TEST_STEPS) {
        far = far.reflectAcross(alternatingFace(step));
    }
    assert(far.height > TEST_STEPS / 2);
    Plane back = far;
    foreach_reverse (step; 0 .. TEST_STEPS) {
        back = back.reflectAcross(alternatingFace(step));
    }
    assert(fabsf(back.distanceTo(point) - ground.distanceTo(point)) < TEST_TOLERANCE);
    Plane nudged = Plane([ground.up[0] + 1e-3f, ground.up[1], ground.up[2]], ground.height + 1e-3f);
    Plane snapped = nudged.snappedToFaces();
    assert(snapped.height == ground.height && snapped.up[0] == ground.up[0] && snapped.up[1] == ground.up[1] && snapped.up[2] == ground.up[2]);
    assert((-nudged).snappedToFaces().height == -ground.height);
    Plane fromItsNormal = Plane.fromNormal(Vec4!float([ground.up[0] * 1.2f, ground.up[1] * 1.2f, ground.up[2] * 1.2f, 0.0f]).toNormal().v);
    assert(fabsf(fromItsNormal.height) < TEST_TOLERANCE);
}
