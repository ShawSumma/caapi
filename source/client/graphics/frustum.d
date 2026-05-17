module client.graphics.frustum;

import std.math : tan, atan;

/// Port of hypermine's Frustum (client/src/graphics/frustum.rs).
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

    /// Right-handed y-up inverse-Z perspective projection with far plane at 1.0.
    /// The Beltrami-Klein vertices fall within a ball of radius 1, so far=1 is the natural choice.
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
        // Column-major flat array
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
