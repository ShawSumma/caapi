module common.vector3;

import core.math : sqrt;

immutable float[3] ZERO_VECTOR = [0.0f, 0.0f, 0.0f];

float dot(float[3] a, float[3] b) {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

float magnitude(float[3] v) {
    return sqrt(v.dot(v));
}

float[3] scaled(float[3] v, float s) {
    float[3] result = [v[0] * s, v[1] * s, v[2] * s];
    return result;
}

float[3] plus(float[3] a, float[3] b) {
    float[3] result = [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
    return result;
}

float[3] minus(float[3] a, float[3] b) {
    float[3] result = [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
    return result;
}

float[3] negated(float[3] v) {
    float[3] result = [-v[0], -v[1], -v[2]];
    return result;
}

float[3] cross(float[3] a, float[3] b) {
    float[3] result = [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ];
    return result;
}

float[3] rejectAlong(float[3] v, float[3] unitAxis) {
    return v.minus(unitAxis.scaled(v.dot(unitAxis)));
}

float[3] cappedTo(float[3] v, float maxMagnitude) {
    float magnitudeSquared = v.dot(v);
    if (magnitudeSquared > maxMagnitude * maxMagnitude) {
        return v.scaled(maxMagnitude / sqrt(magnitudeSquared));
    } else {
        return v;
    }
}

float[3] movedToward(float[3] current, float[3] target, float maxStep) {
    return current.plus(target.minus(current).cappedTo(maxStep));
}

float[3] projectedOntoPlane(float[3] subject, float[3] normal, float[3] direction, float distance) {
    return subject.plus(direction.scaled((distance - subject.dot(normal)) / direction.dot(normal)));
}

unittest {
    float[3] v = [3, 4, 0];
    assert(v.cappedTo(1).magnitude < 1.0001f);
    float[3] z = [0, 0, 1];
    assert(v.cross(z).dot(v) == 0);
    float[3] reached = ZERO_VECTOR.movedToward(v, 10);
    assert(reached[0] == 3 && reached[1] == 4);
    float[3] partial = ZERO_VECTOR.movedToward(v, 1);
    assert(partial.magnitude < 1.0001f && partial.magnitude > 0.9999f);
    float[3] xAxis = [1, 0, 0];
    assert(v.rejectAlong(xAxis).dot(xAxis) == 0);
}
