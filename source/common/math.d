/// This module defines vector and matrix types for use in Minkowski space,
/// allowing natural operations to be performed in hyperbolic space.
module common.math;

import std.math;
import std.traits : isFloatingPoint;
import std.math : isNaN, isInfinity;

/// A stack-allocated 4-dimensional column-vector in Minkowski space.
/// Useful for computations in the hyperboloid model of hyperbolic space.
/// The last coordinate (w) is the special "time" coordinate.
struct MVector(N) if (isFloatingPoint!N) {
    N[4] data = [0, 0, 0, 0];

    @property ref inout(N) x() inout { return data[0]; }
    @property ref inout(N) y() inout { return data[1]; }
    @property ref inout(N) z() inout { return data[2]; }
    @property ref inout(N) w() inout { return data[3]; }

    this(N x, N y, N z, N w) {
        data = [x, y, z, w];
    }

    static MVector zero() {
        return MVector(0, 0, 0, 0);
    }

    static MVector origin() {
        return w_basis();
    }

    static MVector x_basis() {
        return MVector(1, 0, 0, 0);
    }

    static MVector y_basis() {
        return MVector(0, 1, 0, 0);
    }

    static MVector z_basis() {
        return MVector(0, 0, 1, 0);
    }

    static MVector w_basis() {
        return MVector(0, 0, 0, 1);
    }

    /// Minkowski inner product: x*x + y*y + z*z - w*w
    N mip(const MVector other) const {
        return data[0] * other.data[0] + data[1] * other.data[1] + data[2] * other.data[2] - data[3] * other.data[3];
    }

    /// Normalize so that self-mip is -1 (point on hyperboloid)
    MPoint!N normalizedPoint() const {
        N scale_sq = -this.mip(this);
        if (scale_sq <= 0) {
            return MPoint!N.origin();
        }
        N scale = sqrt(scale_sq);
        return MPoint!N(this / scale);
    }

    /// Normalize so that self-mip is 1 (direction/plane)
    MDirection!N normalizedDirection() const {
        N scale_sq = this.mip(this);
        if (scale_sq <= 0) {
            return MDirection!N.x();
        }
        N scale = sqrt(scale_sq);
        return MDirection!N(this / scale);
    }

    N[3] xyz() const {
        return data[0 .. 3];
    }

    /// Minkowski outer product
    Matrix4!N minkowskiOuterProduct(const MVector other) const {
        Matrix4!N result;
        foreach (col; 0 .. 4) {
            N factor = col == 3 ? -other.data[col] : other.data[col];
            foreach (row; 0 .. 4) {
                result[col][row] = data[row] * factor;
            }
        }
        return result;
    }

    MVector opBinary(string op)(const MVector rhs) const if (op == "+") {
        MVector r;
        foreach (i; 0 .. 4) r.data[i] = data[i] + rhs.data[i];
        return r;
    }

    MVector opBinary(string op)(const MVector rhs) const if (op == "-") {
        MVector r;
        foreach (i; 0 .. 4) r.data[i] = data[i] - rhs.data[i];
        return r;
    }

    MVector opBinary(string op)(N rhs) const if (op == "*") {
        MVector r;
        foreach (i; 0 .. 4) r.data[i] = data[i] * rhs;
        return r;
    }

    MVector opBinary(string op)(N rhs) const if (op == "/") {
        MVector r;
        foreach (i; 0 .. 4) r.data[i] = data[i] / rhs;
        return r;
    }

    MVector opUnary(string op)() const if (op == "-") {
        MVector r;
        foreach (i; 0 .. 4) r.data[i] = -data[i];
        return r;
    }

    ref N opIndex(size_t i) return {
        return data[i];
    }

    N opIndex(size_t i) const {
        return data[i];
    }

    MVector!N2 toType(N2)() const if (isFloatingPoint!N2) {
        MVector!N2 r;
        static foreach (i; 0 .. 4) r.data[i] = cast(N2)(data[i]);
        return r;
    }
}

