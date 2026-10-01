module common.vector3;

import core.math : sqrt;

float dot3(float[3] a, float[3] b) {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

float magnitude3(float[3] v) {
    return sqrt(dot3(v, v));
}

float[3] scale3(float[3] v, float s) {
    float[3] result = [v[0] * s, v[1] * s, v[2] * s];
    return result;
}

float[3] add3(float[3] a, float[3] b) {
    float[3] result = [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
    return result;
}

float[3] sub3(float[3] a, float[3] b) {
    float[3] result = [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
    return result;
}

float[3] neg3(float[3] v) {
    float[3] result = [-v[0], -v[1], -v[2]];
    return result;
}

float[3] cross3(float[3] a, float[3] b) {
    float[3] result = [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ];
    return result;
}

float[3] zero3() {
    float[3] result = [0.0f, 0.0f, 0.0f];
    return result;
}

float[3] rejectAlong(float[3] v, float[3] unitAxis) {
    return sub3(v, scale3(unitAxis, dot3(v, unitAxis)));
}

float[3] capMagnitude3(float[3] v, float maxMagnitude) {
    float magnitudeSquared = dot3(v, v);
    float[3] result = v;
    if (magnitudeSquared > maxMagnitude * maxMagnitude) {
        result = scale3(v, maxMagnitude / sqrt(magnitudeSquared));
    }
    return result;
}

float[3] moveToward3(float[3] current, float[3] target, float maxStep) {
    float[3] toTarget = sub3(target, current);
    return add3(current, capMagnitude3(toTarget, maxStep));
}

unittest {
    float[3] v = [3, 4, 0];
    assert(magnitude3(capMagnitude3(v, 1)) < 1.0001f);
    float[3] z = [0, 0, 1];
    assert(dot3(cross3(v, z), v) == 0);
    float[3] reached = moveToward3(zero3(), v, 10);
    assert(reached[0] == 3 && reached[1] == 4);
    float[3] partial = moveToward3(zero3(), v, 1);
    assert(magnitude3(partial) < 1.0001f && magnitude3(partial) > 0.9999f);
    assert(dot3(rejectAlong(v, [1, 0, 0]), [1, 0, 0]) == 0);
}
