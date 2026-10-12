module client.graphics.matrices;

import geometry.lorentz : Mat4;

enum uint MATRIX_FLOATS = 16;
enum uint COFACTOR_COUNT = 12;

float[MATRIX_FLOATS] flatten(Mat4!float matrix) {
    float[MATRIX_FLOATS] result;
    foreach (column; 0 .. 4) {
        foreach (row; 0 .. 4) {
            result[column * 4 + row] = matrix.c[column][row];
        }
    }
    return result;
}

float[MATRIX_FLOATS] matrixMultiply(float[MATRIX_FLOATS] a, float[MATRIX_FLOATS] b) {
    float[MATRIX_FLOATS] result = 0;
    foreach (column; 0 .. 4) {
        foreach (row; 0 .. 4) {
            float sum = 0;
            foreach (k; 0 .. 4) {
                sum += a[k * 4 + row] * b[column * 4 + k];
            }
            result[column * 4 + row] = sum;
        }
    }
    return result;
}

float[COFACTOR_COUNT] cofactors(float[MATRIX_FLOATS] m) {
    float[COFACTOR_COUNT] b = [
        m[0] * m[5] - m[1] * m[4],
        m[0] * m[6] - m[2] * m[4],
        m[0] * m[7] - m[3] * m[4],
        m[1] * m[6] - m[2] * m[5],
        m[1] * m[7] - m[3] * m[5],
        m[2] * m[7] - m[3] * m[6],
        m[8] * m[13] - m[9] * m[12],
        m[8] * m[14] - m[10] * m[12],
        m[8] * m[15] - m[11] * m[12],
        m[9] * m[14] - m[10] * m[13],
        m[9] * m[15] - m[11] * m[13],
        m[10] * m[15] - m[11] * m[14],
    ];
    return b;
}

float determinantOf(float[COFACTOR_COUNT] b) {
    return b[0] * b[11] - b[1] * b[10] + b[2] * b[9] + b[3] * b[8] - b[4] * b[7] + b[5] * b[6];
}

float determinant(float[MATRIX_FLOATS] m) {
    return determinantOf(cofactors(m));
}
