module client.graphics.frustum;

import core.stdc.math : atanf, cosf, sinf, tanf;
import common.math : MDirection, MVector;

enum uint FRUSTUM_PLANE_COUNT = 5;
enum float KLEIN_FAR_PLANE = 1.0f;

struct Frustum {
    float left;
    float right;
    float down;
    float up;

    static Frustum fromVerticalFov(float verticalFov, float aspectRatio) {
        float horizontalFov = atanf(aspectRatio * tanf(verticalFov));
        return Frustum(-horizontalFov, horizontalFov, -verticalFov, verticalFov);
    }

    MDirection!float[FRUSTUM_PLANE_COUNT] planes() const {
        MDirection!float[FRUSTUM_PLANE_COUNT] result = [
            MDirection!float(MVector!float(cosf(left), 0, sinf(left), 0)),
            MDirection!float(MVector!float(-cosf(right), 0, -sinf(right), 0)),
            MDirection!float(MVector!float(0, cosf(down), sinf(down), 0)),
            MDirection!float(MVector!float(0, -cosf(up), -sinf(up), 0)),
            MDirection!float(MVector!float(0, 0, -1, 0)),
        ];
        return result;
    }

    float[16] projection(float near) const {
        float tanLeft = tanf(left);
        float tanRight = tanf(right);
        float tanDown = tanf(down);
        float tanUp = tanf(up);
        float inverseWidth = 1.0f / (tanRight - tanLeft);
        float inverseHeight = 1.0f / (tanDown - tanUp);
        float[16] result = 0;
        result[0] = 2.0f * inverseWidth;
        result[5] = 2.0f * inverseHeight;
        result[8] = (tanRight + tanLeft) * inverseWidth;
        result[9] = (tanDown + tanUp) * inverseHeight;
        result[10] = -near / (near - KLEIN_FAR_PLANE);
        result[11] = -1.0f;
        result[14] = -(near * KLEIN_FAR_PLANE) / (near - KLEIN_FAR_PLANE);
        return result;
    }
}
