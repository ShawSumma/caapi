module client.camera;

import core.math : cos, sin, sqrt;
import core.stdc.math : asinf, atan2f, fabsf;
import common.math : MIsometry, Matrix4, PI, clamped;
import common.position : Position;
import common.units : Angle, Length;

enum Angle PITCH_LIMIT = Angle(PI / 2.0f - 1e-3f);
enum float OPPOSITE_DOT_LIMIT = -0.999999f;
enum float PERPENDICULAR_AXIS_LIMIT = 0.9f;
enum float MIN_QUATERNION_LENGTH = 1e-10f;
enum Angle TEST_ANGLE_TOLERANCE = Angle(1e-3f);

immutable float[3] CAMERA_FORWARD = [0, 0, -1];

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
    MIsometry!float eye;
    Quaternion orientation;
    float[3] viewUp = [0, 1, 0];
    Length eyeOffset;
    Angle pitch;

    static Camera make(Length eyeOffset) {
        return Camera(Position.origin(), MIsometry!float.identity(), Quaternion.identity(), [0, 1, 0], eyeOffset, Angle(0));
    }

    Position orientedPosition() const {
        return Position(position.node, position.local * eye * orientation.toIsometry());
    }

    float[3] forward() const {
        return orientation.rotate(CAMERA_FORWARD);
    }

    Angle elevation() const {
        float[3] ahead = forward();
        return Angle(asinf(clamped(ahead[0] * viewUp[0] + ahead[1] * viewUp[1] + ahead[2] * viewUp[2], -1.0f, 1.0f)));
    }

    void follow(Position bodyPosition, MIsometry!float eyeFromBody, float[3] visibleUp) {
        position = bodyPosition;
        eye = eyeFromBody;
        viewUp = visibleUp;
    }

    void turn(Angle deltaYaw, Angle deltaPitch) {
        orientation = (Quaternion.fromAxisAngle(viewUp, deltaYaw.value) * orientation).normalized();
        pitch = Angle(clamped((pitch + deltaPitch).value, -PITCH_LIMIT.value, PITCH_LIMIT.value));
        holdPitch();
    }

    void holdPitch() {
        orientation = (orientation * Quaternion.fromAxisAngle([1, 0, 0], (pitch - elevation()).value)).normalized();
    }

    void level() {
        orientation = (orientation * Quaternion.fromVectors([0.0f, 1.0f, 0.0f], orientation.inverseRotate(viewUp))).normalized();
        pitch = Angle(0);
    }

    Angle roll() const {
        float[3] ahead = forward();
        float[3] cameraUp = orientation.rotate([0, 1, 0]);
        float along = viewUp[0] * ahead[0] + viewUp[1] * ahead[1] + viewUp[2] * ahead[2];
        float[3] level = [viewUp[0] - along * ahead[0], viewUp[1] - along * ahead[1], viewUp[2] - along * ahead[2]];
        float[3] turned = [cameraUp[1] * level[2] - cameraUp[2] * level[1], cameraUp[2] * level[0] - cameraUp[0] * level[2], cameraUp[0] * level[1] - cameraUp[1] * level[0]];
        float sine = turned[0] * ahead[0] + turned[1] * ahead[1] + turned[2] * ahead[2];
        float cosine = cameraUp[0] * level[0] + cameraUp[1] * level[1] + cameraUp[2] * level[2];
        return Angle(atan2f(sine, cosine));
    }

    void levelRoll() {
        orientation = (Quaternion.fromAxisAngle(forward(), roll().value) * orientation).normalized();
    }
}

unittest {
    Camera camera = Camera.make(Length(0));
    camera.turn(Angle(0), Angle(PI));
    assert(camera.elevation() <= PITCH_LIMIT + TEST_ANGLE_TOLERANCE);
    camera.turn(Angle(0), Angle(-2 * PI));
    assert(camera.elevation() >= -PITCH_LIMIT - TEST_ANGLE_TOLERANCE);
    Angle before = camera.elevation();
    camera.turn(Angle(PI / 2), Angle(0));
    assert(fabsf((camera.elevation() - before).value) < TEST_ANGLE_TOLERANCE.value);
}

unittest {
    Camera camera = Camera.make(Length(0));
    float[3] before = camera.forward();
    camera.follow(camera.position, MIsometry!float.identity(), [1, 0, 0]);
    float[3] after = camera.forward();
    assert(before[0] == after[0] && before[1] == after[1] && before[2] == after[2]);
}

unittest {
    Camera camera = Camera.make(Length(0));
    camera.follow(camera.position, MIsometry!float.identity(), [0.6f, 0.8f, 0]);
    float[3] before = camera.forward();
    camera.levelRoll();
    float[3] after = camera.forward();
    assert(fabsf(camera.roll().value) < TEST_ANGLE_TOLERANCE.value);
    assert(fabsf(before[0] - after[0]) + fabsf(before[1] - after[1]) + fabsf(before[2] - after[2]) < TEST_ANGLE_TOLERANCE.value);
}