/// An MVector with self-mip == -1, representing a point in hyperbolic space.
struct MPoint(N) if (isFloatingPoint!N) {
    MVector!N vec;

    this(MVector!N v) {
        vec = v;
    }

    this(N x, N y, N z, N w) {
        vec = MVector!N(x, y, z, w);
    }

    static MPoint origin() {
        return MPoint(MVector!N.w_basis());
    }

    alias w = MPoint.origin;

    static MPoint newUnchecked(N x, N y, N z, N w) {
        return MPoint(MVector!N(x, y, z, w));
    }

    N mip(T)(const ref T other) const {
        static if (is(T == MVector!N))
            return vec.mip(other);
        else {
            return vec.mip(other.vec);
        }
    }

    /// Returns the midpoint between two points on the hyperboloid
    MPoint midpoint(const MPoint other) const {
        return (vec + other.vec).normalizedPoint();
    }

    /// Hyperbolic distance between two normalized points
    N distance(const MPoint other) const {
        return acosh(-vec.mip(other.vec));
    }

    ref const(MVector!N) asVector() const return {
        return vec;
    }

    MPoint!N2 toType(N2)() const if (isFloatingPoint!N2) {
        return MPoint!N2(vec.toType!N2());
    }

    ref N opIndex(size_t i) return {
        return vec.data[i];
    }

    N opIndex(size_t i) const {
        return vec.data[i];
    }
}

/// An MVector with self-mip == 1, representing a direction/plane in hyperbolic space.
struct MDirection(N) if (isFloatingPoint!N) {
    MVector!N vec;

    this(MVector!N v) {
        vec = v;
    }

    this(N x, N y, N z, N w) {
        vec = MVector!N(x, y, z, w);
    }

    static MDirection x() {
        return MDirection(MVector!N.x_basis());
    }

    static MDirection y() {
        return MDirection(MVector!N.y_basis());
    }

    static MDirection z() {
        return MDirection(MVector!N.z_basis());
    }

    static MDirection newUnchecked(N x, N y, N z, N w) {
        return MDirection(MVector!N(x, y, z, w));
    }

    N mip(T)(const ref T other) const {
        static if (is(T == MVector!N))
            return vec.mip(other);
        else {
            return vec.mip(other.vec);
        }
    }

    ref const(MVector!N) asVector() const return {
        return vec;
    }

    MDirection opUnary(string op)() const if (op == "-") {
        return MDirection(-vec);
    }

    MDirection!N2 toType(N2)() const if (isFloatingPoint!N2) {
        return MDirection!N2(vec.toType!N2());
    }

    ref N opIndex(size_t i) return {
        return vec.data[i];
    }

    N opIndex(size_t i) const {
        return vec.data[i];
    }
}

/// A 4x4 matrix stored in column-major order.
/// data[col][row]
struct Matrix4(N) if (isFloatingPoint!N) {
    N[4][4] data = 0; // data[col][row]

    static Matrix4 identity() {
        Matrix4 m;
        foreach (i; 0 .. 4) {
            m.data[i][i] = 1;
        }
        return m;
    }

    static Matrix4 zero() {
        return Matrix4.init;
    }

    static Matrix4 newScaling(N s) {
        Matrix4 m;
        m.data[0][0] = s;
        m.data[1][1] = s;
        m.data[2][2] = s;
        m.data[3][3] = 1;
        return m;
    }

    /// Matrix * vector
    MVector!N opBinary(string op)(const MVector!N v) const if (op == "*") {
        MVector!N r;
        foreach (row; 0 .. 4) {
            N sum = 0;
            foreach (col; 0 .. 4) {
                sum += data[col][row] * v.data[col];
            }
            r.data[row] = sum;
        }
        return r;
    }

