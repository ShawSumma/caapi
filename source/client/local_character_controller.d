module client.local_character_controller;

import std.math : acos, atan2, abs, PI, sqrt, sin, cos, fmin, fmax;
import common.math : MIsometry, Matrix4;
import common.proto : Position;

struct LocalCharacterController {
    Position position;
    float[3] up = [0, 0, 1];
    // Yaw-only frame: kept up-aligned (its local +Y is `up`) by construction.
    // Pitch lives in a separate scalar so it can never bleed into roll, and
    // clamping it at the poles is a plain scalar clamp.
    Quaternion orientation;
    float pitchAngle = 0;

    static LocalCharacterController create() {
        LocalCharacterController c;
        c.position = Position.origin();
        c.orientation = Quaternion.identity();
        c.up = [0, 0, 1];
        return c;
    }

    /// Full view orientation: the up-aligned yaw frame with pitch on top.
    Quaternion viewOrientation() {
        return orientation * Quaternion.fromAxisAngle([1, 0, 0], pitchAngle);
    }

    Position orientedPosition() {
        Position p;
        p.node = position.node;
        p.local = position.local * quaternionToIsometry(viewOrientation());
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
        // Yaw rotates the up-aligned frame about the world up (which is its
        // own +Y), preserving up-alignment exactly. Pitch is scalar state:
        // down always means down, saturating precisely at the poles.
        float[3] relUp = orientation.inverseRotate(up);
        orientation = orientation * Quaternion.fromAxisAngle(relUp, deltaYaw);

        enum float PITCH_LIMIT = PI / 2.0f - 1e-3f;
        pitchAngle += deltaPitch;
        if (pitchAngle > PITCH_LIMIT) {
            pitchAngle = PITCH_LIMIT;
        }
        if (pitchAngle < -PITCH_LIMIT) {
            pitchAngle = -PITCH_LIMIT;
        }
    }

    /// Squares the yaw frame back onto `up`. Yaw and the up-transport both
    /// preserve up-alignment exactly, so what this removes is float noise —
    /// the correction is never large enough to see.
    void alignToGravity() {
        // New local up is rot⁻¹(relUp), so rot must take [0,1,0] to relUp.
        float[3] relUp = orientation.inverseRotate(up);
        Quaternion rot = rotationBetweenVectors([0.0f, 1.0f, 0.0f], relUp);
        orientation = orientation * rot;
    }

