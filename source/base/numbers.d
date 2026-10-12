module base.numbers;

enum float PI = 3.14159265358979323846f;

bool isNan(float value) {
    return value != value;
}

bool isInfinite(float value) {
    return value == float.infinity || value == -float.infinity;
}

T lowerOf(T)(T a, T b) {
    return a < b ? a : b;
}

T higherOf(T)(T a, T b) {
    return a > b ? a : b;
}

// The C library's logarithms cannot run at compile time; these can, for constants derived from geometry.
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
    double estimate = x > 1 ? x : 1;
    foreach (_; 0 .. SQRT_STEPS) {
        estimate = (estimate + x / estimate) / 2;
    }
    return estimate;
}

enum double LN_TWO = 0.69314718055994530942;
enum uint LOG_SERIES_TERMS = 40;
enum uint SQRT_STEPS = 60;

float clamped(float value, float low, float high) {
    if (value < low) {
        return low;
    } else if (value > high) {
        return high;
    } else {
        return value;
    }
}
