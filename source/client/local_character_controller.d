module client.local_character_controller;

import core.math : cos, sin, sqrt;
import core.stdc.math : expf, fabsf;
import common.character_controller.controller : getRelativeUp;
import common.graph : Graph, ROOT_NODE, createGraph;
import common.math : MIsometry, Matrix4, PI;
import common.proto : Position, originPosition;

enum float EYE_LAG_DECAY_PER_SECOND = 12.0f;
enum float PITCH_LIMIT_RADIANS = PI / 2.0f - 1e-3f;
enum float OPPOSITE_DOT_LIMIT = -0.999999f;
enum float PERPENDICULAR_AXIS_LIMIT = 0.9f;
enum float MIN_QUATERNION_LENGTH = 1e-10f;
enum uint TEST_LEG_STEPS = 10;
enum float TEST_STEP_ABSOLUTE = 0.02f;
enum float TEST_UP_TOLERANCE = 1e-3f;
enum float TEST_UP_MIN = 0.999f;

struct Quaternion {
    float w = 1;
    float x = 0;
    float y = 0;
    float z = 0;

    static Quaternion identity() {
        return Quaternion(1, 0, 0, 0);
    }

    static Quaternion fromAxisAngle(float[3] axis, float angle) {
        float length = sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]);
        Quaternion result = identity();
        if (!(length < MIN_QUATERNION_LENGTH)) {
            float halfAngle = angle * 0.5f;
            float scale = sin(halfAngle) / length;
            result = Quaternion(cos(halfAngle), axis[0] * scale, axis[1] * scale, axis[2] * scale);
        }
        return result;
    }

    Quaternion opBinary(string op)(Quaternion rhs) const if (op == "*") {
        return Quaternion(w * rhs.w - x * rhs.x - y * rhs.y - z * rhs.z, w * rhs.x + x * rhs.w + y * rhs.z - z * rhs.y, w * rhs.y - x * rhs.z + y * rhs.w + z * rhs.x, w * rhs.z + x * rhs.y - y * rhs.x + z * rhs.w);
    }

    float[3] rotate(float[3] v) const {
        Quaternion rotated = this * Quaternion(0, v[0], v[1], v[2]) * Quaternion(w, -x, -y, -z);
        float[3] result = [rotated.x, rotated.y, rotated.z];
        return result;
    }

    float[3] inverseRotate(float[3] v) const {
        Quaternion rotated = Quaternion(w, -x, -y, -z) * Quaternion(0, v[0], v[1], v[2]) * this;
        float[3] result = [rotated.x, rotated.y, rotated.z];
        return result;
    }

    Quaternion normalized() const {
        float length = sqrt(w * w + x * x + y * y + z * z);
        Quaternion result = identity();
        if (!(length < MIN_QUATERNION_LENGTH)) {
            float inverseLength = 1.0f / length;
            result = Quaternion(w * inverseLength, x * inverseLength, y * inverseLength, z * inverseLength);
        }
        return result;
    }
}

struct LocalCharacterController {
    Position position;
    Quaternion orientation;
    float[3] up = [0, 0, 1];
    float pitchAngle = 0;
    float eyeOffset = 0;
    float eyeLag = 0;

    void smoothEyeVertical(float groundedRise, float limit, float dt) {
        eyeLag = (eyeLag + groundedRise) * expf(-EYE_LAG_DECAY_PER_SECOND * dt);
        if (eyeLag > limit) {
            eyeLag = limit;
        } else if (eyeLag < -limit) {
            eyeLag = -limit;
        }
    }

    Quaternion viewOrientation() const {
        return orientation * Quaternion.fromAxisAngle([1, 0, 0], pitchAngle);
    }

    Position orientedPosition() const {
        Position result = position;
        float height = eyeOffset - eyeLag;
        if (height != 0) {
            result.local = result.local * MIsometry!float.translationAlong([up[0] * height, up[1] * height, up[2] * height]);
        }
        result.local = result.local * quaternionToIsometry(viewOrientation());
        return result;
    }

    void updatePosition(Position newPosition, float[3] newUp) {
        orientation = rotationBetweenVectors(up, newUp) * orientation;
        position = newPosition;
        up = newUp;
    }

