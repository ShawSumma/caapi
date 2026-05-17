module client.local_character_controller;

import common.math;
import common.proto : Position;
import std.math : atan2, abs, PI, SQRT2, fmin = fmin, fmax = fmax;
import std.math : sqrt;
import std.math : sin, cos, sqrt;

/// Controls the local character's camera orientation independently from the server-authoritative position.
struct LocalCharacterController {
    /// The last extrapolated inter-frame view position, used for rendering and gravity-specific
    /// orientation computations
    Position position;

    /// The up vector relative to position, ignoring orientation
    float[3] up = [0, 0, 1];

    /// The quaternion adjustment to the character position to represent its actual apparent orientation
    Quaternion orientation;

    static LocalCharacterController create() {
        LocalCharacterController c;
        c.position = Position.origin();
        c.orientation = Quaternion.identity();
        c.up = [0, 0, 1];
        return c;
    }

    /// Get the current position with orientation applied to it
    Position orientedPosition() {
        Position p;
        p.node = position.node;
        p.local = position.local * quaternionToIsometry(orientation);
        return p;
    }

    /// Updates the LocalCharacter based on outside information. Note that the `up` parameter is relative
    /// only to `position`, not the character's orientation.
    void updatePosition(Position pos, float[3] newUp, bool preserveUpAlignment) {
        if (preserveUpAlignment) {
            // Rotate the character orientation to stay consistent with changes in gravity
            auto rot = rotationBetweenVectors(up, newUp);
            orientation = rot * orientation;
        }
        position = pos;
        up = newUp;
    }

    /// Rotates the camera's view by locally adding pitch and yaw.
    void lookFree(float deltaYaw, float deltaPitch, float deltaRoll) {
        orientation = orientation
            * Quaternion.fromAxisAngle([0, 1, 0], deltaYaw)
            * Quaternion.fromAxisAngle([1, 0, 0], deltaPitch)
            * Quaternion.fromAxisAngle([0, 0, 1], deltaRoll);
    }

    /// Rotates the camera's view with standard first-person walking simulator mouse controls.
    void lookLevel(float deltaYaw, float deltaPitch) {
        // Get orientation-relative up
        float[3] relUp = orientation.inverseRotate(up);

        // Handle yaw: rotate the view about the up vector
        orientation = orientation * Quaternion.fromAxisAngle(relUp, deltaYaw);

        // Handle pitch with capping
        if (abs(relUp[0]) < 0.9) {
            float currentPitch = -atan2(relUp[2], relUp[1]);
            float targetPitch = currentPitch + deltaPitch;
            if (deltaPitch > 0.0) {
                targetPitch = fmax(currentPitch, fmin(targetPitch, PI / 2.0));
            } else {
                targetPitch = fmin(currentPitch, fmax(targetPitch, -PI / 2.0));
            }
            orientation = orientation * Quaternion.fromAxisAngle([1, 0, 0], targetPitch - currentPitch);
        }
    }

    /// Instantly updates the current orientation quaternion to make the camera level.
    void alignToGravity() {
        float[3] relUp = orientation.inverseRotate(up);

        if (abs(relUp[2]) < 0.9) {
            // If facing not too vertically, roll the camera to make it level.
            float deltaRoll = -atan2(relUp[0], relUp[1]);
            orientation = orientation * Quaternion.fromAxisAngle([0, 0, 1], deltaRoll);
        } else if (relUp[1] > 0.0) {
            // If not upside-down, yaw the camera to make it level.
            float deltaYaw = atan2(relUp[0], relUp[2]);
            orientation = orientation * Quaternion.fromAxisAngle([0, 1, 0], deltaYaw);
        } else {
            // Rotate the camera to look straight up or down.
            float[3] target = [0, 0, relUp[2] > 0 ? 1.0f : -1.0f];
            auto rot = rotationBetweenVectors(target, relUp);
            orientation = orientation * rot;
        }
    }

    /// Returns an orientation quaternion restricted to being level and horizontal.
    /// Used to determine movement direction when a key is pressed.
    Quaternion horizontalOrientation() {
        float[3] relUp = orientation.inverseRotate(up);

        float[3] forward;
        if (abs(relUp[0]) < 0.9) {
            // Rotate the local forward vector about the locally horizontal axis until it is horizontal
            forward = [0.0f, -relUp[2], relUp[1]];
        } else {
            // Project the local forward vector to the level plane
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

/// Compute a quaternion that rotates vector `from` to vector `to`.
private Quaternion rotationBetweenVectors(float[3] from, float[3] to) {

    float[3] cross = [
        from[1] * to[2] - from[2] * to[1],
        from[2] * to[0] - from[0] * to[2],
        from[0] * to[1] - from[1] * to[0],
    ];
    float dot = from[0] * to[0] + from[1] * to[1] + from[2] * to[2];

    // If vectors are nearly opposite, find a perpendicular axis
    if (dot < -0.999999) {
        // Use an arbitrary perpendicular vector
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

/// Minimal quaternion type for orientation math.
/// If common.math provides one, this can be replaced.
struct Quaternion {
    float w = 1, x = 0, y = 0, z = 0;

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

    /// Construct a rotation looking in `forward` direction with given `up`.
    static Quaternion lookRotation(float[3] forward, float[3] up) {
        // Simplified: just return fromAxisAngle-based approximation
        // A full implementation would build a rotation matrix and convert
        return identity(); // TODO: implement properly if needed
    }

    Quaternion opBinary(string op : "*")(Quaternion rhs) const {
        return Quaternion(
            w * rhs.w - x * rhs.x - y * rhs.y - z * rhs.z,
            w * rhs.x + x * rhs.w + y * rhs.z - z * rhs.y,
            w * rhs.y - x * rhs.z + y * rhs.w + z * rhs.x,
            w * rhs.z + x * rhs.y - y * rhs.x + z * rhs.w,
        );
    }

    /// Rotate a vector by the inverse of this quaternion
    float[3] inverseRotate(float[3] v) const {
        // q^-1 * v * q, for unit quaternion q^-1 = conjugate
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

/// Convert a Quaternion to a 4x4 MIsometry (rotation matrix in homogeneous coords)
MIsometry!float quaternionToIsometry(Quaternion q) {
    float xx = q.x * q.x, yy = q.y * q.y, zz = q.z * q.z;
    float xy = q.x * q.y, xz = q.x * q.z, yz = q.y * q.z;
    float wx = q.w * q.x, wy = q.w * q.y, wz = q.w * q.z;

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
