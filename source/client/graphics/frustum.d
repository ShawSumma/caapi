module client.graphics.frustum;

import core.math : sqrt;
import geometry.lorentz : Normal, Vec4;

enum uint FRUSTUM_PLANE_COUNT = 5;

struct Frustum {
    float tanHalfWidth;
    float tanHalfHeight;

    static Frustum fromVerticalTangent(float tanHalfHeight, float aspectRatio) {
        return Frustum(aspectRatio * tanHalfHeight, tanHalfHeight);
    }

    Normal!float[FRUSTUM_PLANE_COUNT] planes() const {
        Normal!float[FRUSTUM_PLANE_COUNT] found = [
            sidePlane(1, 0, tanHalfWidth),
            sidePlane(-1, 0, tanHalfWidth),
            sidePlane(0, 1, tanHalfHeight),
            sidePlane(0, -1, tanHalfHeight),
            Normal!float(Vec4!float([0, 0, -1, 0])),
        ];
        return found;
    }

    float[16] projection(float near) const {
        float scale = kleinDepthScale(near);
        float[16] columns = 0;
        columns[0] = 1 / tanHalfWidth;
        columns[5] = -1 / tanHalfHeight;
        columns[10] = scale;
        columns[11] = -1;
        columns[14] = scale;
        return columns;
    }
}

float kleinDepthScale(float near) {
    return near / (1 - near);
}

Normal!float sidePlane(float x, float y, float tangent) {
    float length = sqrt(1 + tangent * tangent);
    return Normal!float(Vec4!float([x / length, y / length, -tangent / length, 0]));
}
