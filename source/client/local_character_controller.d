module client.local_character_controller;

import std.math : atan2, abs, PI, sqrt, sin, cos, fmin, fmax;
import common.math : MIsometry, Matrix4;
import common.proto : Position;

struct LocalCharacterController {
    Position position;
    float[3] up = [0, 0, 1];
    Quaternion orientation;

    static LocalCharacterController create() {
        LocalCharacterController c;
        c.position = Position.origin();
        c.orientation = Quaternion.identity();
        c.up = [0, 0, 1];
        return c;
    }

    Position orientedPosition() {
        Position p;
        p.node = position.node;
        p.local = position.local * quaternionToIsometry(orientation);
        return p;
    }

    void updatePosition(Position pos, float[3] newUp, bool preserveUpAlignment) {
        if (preserveUpAlignment) {
            Quaternion rot = rotationBetweenVectors(up, newUp);
            orientation = rot * orientation;
        }
        position = pos;
        up = newUp;
    }

    void lookFree(float deltaYaw, float deltaPitch, float deltaRoll) {
        orientation = orientation
            * Quaternion.fromAxisAngle([0, 1, 0], deltaYaw)
            * Quaternion.fromAxisAngle([1, 0, 0], deltaPitch)
            * Quaternion.fromAxisAngle([0, 0, 1], deltaRoll);
    }

    void lookLevel(float deltaYaw, float deltaPitch) {
        float[3] relUp = orientation.inverseRotate(up);

        orientation = orientation * Quaternion.fromAxisAngle(relUp, deltaYaw);

        if (abs(relUp[0]) < 0.9) {
            float currentPitch = -atan2(relUp[2], relUp[1]);
            float targetPitch = currentPitch + deltaPitch;
            if (deltaPitch > 0.0) {
                targetPitch = fmax(currentPitch, fmin(targetPitch, PI / 2.0));
            }
            else {
                targetPitch = fmin(currentPitch, fmax(targetPitch, -PI / 2.0));
            }
            orientation = orientation * Quaternion.fromAxisAngle([1, 0, 0], targetPitch - currentPitch);
        }
    }

    void alignToGravity() {
        float[3] relUp = orientation.inverseRotate(up);

        if (abs(relUp[2]) < 0.9) {
            float deltaRoll = -atan2(relUp[0], relUp[1]);
            orientation = orientation * Quaternion.fromAxisAngle([0, 0, 1], deltaRoll);
        }
        else if (relUp[1] > 0.0) {
            float deltaYaw = atan2(relUp[0], relUp[2]);
            orientation = orientation * Quaternion.fromAxisAngle([0, 1, 0], deltaYaw);
        }
        else {
            float[3] target = [0, 0, relUp[2] > 0 ? 1.0f : -1.0f];
            Quaternion rot = rotationBetweenVectors(target, relUp);
            orientation = orientation * rot;
        }
    }

    Quaternion horizontalOrientation() {
        float[3] relUp = orientation.inverseRotate(up);

        float[3] forward;
        if (abs(relUp[0]) < 0.9) {
            forward = [0.0f, -relUp[2], relUp[1]];
        }
        else {
            forward = [0.0f, 0.0f, 1.0f];
            float dot = forward[0] * relUp[0] + forward[1] * relUp[1] + forward[2] * relUp[2];
            forward[0] -= relUp[0] * dot;
            forward[1] -= relUp[1] * dot;
            forward[2] -= relUp[2] * dot;
        }

        return orientation * Quaternion.lookRotation(forward, relUp);
    }

    void renormalizeOrientation() {
        orientation = orientation.normalized();
    }
}

Quaternion rotationBetweenVectors(float[3] from, float[3] to) {

    float[3] cross = [
        from[1] * to[2] - from[2] * to[1],
        from[2] * to[0] - from[0] * to[2],
        from[0] * to[1] - from[1] * to[0],
    ];
    float dot = from[0] * to[0] + from[1] * to[1] + from[2] * to[2];

    if (dot < -0.999999) {
        float[3] perp = abs(from[0]) < 0.9 ? [1, 0, 0] : [0, 1, 0];
        float[3] axis = [
            from[1] * perp[2] - from[2] * perp[1],
            from[2] * perp[0] - from[0] * perp[2],
            from[0] * perp[1] - from[1] * perp[0],
        ];
        float len = sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]);
        if (len > 0) {
            axis[0] /= len;
            axis[1] /= len;
            axis[2] /= len;
        }
        return Quaternion(0, axis[0], axis[1], axis[2]);
    }

    float w = 1.0f + dot;
    float invNorm = 1.0f / sqrt(w * w + cross[0] * cross[0] + cross[1] * cross[1] + cross[2] * cross[2]);
    return Quaternion(w * invNorm, cross[0] * invNorm, cross[1] * invNorm, cross[2] * invNorm);
}

struct Quaternion {
    float w = 1;
    float x = 0;
    float y = 0;
    float z = 0;

    static Quaternion identity() {
        return Quaternion(1, 0, 0, 0);
    }

    static Quaternion fromAxisAngle(float[3] axis, float angle) {
        float halfAngle = angle * 0.5f;
        float s = sin(halfAngle);
        float len = sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]);
        if (len < 1e-10) {
            return identity();
        }
        float invLen = s / len;
        return Quaternion(cos(halfAngle), axis[0] * invLen, axis[1] * invLen, axis[2] * invLen);
    }

    static Quaternion lookRotation(float[3] forward, float[3] up) {
        return identity();
    }

    Quaternion opBinary(string op : "*")(Quaternion rhs) const {
        return Quaternion(
            w * rhs.w - x * rhs.x - y * rhs.y - z * rhs.z,
            w * rhs.x + x * rhs.w + y * rhs.z - z * rhs.y,
            w * rhs.y - x * rhs.z + y * rhs.w + z * rhs.x,
            w * rhs.z + x * rhs.y - y * rhs.x + z * rhs.w,
        );
    }

    float[3] inverseRotate(float[3] v) const {
        Quaternion conj = Quaternion(w, -x, -y, -z);
        Quaternion vq = Quaternion(0, v[0], v[1], v[2]);
        Quaternion result = conj * vq * this;
        return [result.x, result.y, result.z];
    }

    Quaternion normalized() const {
        float len = sqrt(w * w + x * x + y * y + z * z);
        if (len < 1e-10) {
            return identity();
        }
        float inv = 1.0f / len;
        return Quaternion(w * inv, x * inv, y * inv, z * inv);
    }
}

MIsometry!float quaternionToIsometry(Quaternion q) {
    float xx = q.x * q.x;
    float yy = q.y * q.y;
    float zz = q.z * q.z;
    float xy = q.x * q.y;
    float xz = q.x * q.z;
    float yz = q.y * q.z;
    float wx = q.w * q.x;
    float wy = q.w * q.y;
    float wz = q.w * q.z;

    Matrix4!float m;
    m.data[0][0] = 1 - 2 * (yy + zz);
    m.data[0][1] = 2 * (xy + wz);
    m.data[0][2] = 2 * (xz - wy);
    m.data[1][0] = 2 * (xy - wz);
    m.data[1][1] = 1 - 2 * (xx + zz);
    m.data[1][2] = 2 * (yz + wx);
    m.data[2][0] = 2 * (xz + wy);
    m.data[2][1] = 2 * (yz - wx);
    m.data[2][2] = 1 - 2 * (xx + yy);
    m.data[3][3] = 1;
    return MIsometry!float(m);
}
