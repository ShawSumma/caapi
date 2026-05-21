module client.graphics.frustum;

import std.math : tan, atan, sin, cos, sinh;
import common.math : MVector, MDirection, MPoint;

struct Frustum {
    float left;
    float right;
    float down;
    float up;

    static Frustum fromVfov(float vfov, float aspectRatio) {
        float hfov = atan(aspectRatio * tan(vfov));
        Frustum f;
        f.left = -hfov;
        f.right = hfov;
        f.down = -vfov;
        f.up = vfov;
        return f;
    }

    MDirection!float[5] planes() const {
        return [
            MDirection!float(MVector!float(cos(left), 0, -sin(left), 0)),
            MDirection!float(MVector!float(-cos(right), 0, sin(right), 0)),
            MDirection!float(MVector!float(0, cos(down), -sin(down), 0)),
            MDirection!float(MVector!float(0, -cos(up), sin(up), 0)),
            MDirection!float(MVector!float(0, 0, -1, 0)),
        ];
    }

    bool sphereOutside(const ref MDirection!float[5] fp, const ref MPoint!float center, float radius) const {
        float threshold = sinh(radius);
        foreach (ref p; fp) {
            if (p.mip(center) > threshold) {
                return true;
            }
        }
        return false;
    }

    float[16] projection(float znear) const {
        float zfar = 1.0f;
        float l = tan(left);
        float r = tan(right);
        float d = tan(down);
        float u = tan(up);
        float idx = 1.0f / (r - l);
        float idy = 1.0f / (d - u);
        float sx = r + l;
        float sy = d + u;
        float za = -znear / (znear - zfar);
        float zb = -(znear * zfar) / (znear - zfar);
        float[16] m = 0;
        m[0]  = 2.0f * idx;
        m[5]  = 2.0f * idy;
        m[8]  = sx * idx;
        m[9]  = sy * idy;
        m[10] = za;
        m[11] = -1.0f;
        m[14] = zb;
        return m;
    }
}
