module common.worldgen.plane;

import core.stdc.math : asinh, exp, fabs, fabsf, log, log1p, sqrt, sqrtf, tanh;
import base.vector3 : Vec3;
import common.character.chart : applied, gridJacobian;
import common.node : ChunkLayout;
import geometry.honeycomb : Corner, FACE_COUNT, FACE_DISTANCE, Face, cubeToNode, direction, mirror, nodeToCorner;
import geometry.lorentz : Mat4, Motion, Point, Vec4;

enum double LARGEST_DIRECT_SCALE = 600;
enum float SNAP_TOLERANCE = 0.05f;
enum float SNAP_ALIGNMENT = 0.99f;

struct Plane {
    Vec3!float up;
    float height;

    static Plane ofFace(Face face) {
        return Plane(face.direction, -FACE_DISTANCE);
    }

    static Plane fromNormal(Vec4!float normal) {
        return Plane(unit(normal.spatial().as!double()), cast(float) asinh(-normal.c[3]));
    }

    Plane opUnary(string op)() const if (op == "-") {
        return Plane(Vec3!float(-up.x, -up.y, -up.z), -height);
    }

    Plane reflectAcross(Face face) const {
        return transformBy(face.mirror);
    }

    Plane snappedToFaces() const {
        Plane snapped = this;
        if (fabsf(fabsf(height) - FACE_DISTANCE) < SNAP_TOLERANCE) {
            foreach (index; 0 .. FACE_COUNT) {
                Face face = cast(Face) index;
                Vec3!float outward = face.direction;
                float along = up.x * outward.x + up.y * outward.y + up.z * outward.z;
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
        return Vec4!double([up.x, up.y, up.z, -tanh(height)]);
    }

    PlaneMeasure measure() const {
        double logScale = logCosh(height);
        return PlaneMeasure(scaledNormal(), logScale, exp(logScale));
    }

    float distanceTo(Point!float point) const {
        return measure().distanceTo(point);
    }

    float distanceToChunk(Corner chunk, Vec3!float coord) const {
        return distanceTo(chunkPoint(chunk, coord));
    }

    Vec3!float upAt(Motion!float local) const {
        Vec4!double away = local.inverse().as!double() * scaledNormal();
        return unit(away.spatial());
    }

    Vec3!float gridUpAt(Corner chunk, ref const ChunkLayout layout, Vec3!float grid) const {
        Point!float point = (chunk.cubeToNode * Vec4!float([layout.gridToCube(grid.x), layout.gridToCube(grid.y), layout.gridToCube(grid.z), 1.0f])).toPoint();
        Motion!float local = Motion!float.shiftTo(point);
        Vec3!float up = applied(gridJacobian(layout, chunk.nodeToCorner * local), upAt(local));
        float length = sqrtf(up.x * up.x + up.y * up.y + up.z * up.z);
        return Vec3!float(up.x / length, up.y / length, up.z / length);
    }

    int risingNeighbor(Corner chunk, ref const ChunkLayout layout, Vec3!int cell) const {
        Vec3!float up = gridUpAt(chunk, layout, Vec3!float(cell.x + 0.5f, cell.y + 0.5f, cell.z + 0.5f));
        int rising = 0;
        float steepest = 0;
        foreach (axis; 0 .. 3) {
            if (axis == 0 || fabsf(up[axis]) > steepest) {
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

    double sinhDistanceTo(Point!float point) const {
        return normal.minkowski(point.v.as!double()) * scale;
    }

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

Point!float chunkPoint(Corner chunk, Vec3!float coord) {
    return cubePoint(chunk.cubeToNode, coord);
}

Point!float cubePoint(Mat4!float cubeToNode, Vec3!float coord) {
    return (cubeToNode * Vec4!float([coord.x, coord.y, coord.z, 1.0f])).toPoint();
}

double logCosh(double x) {
    double size = fabs(x);
    return size + log1p(exp(-2 * size)) - log(2.0);
}

Vec3!float unit(Vec3!double v) {
    double length = sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    return Vec3!float(cast(float)(v.x / length), cast(float)(v.y / length), cast(float)(v.z / length));
}