    Quaternion horizontalOrientation() {
        // The yaw frame is horizontal by construction.
        return orientation;
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

    /// Rotation taking the local +Z axis to `forward` and +Y toward `up`,
    /// so a level frame (forward = [0,0,1], up = [0,1,0]) maps to identity.
    static Quaternion lookRotation(float[3] forward, float[3] up) {
        float flen = sqrt(forward[0] * forward[0] + forward[1] * forward[1] + forward[2] * forward[2]);
        if (flen < 1e-10) {
            return identity();
        }
        float[3] z = [forward[0] / flen, forward[1] / flen, forward[2] / flen];

        float d = up[0] * z[0] + up[1] * z[1] + up[2] * z[2];
        float[3] y = [up[0] - z[0] * d, up[1] - z[1] * d, up[2] - z[2] * d];
        float ylen = sqrt(y[0] * y[0] + y[1] * y[1] + y[2] * y[2]);
        if (ylen < 1e-10) {
            // up is parallel to forward; pick any perpendicular axis instead.
            float[3] alt = abs(z[0]) < 0.9 ? [1.0f, 0, 0] : [0, 1.0f, 0];
            float ad = alt[0] * z[0] + alt[1] * z[1] + alt[2] * z[2];
            y = [alt[0] - z[0] * ad, alt[1] - z[1] * ad, alt[2] - z[2] * ad];
            ylen = sqrt(y[0] * y[0] + y[1] * y[1] + y[2] * y[2]);
        }
        y[0] /= ylen;
        y[1] /= ylen;
        y[2] /= ylen;

        float[3] x = [
            y[1] * z[2] - y[2] * z[1],
            y[2] * z[0] - y[0] * z[2],
            y[0] * z[1] - y[1] * z[0],
        ];

        // Columns of the rotation matrix are the basis vectors x, y, z;
        // convert to a quaternion via the standard branch-on-trace method.
        float m00 = x[0], m01 = y[0], m02 = z[0];
        float m10 = x[1], m11 = y[1], m12 = z[1];
        float m20 = x[2], m21 = y[2], m22 = z[2];

        float trace = m00 + m11 + m22;
        Quaternion q;
        if (trace > 0) {
            float s = 0.5f / sqrt(trace + 1.0f);
            q = Quaternion(0.25f / s, (m21 - m12) * s, (m02 - m20) * s, (m10 - m01) * s);
        } else if (m00 > m11 && m00 > m22) {
            float s = 2.0f * sqrt(1.0f + m00 - m11 - m22);
            q = Quaternion((m21 - m12) / s, 0.25f * s, (m01 + m10) / s, (m02 + m20) / s);
        } else if (m11 > m22) {
            float s = 2.0f * sqrt(1.0f + m11 - m00 - m22);
            q = Quaternion((m02 - m20) / s, (m01 + m10) / s, 0.25f * s, (m12 + m21) / s);
        } else {
            float s = 2.0f * sqrt(1.0f + m22 - m00 - m11);
            q = Quaternion((m10 - m01) / s, (m02 + m20) / s, (m12 + m21) / s, 0.25f * s);
        }
        return q.normalized();
    }

    Quaternion opBinary(string op : "*")(Quaternion rhs) const {
        return Quaternion(
            w * rhs.w - x * rhs.x - y * rhs.y - z * rhs.z,
            w * rhs.x + x * rhs.w + y * rhs.z - z * rhs.y,
            w * rhs.y - x * rhs.z + y * rhs.w + z * rhs.x,
            w * rhs.z + x * rhs.y - y * rhs.x + z * rhs.w,
        );
    }

    float[3] rotate(float[3] v) const {
        Quaternion conj = Quaternion(w, -x, -y, -z);
        Quaternion vq = Quaternion(0, v[0], v[1], v[2]);
        Quaternion result = this * vq * conj;
        return [result.x, result.y, result.z];
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

unittest {
    import std.math : isClose;

    // Level frame maps to identity.
    Quaternion q = Quaternion.lookRotation([0, 0, 1], [0, 1, 0]);
    assert(isClose(q.w, 1.0f, 1e-5));

    // Rotating local +Z by the result must give the requested forward,
    // and local +Y the requested up, for an arbitrary orthogonal pair.
    float[3] fwd = [1, 0, 0];
    float[3] up = [0, 0, 1];
    q = Quaternion.lookRotation(fwd, up);
    Quaternion conj = Quaternion(q.w, -q.x, -q.y, -q.z);
    Quaternion vz = Quaternion(0, 0, 0, 1);
    Quaternion rz = q * vz * conj;
    assert(isClose(rz.x, fwd[0], 0.0, 1e-5) && isClose(rz.y, fwd[1], 0.0, 1e-5) && isClose(rz.z, fwd[2], 0.0, 1e-5));
    Quaternion vy = Quaternion(0, 0, 1, 0);
    Quaternion ry = q * vy * conj;
    assert(isClose(ry.x, up[0], 0.0, 1e-5) && isClose(ry.y, up[1], 0.0, 1e-5) && isClose(ry.z, up[2], 0.0, 1e-5));

    // Degenerate input falls back to identity instead of NaN.
    q = Quaternion.lookRotation([0, 0, 0], [0, 1, 0]);
    assert(isClose(q.w, 1.0f, 1e-5));
}

unittest {
    // Holonomy regression: translating around a closed loop in hyperbolic
    // space rotates a parallel-transported frame. Re-anchoring `up` from the
    // world each step (getRelativeUp) and re-aligning must keep the view
    // roll-free after the loop instead of accumulating the loop's holonomy.
    import common.character_controller : getRelativeUp;
    import common.graph : Graph, NodeId;
    import common.math : MIsometry;

    Graph graph = Graph.create(12);
    graph.ensureNodeState(NodeId.ROOT);

    LocalCharacterController c = LocalCharacterController.create();
    c.position = Position.origin();
    c.up = getRelativeUp(&graph, &c.position);
    c.alignToGravity();

    // A closed square loop, 0.2 units per side, 10 steps per side, in the
    // horizontal plane of the character's frame.
    static immutable float[3][4] legs = [
        [1, 0, 0], [0, 0, 1], [-1, 0, 0], [0, 0, -1],
    ];
    foreach (leg; legs) {
        foreach (_; 0 .. 10) {
            float[3] step = [leg[0] * 0.02f, leg[1] * 0.02f, leg[2] * 0.02f];
            c.position.local = c.position.local * MIsometry!float.translationAlong(step);
            c.position.local = c.position.local.renormalized();
            float[3] newUp = getRelativeUp(&graph, &c.position);
            c.updatePosition(c.position, newUp, true);
            c.alignToGravity();
            c.renormalizeOrientation();
        }
    }

    // After the loop the local up must sit in the view's Y axis with no roll
    // (x component ~ 0) and no upside-down flip (y component ~ 1).
    float[3] relUp = c.orientation.inverseRotate(c.up);
    assert(relUp[0] > -1e-3 && relUp[0] < 1e-3);
    assert(relUp[1] > 0.999f);
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
