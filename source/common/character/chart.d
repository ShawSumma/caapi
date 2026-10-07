module common.character.chart;

import common.dodeca : Vertex, chunkToNode;
import common.math : MIsometry, MPoint, MVector;
import common.node : ChunkLayout;

enum float GRID_SLOPE_STEP = 1e-4f;
enum float TEST_TOLERANCE = 1e-3f;

float[3][3] gridJacobian(ref const ChunkLayout layout, MIsometry!float toDual) {
    MVector!float point = (toDual * MPoint!float.origin()).vec;
    float[3] klein = [point.data[0] / point.data[3], point.data[1] / point.data[3], point.data[2] / point.data[3]];
    float[3][3] jacobian;
    foreach (bodyAxis; 0 .. 3) {
        float[4] basis = [0, 0, 0, 0];
        basis[bodyAxis] = 1;
        MVector!float direction = toDual * MVector!float(basis);
        foreach (gridAxis; 0 .. 3) {
            float kleinRate = (direction.data[gridAxis] - klein[gridAxis] * direction.data[3]) / point.data[3];
            jacobian[gridAxis][bodyAxis] = gridSlope(layout, klein[gridAxis]) * kleinRate;
        }
    }
    return jacobian;
}

float gridSlope(ref const ChunkLayout layout, float klein) {
    return (layout.dualToGrid(klein + GRID_SLOPE_STEP) - layout.dualToGrid(klein - GRID_SLOPE_STEP)) / (2 * GRID_SLOPE_STEP);
}

MPoint!float chunkPointInNode(Vertex vertex, float[3] chunk) {
    return (vertex.chunkToNode * MVector!float([chunk[0], chunk[1], chunk[2], 1.0f])).normalizedPoint();
}

float[3][3] inverted(float[3][3] m) {
    float[3][3] cofactor = [
        [m[1][1] * m[2][2] - m[1][2] * m[2][1], m[0][2] * m[2][1] - m[0][1] * m[2][2], m[0][1] * m[1][2] - m[0][2] * m[1][1]],
        [m[1][2] * m[2][0] - m[1][0] * m[2][2], m[0][0] * m[2][2] - m[0][2] * m[2][0], m[0][2] * m[1][0] - m[0][0] * m[1][2]],
        [m[1][0] * m[2][1] - m[1][1] * m[2][0], m[0][1] * m[2][0] - m[0][0] * m[2][1], m[0][0] * m[1][1] - m[0][1] * m[1][0]],
    ];
    float determinant = m[0][0] * cofactor[0][0] + m[0][1] * cofactor[1][0] + m[0][2] * cofactor[2][0];
    float[3][3] result;
    foreach (row; 0 .. 3) {
        foreach (column; 0 .. 3) {
            result[row][column] = cofactor[row][column] / determinant;
        }
    }
    return result;
}

float[3] applied(float[3][3] matrix, float[3] v) {
    return [
        matrix[0][0] * v[0] + matrix[0][1] * v[1] + matrix[0][2] * v[2],
        matrix[1][0] * v[0] + matrix[1][1] * v[1] + matrix[1][2] * v[2],
        matrix[2][0] * v[0] + matrix[2][1] * v[1] + matrix[2][2] * v[2],
    ];
}

unittest {
    float[3][3] m = [
        [2, 1, 0],
        [0, 1, 0],
        [0, 0, 3],
    ];
    float[3] v = [1, 2, 3];
    float[3] back = applied(inverted(m), applied(m, v));
    foreach (axis; 0 .. 3) {
        assert(back[axis] - v[axis] < TEST_TOLERANCE && v[axis] - back[axis] < TEST_TOLERANCE);
    }
}
