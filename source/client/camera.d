module client.camera;

import core.math : cos, sin, sqrt;
import core.stdc.math : expf, fabsf;
import common.character.controller : relativeUp;
import common.graph : Graph, ROOT_NODE;
import common.math : MIsometry, Matrix4, PI, clamped;
import common.position : Position;
import common.worldgen.generation : WorldgenSettings;

enum float EYE_LAG_DECAY_PER_SECOND = 12.0f;
enum float PITCH_LIMIT_RADIANS = PI / 2.0f - 1e-3f;
enum float OPPOSITE_DOT_LIMIT = -0.999999f;
enum float PERPENDICULAR_AXIS_LIMIT = 0.9f;
enum float MIN_QUATERNION_LENGTH = 1e-10f;
enum uint TEST_LEG_STEPS = 10;
enum float TEST_STEP_ABSOLUTE = 0.02f;
enum float TEST_UP_TOLERANCE = 1e-3f;
enum float TEST_UP_MIN = 0.999f;
enum ubyte TEST_DIMENSION = 12;

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
        if (length < MIN_QUATERNION_LENGTH) {
            return identity();
        } else {
            float halfAngle = angle * 0.5f;
            float scale = sin(halfAngle) / length;
            return Quaternion(cos(halfAngle), axis[0] * scale, axis[1] * scale, axis[2] * scale);
        }
    }

    static Quaternion fromVectors(float[3] from, float[3] to) {
        float dot = from[0] * to[0] + from[1] * to[1] + from[2] * to[2];
        if (dot < OPPOSITE_DOT_LIMIT) {
            float[3] perpendicular = perpendicularAxis(from);
            float[3] axis = unitOrZero([from[1] * perpendicular[2] - from[2] * perpendicular[1], from[2] * perpendicular[0] - from[0] * perpendicular[2], from[0] * perpendicular[1] - from[1] * perpendicular[0]]);
            return Quaternion(0, axis[0], axis[1], axis[2]);
        } else {
            float[3] cross = [from[1] * to[2] - from[2] * to[1], from[2] * to[0] - from[0] * to[2], from[0] * to[1] - from[1] * to[0]];
            float w = 1.0f + dot;
            float inverseNorm = 1.0f / sqrt(w * w + cross[0] * cross[0] + cross[1] * cross[1] + cross[2] * cross[2]);
            return Quaternion(w * inverseNorm, cross[0] * inverseNorm, cross[1] * inverseNorm, cross[2] * inverseNorm);
        }
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
        if (length < MIN_QUATERNION_LENGTH) {
            return identity();
        } else {
            float inverseLength = 1.0f / length;
            return Quaternion(w * inverseLength, x * inverseLength, y * inverseLength, z * inverseLength);
        }
    }

    MIsometry!float toIsometry() const {
        Matrix4!float m;
        m.data[0][0] = 1 - 2 * (y * y + z * z);
        m.data[0][1] = 2 * (x * y + w * z);
        m.data[0][2] = 2 * (x * z - w * y);
        m.data[1][0] = 2 * (x * y - w * z);
        m.data[1][1] = 1 - 2 * (x * x + z * z);
        m.data[1][2] = 2 * (y * z + w * x);
        m.data[2][0] = 2 * (x * z + w * y);
        m.data[2][1] = 2 * (y * z - w * x);
        m.data[2][2] = 1 - 2 * (x * x + y * y);
        m.data[3][3] = 1;
        return MIsometry!float(m);
    }
}

float[3] perpendicularAxis(float[3] from) {
    if (fabsf(from[0]) < PERPENDICULAR_AXIS_LIMIT) {
        float[3] xAxis = [1.0f, 0.0f, 0.0f];
        return xAxis;
    } else {
        float[3] yAxis = [0.0f, 1.0f, 0.0f];
        return yAxis;
    }
}

float[3] unitOrZero(float[3] axis) {
    float length = sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]);
    if (length > 0) {
        float[3] unit = [axis[0] / length, axis[1] / length, axis[2] / length];
        return unit;
    } else {
        return axis;
    }
}

struct Camera {
    Position position;
    Quaternion orientation;
    float[3] up = [0, 0, 1];
    float pitchAngle = 0;
    float eyeOffset = 0;
    float eyeLag = 0;

    static Camera make(float eyeOffset) {
        return Camera(Position.origin(), Quaternion.identity(), [0, 0, 1], 0, eyeOffset, 0);
    }

    void smoothEyeVertical(float groundedRise, float limit, float dt) {
        eyeLag = clamped((eyeLag + groundedRise) * expf(-EYE_LAG_DECAY_PER_SECOND * dt), -limit, limit);
    }

    Quaternion viewOrientation() const {
        return orientation * Quaternion.fromAxisAngle([1, 0, 0], pitchAngle);
    }

    MIsometry!float eyeLocal() const {
        float height = eyeOffset - eyeLag;
        if (height == 0) {
            return position.local;
        } else {
            return position.local * MIsometry!float.fromDisplacement([up[0] * height, up[1] * height, up[2] * height]);
        }
    }

    Position orientedPosition() const {
        return Position(position.node, eyeLocal() * viewOrientation().toIsometry());
    }

    void updatePosition(Position newPosition, float[3] newUp) {
        orientation = Quaternion.fromVectors(up, newUp) * orientation;
        position = newPosition;
        up = newUp;
    }

    void lookLevel(float deltaYaw, float deltaPitch) {
        orientation = orientation * Quaternion.fromAxisAngle(orientation.inverseRotate(up), deltaYaw);
        pitchAngle = clamped(pitchAngle + deltaPitch, -PITCH_LIMIT_RADIANS, PITCH_LIMIT_RADIANS);
    }

    void alignToGravity() {
        orientation = (orientation * Quaternion.fromVectors([0.0f, 1.0f, 0.0f], orientation.inverseRotate(up))).normalized();
    }
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, WorldgenSettings.init);
    graph.ensureNodeState(ROOT_NODE);
    Camera camera = Camera.make(0);
    camera.up = graph.relativeUp(camera.position);
    camera.alignToGravity();
    float[3][4] legs = [
        [1, 0, 0],
        [0, 0, 1],
        [-1, 0, 0],
        [0, 0, -1],
    ];
    foreach (leg; legs) {
        foreach (_; 0 .. TEST_LEG_STEPS) {
            Position moved = Position(camera.position.node, (camera.position.local * MIsometry!float.fromDisplacement([leg[0] * TEST_STEP_ABSOLUTE, leg[1] * TEST_STEP_ABSOLUTE, leg[2] * TEST_STEP_ABSOLUTE])).renormalized());
            camera.updatePosition(moved, graph.relativeUp(moved));
            camera.alignToGravity();
        }
    }
    float[3] relativeUpInBody = camera.orientation.inverseRotate(camera.up);
    assert(fabsf(relativeUpInBody[0]) < TEST_UP_TOLERANCE);
    assert(relativeUpInBody[1] > TEST_UP_MIN);
    graph.release();
}
