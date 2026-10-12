module client.graphics.frustum;

import core.math : sqrt;
import core.stdc.math : tanf;
import base.units : Angle;
import geometry.lorentz : Normal, Vec4;

enum uint FRUSTUM_PLANE_COUNT = 5;

// A symmetric view frustum, kept as the tangents of its half angles. The camera looks down -z.
struct Frustum {
    float tanHalfWidth;
    float tanHalfHeight;

    static Frustum fromVerticalHalf(Angle halfVertical, float aspectRatio) {
        float tanHalfHeight = tanf(halfVertical.value);
        return Frustum(aspectRatio * tanHalfHeight, tanHalfHeight);
    }

    // Inward unit normals of the four sides and of the plane behind the camera. They all pass through the camera,
    // where Klein and hyperboloid coordinates agree on angles, so they hold in both.
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

    // Takes a camera-space point (x, y, z, w) to clip space. Dividing by clip w = -z gives the perspective of its
    // Klein position (x, y, z) / w, and the clip depth is depthScale (z + w), which divides to
    // depthScale / kleinDepth - depthScale with kleinDepth = -z / w: 1 at the near plane and 0 at the ideal boundary,
    // where the Klein depth reaches 1.
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
