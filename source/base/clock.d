module base.clock;

import base.numbers : higherOf, lowerOf;

version (OSX) {
    import core.sys.posix.time : timespec;

    enum int CLOCK_MONOTONIC = 6;
    enum int CLOCK_THREAD_CPUTIME_ID = 16;

    extern (C) int clock_gettime(int clock, timespec* time) nothrow @nogc;
} else {
    import core.sys.posix.time : CLOCK_MONOTONIC, CLOCK_THREAD_CPUTIME_ID, clock_gettime, timespec;
}

enum double NANOSECONDS_PER_SECOND = 1e9;
enum double NANOSECONDS_PER_MILLISECOND = 1e6;
enum double MILLISECONDS_PER_SECOND = 1e3;
enum uint SMOOTHED_FRAMES = 8;
immutable double[2] TEST_UNEVEN_FRAMES = [0.012, 0.021];
enum double TEST_MOST_FRAME = 0.1;
enum double TEST_FRAME_TOLERANCE = 1e-9;

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
        worstMs = higherOf(ms, worstMs);
    }

    double averageMs() const {
        if (count > 0) {
            return totalMs / count;
        } else {
            return 0;
        }
    }
}

struct FrameClock {
    double[SMOOTHED_FRAMES] intervals = 0;
    double last = 0;
    double worst = 0;
    uint count;

    static FrameClock startingAt(double now) {
        FrameClock clock;
        clock.last = now;
        return clock;
    }

    double tick(double now, double most) {
        double interval = lowerOf(now - last, most);
        intervals[count % SMOOTHED_FRAMES] = interval;
        worst = higherOf(interval, worst);
        last = now;
        count += 1;
        uint used = lowerOf(count, SMOOTHED_FRAMES);
        double total = 0;
        foreach (recent; intervals[0 .. used]) {
            total += recent;
        }
        return total / used;
    }
}

unittest {
    FrameClock clock = FrameClock.startingAt(0);
    double now = 0;
    double smoothed = 0;
    foreach (frame; 0 .. 4 * SMOOTHED_FRAMES) {
        now += TEST_UNEVEN_FRAMES[frame % TEST_UNEVEN_FRAMES.length];
        smoothed = clock.tick(now, TEST_MOST_FRAME);
    }
    double mean = (TEST_UNEVEN_FRAMES[0] + TEST_UNEVEN_FRAMES[1]) / 2;
    assert(smoothed > mean - TEST_FRAME_TOLERANCE && smoothed < mean + TEST_FRAME_TOLERANCE);
    assert(clock.worst > TEST_UNEVEN_FRAMES[1] - TEST_FRAME_TOLERANCE && clock.worst < TEST_UNEVEN_FRAMES[1] + TEST_FRAME_TOLERANCE);
    smoothed = clock.tick(now + 1, TEST_MOST_FRAME);
    assert(smoothed < mean + TEST_MOST_FRAME / SMOOTHED_FRAMES + TEST_FRAME_TOLERANCE);
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