    /// Matrix * matrix
    Matrix4 opBinary(string op)(const Matrix4 rhs) const if (op == "*") {
        Matrix4 r;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                N sum = 0;
                foreach (k; 0 .. 4) {
                    sum += data[k][row] * rhs.data[col][k];
                }
                r.data[col][row] = sum;
            }
        }
        return r;
    }

    Matrix4 opBinary(string op)(N rhs) const if (op == "*") {
        Matrix4 r;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                r.data[col][row] = data[col][row] * rhs;
            }
        }
        return r;
    }

    Matrix4 opBinary(string op)(const Matrix4 rhs) const if (op == "+") {
        Matrix4 r;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                r.data[col][row] = data[col][row] + rhs.data[col][row];
            }
        }
        return r;
    }

    Matrix4 opBinary(string op)(const Matrix4 rhs) const if (op == "-") {
        Matrix4 r;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                r.data[col][row] = data[col][row] - rhs.data[col][row];
            }
        }
        return r;
    }

    ref inout(N[4]) opIndex(size_t col) inout return {
        return data[col];
    }

    N determinant3x3() const {
        return data[0][0] * (data[1][1] * data[2][2] - data[2][1] * data[1][2])
             - data[1][0] * (data[0][1] * data[2][2] - data[2][1] * data[0][2])
             + data[2][0] * (data[0][1] * data[1][2] - data[1][1] * data[0][2]);
    }
}

/// A 4x4 Minkowski isometry matrix preserving the Minkowski inner product.
struct MIsometry(N) if (isFloatingPoint!N) {
    Matrix4!N mat;

    this(Matrix4!N m) {
        mat = m;
    }

    static MIsometry identity() {
        return MIsometry(Matrix4!N.identity());
    }

    /// Reflection about the hyperbolic plane with given normal
    static MIsometry reflection(const MDirection!N normal) {
        auto outer = normal.vec.minkowskiOuterProduct(normal.vec);
        return MIsometry(Matrix4!N.identity() - outer * 2);
    }

    /// Translation from point a to point b
    static MIsometry translation(const MPoint!N a, const ref MPoint!N b) {
        auto aPlusB = a.vec + b.vec;
        auto outer_ba = b.vec.minkowskiOuterProduct(a.vec) * cast(N)(2.0);
        auto outer_ab = aPlusB.minkowskiOuterProduct(aPlusB);
        N denom = cast(N)(1.0) - a.vec.mip(b.vec);
        return MIsometry(Matrix4!N.identity() - outer_ba + outer_ab * (cast(N)(1.0) / denom));
    }

    /// Translation from origin along direction v with distance |v|
    static MIsometry translationAlong(N[3] v) {
        N norm = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
        if (norm == 0) {
            return MIsometry.identity();
        }
        N sinhc_val = sinh(norm) / norm;
        N cosh_val = cosh(norm);
        auto target = MPoint!N(
            v[0] * sinhc_val,
            v[1] * sinhc_val,
            v[2] * sinhc_val,
            cosh_val
        );
        return MIsometry.translation(MPoint!N.origin(), target);
    }

    static MIsometry fromColumnsUnchecked(const MDirection!N[3] dirs, MPoint!N point) {
        Matrix4!N m;
        foreach (col; 0 .. 3) {
            foreach (row; 0 .. 4) {
                m.data[col][row] = dirs[col].vec.data[row];
            }
        }
        foreach (row; 0 .. 4) {
            m.data[3][row] = point.vec.data[row];
        }
        return MIsometry(m);
    }

    /// Minkowski adjoint (efficient inverse for isometries)
    MIsometry inverse() const {
        Matrix4!N r;
        // Transpose upper-left 3x3
        foreach (i; 0 .. 3) {
            foreach (j; 0 .. 3) {
                r.data[j][i] = mat.data[i][j];
            }
        }
        // Negate row 3 of cols 0..3 and col 3 of rows 0..3
        foreach (i; 0 .. 3) {
            r.data[i][3] = -mat.data[3][i];
            r.data[3][i] = -mat.data[i][3];
        }
        r.data[3][3] = mat.data[3][3];
        return MIsometry(r);
    }

    /// Whether the isometry reverses winding
    bool parity() const {
        return mat.determinant3x3() < 0;
    }

