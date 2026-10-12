module base.clock;

import core.sys.posix.time : CLOCK_MONOTONIC, CLOCK_THREAD_CPUTIME_ID, clock_gettime, timespec;

enum double NANOSECONDS_PER_SECOND = 1e9;
enum double NANOSECONDS_PER_MILLISECOND = 1e6;
enum double MILLISECONDS_PER_SECOND = 1e3;

double nowSeconds() {
    timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec + now.tv_nsec / NANOSECONDS_PER_SECOND;
}

struct PhaseTimes {
    double totalMs = 0;
    double worstMs = 0;
    double lastMs = 0;
    uint count;

    void add(double ms) {
        totalMs += ms;
        lastMs = ms;
        count += 1;
        if (ms > worstMs) {
            worstMs = ms;
        }
    }

    double averageMs() const {
        if (count > 0) {
            return totalMs / count;
        } else {
            return 0;
        }
    }
}

double nowMilliseconds() {
    timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec * MILLISECONDS_PER_SECOND + now.tv_nsec / NANOSECONDS_PER_MILLISECOND;
}

double threadCpuMilliseconds() {
    timespec used;
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &used);
    return used.tv_sec * MILLISECONDS_PER_SECOND + used.tv_nsec / NANOSECONDS_PER_MILLISECOND;
}
