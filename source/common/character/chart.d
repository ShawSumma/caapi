module common.character.chart;

import base.vector3 : Vec3;
import common.node : ChunkLayout;
import geometry.honeycomb : Corner, cubeToNode;
import geometry.lorentz : Motion, Point, Vec4;

enum float GRID_SLOPE_STEP = 1e-4f;

struct Matrix3 {
    Vec3!float x;
    Vec3!float y;
    Vec3!float z;

    ref inout(Vec3!float) opIndex(size_t row) inout return {
        if (row == 0) {
            return x;
        } else if (row == 1) {
            return y;
        } else {
            assert(row == 2);
            return z;
        }
    }
}

Matrix3 gridJacobian(ref const ChunkLayout layout, Motion!float toCorner) {
    Vec4!float point = (toCorner * Point!float.origin()).v;
    Vec3!float klein = Vec3!float(point.c[0] / point.c[3], point.c[1] / point.c[3], point.c[2] / point.c[3]);
    Matrix3 jacobian;
    foreach (bodyAxis; 0 .. 3) {
        float[4] basis = [0, 0, 0, 0];
        basis[bodyAxis] = 1;
        Vec4!float direction = toCorner * Vec4!float(basis);
        foreach (gridAxis; 0 .. 3) {
            float kleinRate = (direction.c[gridAxis] - klein[gridAxis] * direction.c[3]) / point.c[3];
            jacobian[gridAxis][bodyAxis] = gridSlope(layout, klein[gridAxis]) * kleinRate;
        }
    }
    return jacobian;
}

float gridSlope(ref const ChunkLayout layout, float klein) {
    return (layout.kleinToGrid(klein + GRID_SLOPE_STEP) - layout.kleinToGrid(klein - GRID_SLOPE_STEP)) / (2 * GRID_SLOPE_STEP);
}

Point!float chunkPointInNode(Corner corner, Vec3!float chunk) {
    return (corner.cubeToNode * Vec4!float([chunk.x, chunk.y, chunk.z, 1.0f])).toPoint();
}

Matrix3 inverted(Matrix3 m) {
    Matrix3 cofactor = Matrix3(
        Vec3!float(m.y.y * m.z.z - m.y.z * m.z.y, m.x.z * m.z.y - m.x.y * m.z.z, m.x.y * m.y.z - m.x.z * m.y.y),
        Vec3!float(m.y.z * m.z.x - m.y.x * m.z.z, m.x.x * m.z.z - m.x.z * m.z.x, m.x.z * m.y.x - m.x.x * m.y.z),
        Vec3!float(m.y.x * m.z.y - m.y.y * m.z.x, m.x.y * m.z.x - m.x.x * m.z.y, m.x.x * m.y.y - m.x.y * m.y.x),
    );
    float determinant = m.x.x * cofactor.x.x + m.x.y * cofactor.y.x + m.x.z * cofactor.z.x;
    Matrix3 result;
    foreach (row; 0 .. 3) {
        foreach (column; 0 .. 3) {
            result[row][column] = cofactor[row][column] / determinant;
        }
    }
    return result;
}

Vec3!float applied(Matrix3 matrix, Vec3!float v) {
    return Vec3!float(
        matrix.x.x * v.x + matrix.x.y * v.y + matrix.x.z * v.z,
        matrix.y.x * v.x + matrix.y.y * v.y + matrix.y.z * v.z,
        matrix.z.x * v.x + matrix.z.y * v.y + matrix.z.z * v.z,
    );
}
