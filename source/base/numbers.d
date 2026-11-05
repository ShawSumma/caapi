module base.numbers;

enum float PI = 3.14159265358979323846f;
enum double RADIANS_PER_DEGREE = 0.017453292519943295;
enum double LN_TWO = 0.69314718055994530942;
enum uint LOG_SERIES_TERMS = 40;
enum uint SQRT_STEPS = 60;

bool isNan(float value) {
    return value != value;
}

T lowerOf(T)(T a, T b) {
    if (a < b) {
        return a;
    } else {
        return b;
    }
}

T higherOf(T)(T a, T b) {
    if (a > b) {
        return a;
    } else {
        return b;
    }
}

double logAtCompileTime(double x) {
    assert(x > 0);
    double scaled = x;
    double exponent = 0;
    while (scaled > 2) {
        scaled /= 2;
        exponent += 1;
    }
    while (scaled < 1) {
        scaled *= 2;
        exponent -= 1;
    }
    double z = (scaled - 1) / (scaled + 1);
    double square = z * z;
    double term = z;
    double sum = 0;
    foreach (k; 0 .. LOG_SERIES_TERMS) {
        sum += term / (2 * k + 1);
        term *= square;
    }
    return 2 * sum + exponent * LN_TWO;
}

double acoshAtCompileTime(double x) {
    return logAtCompileTime(x + sqrtAtCompileTime(x * x - 1));
}

double asinhAtCompileTime(double x) {
    return logAtCompileTime(x + sqrtAtCompileTime(x * x + 1));
}

double sqrtAtCompileTime(double x) {
    double estimate = higherOf(x, 1.0);
    foreach (_; 0 .. SQRT_STEPS) {
        estimate = (estimate + x / estimate) / 2;
    }
    return estimate;
}

T clamped(T)(T value, T low, T high) {
    if (value < low) {
        return low;
    } else if (value > high) {
        return high;
    } else {
        return value;
    }
}
