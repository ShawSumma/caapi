module common.math;

import cmath = core.stdc.math;

// libc splits these by width instead of overloading, so pick the right one
// from the element type. Keeps every call site below unchanged.
N sqrt(N)(N v) {
    // The dodecahedron tables are built at compile time, and libc has no
    // source for CTFE to interpret, so that path gets Newton's method.
    if (__ctfe) {
        return ctfeSqrt(v);
    }
    static if (is(N == float)) {
        return cmath.sqrtf(v);
    } else {
        return cmath.sqrt(v);
    }
}

N ctfeSqrt(N)(N v) {
    if (v <= 0) {
        return 0;
    }
    // Iterate in double regardless of N: for double it is the exact working
    // precision, and for float the extra bits round off cleanly at the end.
    double target = cast(double) v;
    double x = target;
    foreach (i; 0 .. 200) {
        double next = (x + target / x) / 2;
        if (next == x) {
            break;
        }
        x = next;
    }
    return cast(N) x;
}

N cosh(N)(N v) {
    static if (is(N == float)) {
        return cmath.coshf(v);
    } else {
        return cmath.cosh(v);
    }
}

N sinh(N)(N v) {
    static if (is(N == float)) {
        return cmath.sinhf(v);
    } else {
        return cmath.sinh(v);
    }
}

N acosh(N)(N v) {
    static if (is(N == float)) {
        return cmath.acoshf(v);
    } else {
        return cmath.acosh(v);
    }
}

N tanh(N)(N v) {
    static if (is(N == float)) {
        return cmath.tanhf(v);
    } else {
        return cmath.tanh(v);
    }
}

N atanh(N)(N v) {
    static if (is(N == float)) {
        return cmath.atanhf(v);
    } else {
        return cmath.atanh(v);
    }
}

N asinh(N)(N v) {
    static if (is(N == float)) {
        return cmath.asinhf(v);
    } else {
        return cmath.asinh(v);
    }
}

N floor(N)(N v) {
    static if (is(N == float)) {
        return cmath.floorf(v);
    } else {
        return cmath.floor(v);
    }
}

N ceil(N)(N v) {
    static if (is(N == float)) {
        return cmath.ceilf(v);
    } else {
        return cmath.ceil(v);
    }
}

N fabs(N)(N v) {
    static if (is(N == float)) {
        return cmath.fabsf(v);
    } else {
        return cmath.fabs(v);
    }
}

N exp(N)(N v) {
    static if (is(N == float)) {
        return cmath.expf(v);
    } else {
        return cmath.exp(v);
    }
}

N log(N)(N v) {
    static if (is(N == float)) {
        return cmath.logf(v);
    } else {
        return cmath.log(v);
    }
}

N exp2(N)(N v) {
    static if (is(N == float)) {
        return cmath.exp2f(v);
    } else {
        return cmath.exp2(v);
    }
}

N pow(N)(N base, N power) {
    static if (is(N == float)) {
        return cmath.powf(base, power);
    } else {
        return cmath.pow(base, power);
    }
}

N sin(N)(N v) {
    static if (is(N == float)) {
        return cmath.sinf(v);
    } else {
        return cmath.sin(v);
    }
}

N cos(N)(N v) {
    static if (is(N == float)) {
        return cmath.cosf(v);
    } else {
        return cmath.cos(v);
    }
}

N acos(N)(N v) {
    static if (is(N == float)) {
        return cmath.acosf(v);
    } else {
        return cmath.acos(v);
    }
}

N atan2(N)(N y, N x) {
    static if (is(N == float)) {
        return cmath.atan2f(y, x);
    } else {
        return cmath.atan2(y, x);
    }
}

N fmin(N)(N a, N b) {
    if (a < b) {
        return a;
    }
    return b;
}

N fmax(N)(N a, N b) {
    if (a > b) {
        return a;
    }
    return b;
}

N abs(N)(N v) {
    if (v < 0) {
        return -v;
    }
    return v;
}

enum float PI = 3.14159265358979323846f;

bool isNaN(N)(N v) {
    return v != v;
}

bool isFinite(N)(N v) {
    return v == v && v <= N.max && v >= -N.max;
}

bool isInfinity(N)(N v) {
    return v > N.max || v < -N.max;
}