    void lookLevel(float deltaYaw, float deltaPitch) {
        orientation = orientation * Quaternion.fromAxisAngle(orientation.inverseRotate(up), deltaYaw);
        pitchAngle += deltaPitch;
        if (pitchAngle > PITCH_LIMIT_RADIANS) {
            pitchAngle = PITCH_LIMIT_RADIANS;
        } else if (pitchAngle < -PITCH_LIMIT_RADIANS) {
            pitchAngle = -PITCH_LIMIT_RADIANS;
        }
    }

    void alignToGravity() {
        orientation = (orientation * rotationBetweenVectors([0.0f, 1.0f, 0.0f], orientation.inverseRotate(up))).normalized();
    }
}

LocalCharacterController createLocalCharacterController() {
    LocalCharacterController controller;
    controller.position = originPosition();
    controller.orientation = Quaternion.identity();
    return controller;
}

Quaternion rotationBetweenVectors(float[3] from, float[3] to) {
    float dot = from[0] * to[0] + from[1] * to[1] + from[2] * to[2];
    Quaternion result;
    if (dot < OPPOSITE_DOT_LIMIT) {
        float[3] perpendicular = [0.0f, 1.0f, 0.0f];
        if (fabsf(from[0]) < PERPENDICULAR_AXIS_LIMIT) {
            perpendicular = [1.0f, 0.0f, 0.0f];
        }
        float[3] axis = [from[1] * perpendicular[2] - from[2] * perpendicular[1], from[2] * perpendicular[0] - from[0] * perpendicular[2], from[0] * perpendicular[1] - from[1] * perpendicular[0]];
        float length = sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]);
        if (length > 0) {
            axis = [axis[0] / length, axis[1] / length, axis[2] / length];
        }
        result = Quaternion(0, axis[0], axis[1], axis[2]);
    } else {
        float[3] cross = [from[1] * to[2] - from[2] * to[1], from[2] * to[0] - from[0] * to[2], from[0] * to[1] - from[1] * to[0]];
        float w = 1.0f + dot;
        float inverseNorm = 1.0f / sqrt(w * w + cross[0] * cross[0] + cross[1] * cross[1] + cross[2] * cross[2]);
        result = Quaternion(w * inverseNorm, cross[0] * inverseNorm, cross[1] * inverseNorm, cross[2] * inverseNorm);
    }
    return result;
}

MIsometry!float quaternionToIsometry(Quaternion q) {
    Matrix4!float m;
    m.data[0][0] = 1 - 2 * (q.y * q.y + q.z * q.z);
    m.data[0][1] = 2 * (q.x * q.y + q.w * q.z);
    m.data[0][2] = 2 * (q.x * q.z - q.w * q.y);
    m.data[1][0] = 2 * (q.x * q.y - q.w * q.z);
    m.data[1][1] = 1 - 2 * (q.x * q.x + q.z * q.z);
    m.data[1][2] = 2 * (q.y * q.z + q.w * q.x);
    m.data[2][0] = 2 * (q.x * q.z + q.w * q.y);
    m.data[2][1] = 2 * (q.y * q.z - q.w * q.x);
    m.data[2][2] = 1 - 2 * (q.x * q.x + q.y * q.y);
    m.data[3][3] = 1;
    return MIsometry!float(m);
}

unittest {
    Graph graph = createGraph(12);
    graph.ensureNodeState(ROOT_NODE);
    LocalCharacterController controller = createLocalCharacterController();
    controller.up = getRelativeUp(&graph, controller.position);
    controller.alignToGravity();
    immutable float[3][4] legs = [
        [1, 0, 0],
        [0, 0, 1],
        [-1, 0, 0],
        [0, 0, -1],
    ];
    foreach (leg; legs) {
        foreach (i; 0 .. TEST_LEG_STEPS) {
            Position moved = controller.position;
            moved.local = (moved.local * MIsometry!float.translationAlong([leg[0] * TEST_STEP_ABSOLUTE, leg[1] * TEST_STEP_ABSOLUTE, leg[2] * TEST_STEP_ABSOLUTE])).renormalized();
            controller.updatePosition(moved, getRelativeUp(&graph, moved));
            controller.alignToGravity();
        }
    }
    float[3] relativeUp = controller.orientation.inverseRotate(controller.up);
    assert(fabsf(relativeUp[0]) < TEST_UP_TOLERANCE);
    assert(relativeUp[1] > TEST_UP_MIN);
    graph.release();
}
