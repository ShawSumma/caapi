module client.camera;

import core.math : cos, sin, sqrt;
import core.stdc.math : asinf, fabsf;
import base.numbers : PI, clamped;
import base.units : Angle, Length;
import base.vector3 : Vec3, cross, dot;
import common.position : Position;
import geometry.lorentz : Mat4, Motion;

enum Angle PITCH_LIMIT = Angle(PI / 2.0f - 1e-3f);
enum float OPPOSITE_DOT_LIMIT = -0.999999f;
enum float PERPENDICULAR_AXIS_LIMIT = 0.9f;
enum float MIN_QUATERNION_LENGTH = 1e-10f;

immutable Vec3!float CAMERA_FORWARD = Vec3!float(0, 0, -1);

struct Quaternion {
    float w = 1;
    float x = 0;
    float y = 0;
    float z = 0;

    static Quaternion identity() {
        return Quaternion(1, 0, 0, 0);
    }

    static Quaternion fromAxisAngle(Vec3!float axis, float angle) {
        float length = sqrt(axis.dot(axis));
        if (length < MIN_QUATERNION_LENGTH) {
            return identity();
        } else {
            float halfAngle = angle * 0.5f;
            float scale = sin(halfAngle) / length;
            return Quaternion(cos(halfAngle), axis.x * scale, axis.y * scale, axis.z * scale);
        }
    }

    static Quaternion fromVectors(Vec3!float from, Vec3!float to) {
        float along = from.dot(to);
        if (along < OPPOSITE_DOT_LIMIT) {
            Vec3!float axis = unitOrZero(from.cross(perpendicularAxis(from)));
            return Quaternion(0, axis.x, axis.y, axis.z);
        } else {
            Vec3!float across = from.cross(to);
            float w = 1.0f + along;
            float inverseNorm = 1.0f / sqrt(w * w + across.dot(across));
            return Quaternion(w * inverseNorm, across.x * inverseNorm, across.y * inverseNorm, across.z * inverseNorm);
        }
    }

    Quaternion opBinary(string op)(Quaternion rhs) const if (op == "*") {
        return Quaternion(w * rhs.w - x * rhs.x - y * rhs.y - z * rhs.z, w * rhs.x + x * rhs.w + y * rhs.z - z * rhs.y, w * rhs.y - x * rhs.z + y * rhs.w + z * rhs.x, w * rhs.z + x * rhs.y - y * rhs.x + z * rhs.w);
    }

    Vec3!float rotate(Vec3!float v) const {
        Quaternion rotated = this * Quaternion(0, v.x, v.y, v.z) * Quaternion(w, -x, -y, -z);
        return Vec3!float(rotated.x, rotated.y, rotated.z);
    }

    Quaternion normalized() const {
        float length = sqrt(w * w + x * x + y * y + z * z);
        if (length < MIN_QUATERNION_LENGTH) {
            return identity();
        } else {
            float inverseLength = 1.0f / length;
            return Quaternion(w * inverseLength, x * inverseLength, y * inverseLength, z * inverseLength);
        }
    }

    Quaternion inverted() const {
        return Quaternion(w, -x, -y, -z);
    }

    Motion!float toMotion() const {
        Mat4!float m;
        m.c[0][0] = 1 - 2 * (y * y + z * z);
        m.c[0][1] = 2 * (x * y + w * z);
        m.c[0][2] = 2 * (x * z - w * y);
        m.c[1][0] = 2 * (x * y - w * z);
        m.c[1][1] = 1 - 2 * (x * x + z * z);
        m.c[1][2] = 2 * (y * z + w * x);
        m.c[2][0] = 2 * (x * z + w * y);
        m.c[2][1] = 2 * (y * z - w * x);
        m.c[2][2] = 1 - 2 * (x * x + y * y);
        m.c[3][3] = 1;
        return Motion!float(m);
    }
}

Vec3!float perpendicularAxis(Vec3!float from) {
    if (fabsf(from.x) < PERPENDICULAR_AXIS_LIMIT) {
        return Vec3!float(1.0f, 0.0f, 0.0f);
    } else {
        return Vec3!float(0.0f, 1.0f, 0.0f);
    }
}

Vec3!float unitOrZero(Vec3!float axis) {
    float length = sqrt(axis.dot(axis));
    if (length > 0) {
        return Vec3!float(axis.x / length, axis.y / length, axis.z / length);
    } else {
        return axis;
    }
}

struct Camera {
    Position position;
    Motion!float eye;
    Quaternion heading;
    Vec3!float viewUp = Vec3!float(0, 1, 0);
    Length eyeOffset;
    Angle pitch;

    static Camera make(Length eyeOffset) {
        return Camera(Position.origin(), Motion!float.identity(), Quaternion.identity(), Vec3!float(0, 1, 0), eyeOffset, Angle(0));
    }

    Quaternion orientation() const {
        return heading * Quaternion.fromAxisAngle(Vec3!float(1, 0, 0), pitch.value);
    }

    Position orientedPosition() const {
        return Position(position.node, position.local * eye * orientation.toMotion());
    }

    Vec3!float forward() const {
        return orientation.rotate(CAMERA_FORWARD);
    }

    Angle elevation() const {
        return Angle(asinf(clamped(forward().dot(viewUp), -1.0f, 1.0f)));
    }

    void follow(Position bodyPosition, Motion!float eyeFromBody, Vec3!float visibleUp) {
        position = bodyPosition;
        eye = eyeFromBody;
        heading = (Quaternion.fromVectors(heading.rotate(Vec3!float(0, 1, 0)), visibleUp) * heading).normalized();
        viewUp = visibleUp;
    }

    void turn(Angle deltaYaw, Angle deltaPitch) {
        heading = (Quaternion.fromAxisAngle(viewUp, deltaYaw.value) * heading).normalized();
        pitch = Angle(clamped((pitch + deltaPitch).value, -PITCH_LIMIT.value, PITCH_LIMIT.value));
    }
}