struct MVector(N) if (__traits(isFloating, N)) {
    N[4] data = [0, 0, 0, 0];

    @property ref inout(N) x() inout {
        return data[0];
    }

    @property ref inout(N) y() inout {
        return data[1];
    }

    @property ref inout(N) z() inout {
        return data[2];
    }

    @property ref inout(N) w() inout {
        return data[3];
    }

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

    N mip(const MVector other) const {
        return data[0] * other.data[0] + data[1] * other.data[1] + data[2] * other.data[2] - data[3] * other.data[3];
    }

    MPoint!N normalizedPoint() const {
        N scale_sq = -this.mip(this);
        if (scale_sq <= 0) {
            return MPoint!N.origin();
        }
        N scale = sqrt(scale_sq);
        return MPoint!N(this / scale);
    }

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
        foreach (i; 0 .. 4) {
            r.data[i] = data[i] + rhs.data[i];
        }
        return r;
    }

    MVector opBinary(string op)(const MVector rhs) const if (op == "-") {
        MVector r;
        foreach (i; 0 .. 4) {
            r.data[i] = data[i] - rhs.data[i];
        }
        return r;
    }

    MVector opBinary(string op)(N rhs) const if (op == "*") {
        MVector r;
        foreach (i; 0 .. 4) {
            r.data[i] = data[i] * rhs;
        }
        return r;
    }

    MVector opBinary(string op)(N rhs) const if (op == "/") {
        MVector r;
        foreach (i; 0 .. 4) {
            r.data[i] = data[i] / rhs;
        }
        return r;
    }

    MVector opUnary(string op)() const if (op == "-") {
        MVector r;
        foreach (i; 0 .. 4) {
            r.data[i] = -data[i];
        }
        return r;
    }

    ref N opIndex(size_t i) return {
        return data[i];
    }

    N opIndex(size_t i) const {
        return data[i];
    }

    MVector!N2 toType(N2)() const if (__traits(isFloating, N2)) {
        MVector!N2 r;
        static foreach (i; 0 .. 4) {
            r.data[i] = cast(N2)(data[i]);
        }
        return r;
    }
}

struct MPoint(N) if (__traits(isFloating, N)) {
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
        static if (is(T == MVector!N)) {
            return vec.mip(other);
        }
        else {
            return vec.mip(other.vec);
        }
    }

    MPoint midpoint(const MPoint other) const {
        return (vec + other.vec).normalizedPoint();
    }

    N distance(const MPoint other) const {
        return acosh(-vec.mip(other.vec));
    }

    ref const(MVector!N) asVector() const return {
        return vec;
    }

    MPoint!N2 toType(N2)() const if (__traits(isFloating, N2)) {
        return MPoint!N2(vec.toType!N2());
    }

    ref N opIndex(size_t i) return {
        return vec.data[i];
    }

    N opIndex(size_t i) const {
        return vec.data[i];
    }
}

struct MDirection(N) if (__traits(isFloating, N)) {
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
        static if (is(T == MVector!N)) {
            return vec.mip(other);
        }
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

    MDirection!N2 toType(N2)() const if (__traits(isFloating, N2)) {
        return MDirection!N2(vec.toType!N2());
    }

    ref N opIndex(size_t i) return {
        return vec.data[i];
    }

    N opIndex(size_t i) const {
        return vec.data[i];
    }
}

struct Matrix4(N) if (__traits(isFloating, N)) {
    N[4][4] data = 0;

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

    N determinant() const {
        N det = 0;
        foreach (col; 0 .. 4) {
            N minor = 0;
            N[3][3] m;
            foreach (c2; 0 .. 4) {
                if (c2 == col) {
                    continue;
                }
                size_t mc = c2 < col ? c2 : c2 - 1;
                foreach (r2; 1 .. 4) {
                    m[mc][r2 - 1] = data[c2][r2];
                }
            }
            minor = m[0][0] * (m[1][1] * m[2][2] - m[2][1] * m[1][2])
                  - m[1][0] * (m[0][1] * m[2][2] - m[2][1] * m[0][2])
                  + m[2][0] * (m[0][1] * m[1][2] - m[1][1] * m[0][2]);
            N sign = (col % 2 == 0) ? 1 : -1;
            det += sign * data[col][0] * minor;
        }
        return det;
    }
}

