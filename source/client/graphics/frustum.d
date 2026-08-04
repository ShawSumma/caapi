module client.graphics.frustum;

import core.stdc.math : tan, atan, sin, cos, sinh;
import common.math : MVector, MDirection, MPoint;

struct Frustum {
    float left;
    float right;
    float down;
    float up;

    static Frustum fromVfov(float vfov, float aspectRatio) {
        float hfov = cast(float) atan(aspectRatio * tan(vfov));
        Frustum f;
        f.left = -hfov;
        f.right = hfov;
        f.down = -vfov;
        f.up = vfov;
        return f;
    }

    MDirection!float[5] planes() const {
        float cosLeft = cast(float) cos(left);
        float sinLeft = cast(float) sin(left);
        float cosRight = cast(float) cos(right);
        float sinRight = cast(float) sin(right);
        float cosDown = cast(float) cos(down);
        float sinDown = cast(float) sin(down);
        float cosUp = cast(float) cos(up);
        float sinUp = cast(float) sin(up);

        MDirection!float[5] result;
        result[0] = MDirection!float(MVector!float(cosLeft, 0, sinLeft, 0));
        result[1] = MDirection!float(MVector!float(-cosRight, 0, -sinRight, 0));
        result[2] = MDirection!float(MVector!float(0, cosDown, sinDown, 0));
        result[3] = MDirection!float(MVector!float(0, -cosUp, -sinUp, 0));
        result[4] = MDirection!float(MVector!float(0, 0, -1, 0));
        return result;
    }

    bool sphereOutside(
        const ref MDirection!float[5] fp,
        const ref MPoint!float center,
        float radius,
    ) const {
        float threshold = cast(float) sinh(radius);
        foreach (ref p; fp) {
            if (p.mip(center) < -threshold) {
                return true;
            }
        }
        return false;
    }

    float[16] projection(float znear) const {
        float zfar = 1.0f;
        float l = cast(float) tan(left);
        float r = cast(float) tan(right);
        float d = cast(float) tan(down);
        float u = cast(float) tan(up);
        float idx = 1.0f / (r - l);
        float idy = 1.0f / (d - u);
        float sx = r + l;
        float sy = d + u;
        float za = -znear / (znear - zfar);
        float zb = -(znear * zfar) / (znear - zfar);
        float[16] m = 0;
        m[0] = 2.0f * idx;
        m[5] = 2.0f * idy;
        m[8] = sx * idx;
        m[9] = sy * idy;
        m[10] = za;
        m[11] = -1.0f;
        m[14] = zb;
        return m;
    }
}
