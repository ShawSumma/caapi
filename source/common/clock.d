module common.clock;

import core.sys.posix.time : CLOCK_MONOTONIC, clock_gettime, timespec;

enum double NANOSECONDS_PER_SECOND = 1e9;
enum double NANOSECONDS_PER_MILLISECOND = 1e6;
enum double MILLISECONDS_PER_SECOND = 1e3;

double nowSeconds() {
    timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec + now.tv_nsec / NANOSECONDS_PER_SECOND;
}

double nowMilliseconds() {
    timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec * MILLISECONDS_PER_SECOND + now.tv_nsec / NANOSECONDS_PER_MILLISECOND;
}