struct MIsometry(N) if (__traits(isFloating, N)) {
    Matrix4!N mat;

    this(Matrix4!N m) {
        mat = m;
    }

    static MIsometry identity() {
        return MIsometry(Matrix4!N.identity());
    }

    static MIsometry reflection(const MDirection!N normal) {
        Matrix4!N outer = normal.vec.minkowskiOuterProduct(normal.vec);
        return MIsometry(Matrix4!N.identity() - outer * 2);
    }

    static MIsometry translation(const MPoint!N a, const ref MPoint!N b) {
        MVector!N aPlusB = a.vec + b.vec;
        Matrix4!N outer_ba = b.vec.minkowskiOuterProduct(a.vec) * cast(N)(2.0);
        Matrix4!N outer_ab = aPlusB.minkowskiOuterProduct(aPlusB);
        N denom = cast(N)(1.0) - a.vec.mip(b.vec);
        return MIsometry(Matrix4!N.identity() - outer_ba + outer_ab * (cast(N)(1.0) / denom));
    }

    static MIsometry translationAlong(N[3] v) {
        N norm = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
        if (norm == 0) {
            return MIsometry.identity();
        }
        N sinhc_val = sinh(norm) / norm;
        N cosh_val = cosh(norm);
        MPoint!N target = MPoint!N(
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

    MIsometry inverse() const {
        Matrix4!N r;
        foreach (i; 0 .. 3) {
            foreach (j; 0 .. 3) {
                r.data[j][i] = mat.data[i][j];
            }
        }
        foreach (i; 0 .. 3) {
            r.data[i][3] = -mat.data[3][i];
            r.data[3][i] = -mat.data[i][3];
        }
        r.data[3][3] = mat.data[3][3];
        return MIsometry(r);
    }

    bool parity() const {
        return mat.determinant() < 0;
    }

    MVector!N opBinary(string op)(const MVector!N v) const if (op == "*") {
        return mat * v;
    }

    MPoint!N opBinary(string op)(const MPoint!N p) const if (op == "*") {
        return MPoint!N(mat * p.vec);
    }

    MDirection!N opBinary(string op)(const MDirection!N d) const if (op == "*") {
        return MDirection!N(mat * d.vec);
    }

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

    MIsometry!N2 toType(N2)() const if (__traits(isFloating, N2)) {
        Matrix4!N2 r;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                r.data[col][row] = cast(N2)(mat.data[col][row]);
            }
        }
        return MIsometry!N2(r);
    }

    MIsometry renormalized() const {
        MPoint!N translationTarget = MVector!N(
            mat.data[3][0], mat.data[3][1], mat.data[3][2], mat.data[3][3]
        ).normalizedPoint();
        MIsometry normalizedTranslation = MIsometry.translation(MPoint!N.origin(), translationTarget);

        MIsometry orientComp = normalizedTranslation.inverse() * this;

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
                foreach (k; 0 .. 3) {
                    dot += v[k] * q[prev][k];
                }
                foreach (k; 0 .. 3) {
                    v[k] -= dot * q[prev][k];
                }
            }
            N norm = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
            if (norm > 0) {
                foreach (k; 0 .. 3) {
                    v[k] /= norm;
                }
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

N sqr(N)(N x) {
    return x * x;
}

float[3] sanitizeMotionInput(float[3] v) {
    foreach (float x; v) {
        if (isNaN(x) || isInfinity(x)) {
            return [0.0f, 0.0f, 0.0f];
        }
    }
    float norm = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    float scale = 1.0f / (norm > 1.0f ? norm : 1.0f);
    return [v[0] * scale, v[1] * scale, v[2] * scale];
}

N sinhc(N)(N x) if (__traits(isFloating, N)) {
    if (x == 0) {
        return 1;
    }
    return sinh(x) / x;
}

void projectToPlane(N)(ref N[3] subject, const ref N[3] normal, const ref N[3] projDir, N distance)
    if (__traits(isFloating, N))
{
    N dotSN = 0;
    N dotPN = 0;
    foreach (i; 0 .. 3) {
        dotSN += subject[i] * normal[i];
        dotPN += projDir[i] * normal[i];
    }
    N t = (distance - dotSN) / dotPN;
    foreach (i; 0 .. 3) {
        subject[i] += projDir[i] * t;
    }
}
