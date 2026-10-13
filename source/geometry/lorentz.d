module geometry.lorentz;

import core.math : sqrt;
import core.stdc.math : acosh, cosh, sinh;

struct Vec4(T) {
    T[4] c = [0, 0, 0, 0];

    static Vec4 origin() {
        return Vec4([0, 0, 0, 1]);
    }

    T minkowski(Vec4 other) const {
        return c[0] * other.c[0] + c[1] * other.c[1] + c[2] * other.c[2] - c[3] * other.c[3];
    }

    Point!T toPoint() const {
        T scale = 1 / sqrt(-minkowski(this));
        return Point!T(c[3] < 0 ? this * -scale : this * scale);
    }

    Normal!T toNormal() const {
        return Normal!T(this * (1 / sqrt(minkowski(this))));
    }

    T[3] spatial() const {
        return [c[0], c[1], c[2]];
    }

    Vec4 opBinary(string op)(Vec4 rhs) const if (op == "+" || op == "-") {
        Vec4 result;
        foreach (i; 0 .. 4) {
            result.c[i] = mixin("c[i] " ~ op ~ " rhs.c[i]");
        }
        return result;
    }

    Vec4 opBinary(string op)(T rhs) const if (op == "*" || op == "/") {
        Vec4 result;
        foreach (i; 0 .. 4) {
            result.c[i] = mixin("c[i] " ~ op ~ " rhs");
        }
        return result;
    }

    Vec4 opUnary(string op)() const if (op == "-") {
        return this * -1;
    }

    Vec4!U as(U)() const {
        return Vec4!U([cast(U) c[0], cast(U) c[1], cast(U) c[2], cast(U) c[3]]);
    }
}

struct Point(T) {
    Vec4!T v;

    static Point origin() {
        return Point(Vec4!T.origin());
    }

    T minkowski(Vec4!T other) const {
        return v.minkowski(other);
    }

    T coshDistance(Point other) const {
        T value = -v.minkowski(other.v);
        return value < 1 ? 1 : value;
    }

    T distance(Point other) const {
        return cast(T) acosh(coshDistance(other));
    }

    Point midpoint(Point other) const {
        return (v + other.v).toPoint();
    }

    Point!U as(U)() const {
        return Point!U(v.as!U());
    }
}

struct Normal(T) {
    Vec4!T v;

    T minkowski(Vec4!T other) const {
        return v.minkowski(other);
    }

    Normal opUnary(string op)() const if (op == "-") {
        return Normal(-v);
    }

    Normal!U as(U)() const {
        return Normal!U(v.as!U());
    }
}

struct Mat4(T) {
    T[4][4] c = 0;

    static Mat4 identity() {
        Mat4 result;
        foreach (i; 0 .. 4) {
            result.c[i][i] = 1;
        }
        return result;
    }

    static Mat4 scaling(T factor) {
        Mat4 result;
        foreach (i; 0 .. 3) {
            result.c[i][i] = factor;
        }
        result.c[3][3] = 1;
        return result;
    }

    Vec4!T opBinary(string op)(Vec4!T v) const if (op == "*") {
        Vec4!T result;
        foreach (row; 0 .. 4) {
            result.c[row] = c[0][row] * v.c[0] + c[1][row] * v.c[1] + c[2][row] * v.c[2] + c[3][row] * v.c[3];
        }
        return result;
    }

    Mat4 opBinary(string op)(Mat4 rhs) const if (op == "*") {
        Mat4 result;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                result.c[col][row] = c[0][row] * rhs.c[col][0] + c[1][row] * rhs.c[col][1] + c[2][row] * rhs.c[col][2] + c[3][row] * rhs.c[col][3];
            }
        }
        return result;
    }

    Vec4!T column(size_t index) const {
        return Vec4!T(c[index]);
    }

    T determinant() const {
        T result = 0;
        foreach (col; 0 .. 4) {
            T sign = col % 2 == 0 ? 1 : -1;
            result += sign * c[col][0] * minor(col);
        }
        return result;
    }

    T minor(size_t skipped) const {
        size_t[3] cols;
        size_t count = 0;
        foreach (col; 0 .. 4) {
            if (col != skipped) {
                cols[count] = col;
                count += 1;
            }
        }
        T a(size_t col, size_t row) {
            return c[cols[col]][row + 1];
        }
        return a(0, 0) * (a(1, 1) * a(2, 2) - a(2, 1) * a(1, 2)) - a(1, 0) * (a(0, 1) * a(2, 2) - a(2, 1) * a(0, 2)) + a(2, 0) * (a(0, 1) * a(1, 2) - a(1, 1) * a(0, 2));
    }

    T[4] row(size_t index) const {
        return [c[0][index], c[1][index], c[2][index], c[3][index]];
    }
}

struct Motion(T) {
    Mat4!T m;

    static Motion identity() {
        return Motion(Mat4!T.identity());
    }

    static Motion reflection(Normal!T normal) {
        Vec4!T n = normal.v;
        Motion result = identity();
        foreach (col; 0 .. 4) {
            T lowered = col == 3 ? -n.c[col] : n.c[col];
            foreach (row; 0 .. 4) {
                result.m.c[col][row] -= 2 * n.c[row] * lowered;
            }
        }
        return result;
    }

