module common.math;

import std.math : sqrt, sinh, cosh, sin, cos, log;

/// 4D vector in Minkowski space. The Minkowski inner product (mip) uses the
/// (+,+,+,-) signature: points on the hyperboloid satisfy mip(p,p) = -1.
struct MVector {
    float[4] data = [0, 0, 0, 0];

    this(float x, float y, float z, float w) {
        data = [x, y, z, w];
    }

    static MVector origin() {
        return MVector(0, 0, 0, 1);
    }

    ref float x() return { return data[0]; }
    ref float y() return { return data[1]; }
    ref float z() return { return data[2]; }
    ref float w() return { return data[3]; }

    /// Minkowski inner product with (+,+,+,-) signature.
    float mip(const MVector o) const {
        return data[0] * o.data[0] + data[1] * o.data[1]
             + data[2] * o.data[2] - data[3] * o.data[3];
    }

    MVector opBinary(string op)(const MVector r) const if (op == "+" || op == "-") {
        MVector v;
        static foreach (i; 0 .. 4) {
            mixin("v.data[i] = data[i] " ~ op ~ " r.data[i];");
        }
        return v;
    }

    MVector opBinary(string op : "*")(float s) const {
        MVector v;
        static foreach (i; 0 .. 4) {
            v.data[i] = data[i] * s;
        }
        return v;
    }

    /// Project a vector back onto the hyperboloid (mip = -1, w > 0).
    MVector normalized() const {
        float m = mip(this);
        float s = m < 0 ? 1.0f / sqrt(-m) : 1.0f;
        MVector v = this * s;
        if (v.data[3] < 0) {
            v = v * (-1.0f);
        }
        return v;
    }
}

/// Hyperbolic distance between two normalized points.
float hyperbolicDistance(const MVector a, const MVector b) {
    float d = -a.mip(b);
    if (d < 1.0f) {
        d = 1.0f;
    }
    return cast(float) log(d + sqrt(d * d - 1.0)); // acosh(d)
}

/// Column-major 4x4 matrix; doubles as a Minkowski isometry.
struct Matrix4 {
    // data[col][row]
    float[4][4] data = [
        [1, 0, 0, 0],
        [0, 1, 0, 0],
        [0, 0, 1, 0],
        [0, 0, 0, 1],
    ];

    static Matrix4 identity() {
        return Matrix4.init;
    }

    MVector opBinary(string op : "*")(const MVector v) const {
        MVector r;
        foreach (row; 0 .. 4) {
            float s = 0;
            foreach (col; 0 .. 4) {
                s += data[col][row] * v.data[col];
            }
            r.data[row] = s;
        }
        return r;
    }

    Matrix4 opBinary(string op : "*")(const Matrix4 rhs) const {
        Matrix4 r;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                float s = 0;
                foreach (k; 0 .. 4) {
                    s += data[k][row] * rhs.data[col][k];
                }
                r.data[col][row] = s;
            }
        }
        return r;
    }

    /// Flatten in column-major order for upload to GPU.
    float[16] flat() const {
        float[16] f;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                f[col * 4 + row] = data[col][row];
            }
        }
        return f;
    }
}

/// Translation along a direction by hyperbolic distance |v|, in Minkowski space.
/// v is a tangent vector at the origin (its w component is ignored).
Matrix4 translation(float[3] v) {
    float len = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    Matrix4 m = Matrix4.identity();
    if (len < 1e-9f) {
        return m;
    }
    float[3] u = [v[0] / len, v[1] / len, v[2] / len];
    float ch = cosh(len);
    float sh = sinh(len);
    // Boost along u: standard Lorentz boost in the (u, w) plane.
    foreach (i; 0 .. 3) {
        foreach (j; 0 .. 3) {
            m.data[j][i] += (ch - 1.0f) * u[i] * u[j];
        }
        m.data[3][i] = sh * u[i];
        m.data[i][3] = sh * u[i];
    }
    m.data[3][3] = ch;
    return m;
}

/// Inverse of a Minkowski isometry. For a Lorentz transform L, the inverse is
/// J * L^T * J where J = diag(1,1,1,-1) is the metric. Cheaper and stabler than
/// a general 4x4 inverse, and exact for the boosts/rotations we compose.
Matrix4 inverseIsometry(const ref Matrix4 m) {
    enum float[4] J = [1, 1, 1, -1];
    Matrix4 r;
    foreach (col; 0 .. 4) {
        foreach (row; 0 .. 4) {
            // (J * m^T * J)[col][row] = J[row] * m[row][col]... careful with layout:
            // m.data[col][row] is element (row,col). Transpose swaps -> (col,row).
            r.data[col][row] = J[col] * m.data[row][col] * J[row];
        }
    }
    return r;
}

/// Euclidean-style rotation in a coordinate plane (acts on the 3 space axes).
Matrix4 rotation(int axisA, int axisB, float angle) {
    Matrix4 m = Matrix4.identity();
    float c = cos(angle);
    float s = sin(angle);
    m.data[axisA][axisA] = c;
    m.data[axisB][axisB] = c;
    m.data[axisB][axisA] = -s;
    m.data[axisA][axisB] = s;
    return m;
}

/// Project a normalized hyperboloid point into the Poincare ball (eye at the
/// ideal point (0,0,0,-1)). Geodesics map to curves, which is what produces the
/// visible hyperbolic curvature; the camera at the origin maps to the center.
float[3] poincare(MVector p) {
    MVector n = p.normalized();
    float k = 1.0f / (n.data[3] + 1.0f);
    return [n.data[0] * k, n.data[1] * k, n.data[2] * k];
}

unittest {
    // The inverse isometry actually inverts: T^-1 * T == identity on the origin.
    Matrix4 t = translation([0.3f, -0.2f, 0.5f]) * rotation(0, 2, 0.7f);
    Matrix4 inv = inverseIsometry(t);
    MVector p = (inv * (t * MVector.origin())).normalized();
    MVector o = MVector.origin();
    assert(hyperbolicDistance(o, p) < 1e-4);
}

unittest {
    // The projection is hyperbolic, not Euclidean: a straight row of points at
    // equal forward depth, spaced equally in world space, must COMPRESS toward
    // the edges when projected (the fisheye). Build such a row by stepping along
    // x with a fixed-distance translation and check the projected gaps shrink.
    float[] xs;
    foreach (i; -5 .. 6) {
        Matrix4 step = translation([i * 0.4f, 0.0f, -1.0f]);
        float[3] q = poincare(step * MVector.origin());
        xs ~= q[0];
    }

    // In Euclidean projection these gaps would all be equal. Hyperbolic projection
    // compresses toward the edges, so each gap from the center outward is strictly
    // smaller than the previous one.
    float centerGap = xs[6] - xs[5];
    float edgeGap = xs[$ - 1] - xs[$ - 2];
    assert(edgeGap < centerGap * 0.6f);

    foreach (j; 7 .. xs.length) {
        float prev = xs[j - 1] - xs[j - 2];
        float cur = xs[j] - xs[j - 1];
        assert(cur < prev);
    }
}