    /// Apply isometry to a vector
    MVector!N opBinary(string op)(const MVector!N v) const if (op == "*") {
        return mat * v;
    }

    /// Apply isometry to a point
    MPoint!N opBinary(string op)(const MPoint!N p) const if (op == "*") {
        return MPoint!N(mat * p.vec);
    }

    /// Apply isometry to a direction
    MDirection!N opBinary(string op)(const MDirection!N d) const if (op == "*") {
        return MDirection!N(mat * d.vec);
    }

    /// Compose isometries
    MIsometry opBinary(string op)(const MIsometry rhs) const if (op == "*") {
        return MIsometry(mat * rhs.mat);
    }

    ref inout(N) opIndex(size_t col, size_t row) inout return {
        return mat.data[col][row];
    }

    N[4] row(size_t i) const {
        N[4] r;
        foreach (col; 0 .. 4) {
            r[col] = mat.data[col][i];
        }
        return r;
    }

    MIsometry!N2 toType(N2)() const if (isFloatingPoint!N2) {
        Matrix4!N2 r;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                r.data[col][row] = cast(N2)(mat.data[col][row]);
            }
        }
        return MIsometry!N2(r);
    }

    /// Renormalize to correct for floating point drift
    MIsometry renormalized() const {
        auto translationTarget = MVector!N(
            mat.data[3][0], mat.data[3][1], mat.data[3][2], mat.data[3][3]
        ).normalizedPoint();
        auto normalizedTranslation = MIsometry.translation(MPoint!N.origin(), translationTarget);

        auto orientComp = normalizedTranslation.inverse() * this;

        // QR decomposition of the upper-left 3x3 to get an orthogonal matrix
        // Simplified Gram-Schmidt
        N[3][3] cols;
        foreach (col; 0 .. 3) {
            foreach (row; 0 .. 3) {
                cols[col][row] = orientComp.mat.data[col][row];
            }
        }

        N[3][3] q;
        foreach (col; 0 .. 3) {
            N[3] v = cols[col];
            foreach (prev; 0 .. col) {
                N dot = 0;
                foreach (k; 0 .. 3) dot += v[k] * q[prev][k];
                foreach (k; 0 .. 3) v[k] -= dot * q[prev][k];
            }
            N norm = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
            if (norm > 0) {
                foreach (k; 0 .. 3) v[k] /= norm;
            }
            q[col] = v;
        }

        Matrix4!N orientMat;
        foreach (col; 0 .. 3) {
            foreach (row; 0 .. 3) {
                orientMat.data[col][row] = q[col][row];
            }
        }
        orientMat.data[3][3] = 1;

        return normalizedTranslation * MIsometry(orientMat);
    }
}

/// Multiplies argument by itself
N sqr(N)(N x) {
    return x * x;
}

/// Clamp speed to 1.0 with graceful NaN handling
float[3] sanitizeMotionInput(float[3] v) {
    foreach (x; v) {
        if (isNaN(x) || isInfinity(x)) {
            return [0.0f, 0.0f, 0.0f];
        }
    }
    float norm = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    float scale = 1.0f / (norm > 1.0f ? norm : 1.0f);
    return [v[0] * scale, v[1] * scale, v[2] * scale];
}

/// sinhc(x) = sinh(x)/x, defined at x=0 as 1
N sinhc(N)(N x) if (isFloatingPoint!N) {
    if (x == 0) return 1;
    return sinh(x) / x;
}

/// Project subject onto a plane
void projectToPlane(N)(ref N[3] subject, const ref N[3] normal, const ref N[3] projDir, N distance)
    if (isFloatingPoint!N)
{
    N dotSN = 0, dotPN = 0;
    foreach (i; 0 .. 3) {
        dotSN += subject[i] * normal[i];
        dotPN += projDir[i] * normal[i];
    }
    N t = (distance - dotSN) / dotPN;
    foreach (i; 0 .. 3) {
        subject[i] += projDir[i] * t;
    }
}