    static Motion shift(T[3] v) {
        T length = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
        if (length == 0) {
            return identity();
        } else {
            T[3] u = [v[0] / length, v[1] / length, v[2] / length];
            T coshLength = cast(T) cosh(length);
            T sinhLength = cast(T) sinh(length);
            Motion result = identity();
            foreach (col; 0 .. 3) {
                foreach (row; 0 .. 3) {
                    result.m.c[col][row] += (coshLength - 1) * u[row] * u[col];
                }
                result.m.c[col][3] = sinhLength * u[col];
                result.m.c[3][col] = sinhLength * u[col];
            }
            result.m.c[3][3] = coshLength;
            return result;
        }
    }

    static Motion carrying(Point!T from, Point!T to) {
        return shiftTo(to) * shiftTo(from).inverse();
    }

    static Motion shiftTo(Point!T target) {
        T[3] spatial = target.v.spatial();
        T length = sqrt(spatial[0] * spatial[0] + spatial[1] * spatial[1] + spatial[2] * spatial[2]);
        if (length == 0) {
            return identity();
        } else {
            T distance = cast(T) acosh(target.v.c[3] < 1 ? 1 : target.v.c[3]);
            T scale = distance / length;
            return shift([spatial[0] * scale, spatial[1] * scale, spatial[2] * scale]);
        }
    }

    static Motion fromFrame(Normal!T[3] axes, Point!T origin) {
        Motion result;
        foreach (col; 0 .. 3) {
            result.m.c[col] = axes[col].v.c;
        }
        result.m.c[3] = origin.v.c;
        return result;
    }

    Motion inverse() const {
        Motion result;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                T sign = (col == 3) == (row == 3) ? 1 : -1;
                result.m.c[col][row] = sign * m.c[row][col];
            }
        }
        return result;
    }

    Motion orthonormalized() const {
        Vec4!T[4] columns = [m.column(0), m.column(1), m.column(2), m.column(3)];
        columns[3] = columns[3].toPoint().v;
        foreach (axis; 0 .. 3) {
            Vec4!T v = columns[axis] + columns[3] * columns[axis].minkowski(columns[3]);
            foreach (previous; 0 .. axis) {
                v = v - columns[previous] * v.minkowski(columns[previous]);
            }
            columns[axis] = v.toNormal().v;
        }
        Motion result;
        foreach (col; 0 .. 4) {
            result.m.c[col] = columns[col].c;
        }
        return result;
    }

    bool isMirroring() const {
        return m.determinant() < 0;
    }

    Vec4!T opBinary(string op)(Vec4!T v) const if (op == "*") {
        return m * v;
    }

    Point!T opBinary(string op)(Point!T p) const if (op == "*") {
        return Point!T(m * p.v);
    }

    Normal!T opBinary(string op)(Normal!T n) const if (op == "*") {
        return Normal!T(m * n.v);
    }

    Motion opBinary(string op)(Motion rhs) const if (op == "*") {
        return Motion(m * rhs.m);
    }

    Motion!U as(U)() const {
        Motion!U result;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                result.m.c[col][row] = cast(U) m.c[col][row];
            }
        }
        return result;
    }
}

enum double TEST_TOLERANCE = 1e-9;

bool isNear(double a, double b) {
    double difference = a - b;
    return difference < TEST_TOLERANCE && difference > -TEST_TOLERANCE;
}

unittest {
    Motion!double moved = Motion!double.shift([0.3, -1.2, 0.7]);
    Point!double there = moved * Point!double.origin();
    assert(isNear(there.distance(Point!double.origin()), sqrt(0.09 + 1.44 + 0.49)));
    Motion!double back = moved.inverse() * moved;
    foreach (col; 0 .. 4) {
        foreach (row; 0 .. 4) {
            assert(isNear(back.m.c[col][row], col == row ? 1 : 0));
        }
    }
    Point!double start = Motion!double.shift([1, 0, 0.5]) * Point!double.origin();
    Point!double end = Motion!double.shift([-0.4, 2, 0]) * Point!double.origin();
    assert(isNear((Motion!double.carrying(start, end) * start).coshDistance(end), 1));
    Normal!double plane = Vec4!double([1, 0.5, 0, 0.25]).toNormal();
    Motion!double mirror = Motion!double.reflection(plane);
    Point!double mirrored = mirror * start;
    assert(isNear(start.coshDistance(mirror * mirrored), 1));
    assert(isNear(plane.minkowski(start.v), -plane.minkowski(mirrored.v)));
    assert(mirror.isMirroring() && !moved.isMirroring());
    Motion!double drifted = moved;
    drifted.m.c[0][1] += 1e-4;
    drifted.m.c[3][2] -= 1e-4;
    Motion!double repaired = drifted.orthonormalized();
    foreach (col; 0 .. 4) {
        foreach (other; 0 .. 4) {
            double expected = col == other ? (col == 3 ? -1 : 1) : 0;
            assert(isNear(repaired.m.column(col).minkowski(repaired.m.column(other)), expected));
        }
    }
}
