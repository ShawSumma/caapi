module common.clock;

import core.sys.posix.unistd : usleep;

// core.sys.posix.time doesn't expose these on Darwin, so they are declared
// directly. Layout and constant were read out of the platform <time.h> rather
// than assumed: CLOCK_MONOTONIC is 6 and both timespec fields are 64-bit.
extern(C) {
    struct Timespec {
        long tv_sec;
        long tv_nsec;
    }

    int clock_gettime(int clockId, Timespec* tp) nothrow @nogc;
}

version (OSX) {
    enum int CLOCK_MONOTONIC = 6;
} else {
    enum int CLOCK_MONOTONIC = 1;
}

// Monotonic milliseconds since an arbitrary epoch. Only differences are
// meaningful. Straight to libc so this survives a betterC build.
double nowMs() {
    Timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return cast(double) ts.tv_sec * 1000.0 + cast(double) ts.tv_nsec / 1000000.0;
}

void sleepMs(uint ms) {
    usleep(ms * 1000);
}

unittest {
    double a = nowMs();
    sleepMs(5);
    double b = nowMs();
    assert(b > a, "monotonic clock did not advance");
    assert(b - a < 1000.0, "sleep overshot wildly; units are probably wrong");
}
