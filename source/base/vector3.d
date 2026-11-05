module base.vector3;

import core.math : sqrt;

struct Vec3(T) {
    T x;
    T y;
    T z;

    ref inout(T) opIndex(size_t axis) inout return {
        if (axis == 0) {
            return x;
        } else if (axis == 1) {
            return y;
        } else {
            assert(axis == 2);
            return z;
        }
    }

    Vec3!U as(U)() const {
        return Vec3!U(cast(U) x, cast(U) y, cast(U) z);
    }
}

immutable Vec3!float ZERO_VECTOR = Vec3!float(0.0f, 0.0f, 0.0f);

float dot(Vec3!float a, Vec3!float b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

float magnitude(Vec3!float v) {
    return sqrt(v.dot(v));
}

Vec3!float scaled(Vec3!float v, float s) {
    return Vec3!float(v.x * s, v.y * s, v.z * s);
}

Vec3!float plus(Vec3!float a, Vec3!float b) {
    return Vec3!float(a.x + b.x, a.y + b.y, a.z + b.z);
}

Vec3!float minus(Vec3!float a, Vec3!float b) {
    return Vec3!float(a.x - b.x, a.y - b.y, a.z - b.z);
}

Vec3!float negated(Vec3!float v) {
    return Vec3!float(-v.x, -v.y, -v.z);
}

Vec3!float cross(Vec3!float a, Vec3!float b) {
    return Vec3!float(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}

Vec3!float rejectAlong(Vec3!float v, Vec3!float unitAxis) {
    return v.minus(unitAxis.scaled(v.dot(unitAxis)));
}

Vec3!float cappedTo(Vec3!float v, float maxMagnitude) {
    float magnitudeSquared = v.dot(v);
    if (magnitudeSquared > maxMagnitude * maxMagnitude) {
        return v.scaled(maxMagnitude / sqrt(magnitudeSquared));
    } else {
        return v;
    }
}

Vec3!float movedToward(Vec3!float current, Vec3!float target, float maxStep) {
    return current.plus(target.minus(current).cappedTo(maxStep));
}

Vec3!float projectedOntoPlane(Vec3!float subject, Vec3!float normal, Vec3!float direction, float distance) {
    return subject.plus(direction.scaled((distance - subject.dot(normal)) / direction.dot(normal)));
}
