module base.clock;

import base.maybe : Maybe;
import base.numbers : higherOf, lowerOf;

enum double NANOSECONDS_PER_SECOND = 1e9;
enum double NANOSECONDS_PER_MILLISECOND = 1e6;
enum double MILLISECONDS_PER_SECOND = 1e3;
enum uint SMOOTHED_FRAMES = 8;

version (WebAssembly) {
    extern (C) double web_now() nothrow @nogc;

    double nowSeconds() {
        return web_now() / MILLISECONDS_PER_SECOND;
    }

    double nowMilliseconds() {
        return web_now();
    }

    double threadCpuMilliseconds() {
        return web_now();
    }
} else {
    version (OSX) {
        import core.sys.posix.time : timespec;

        enum int CLOCK_MONOTONIC = 6;
        enum int CLOCK_THREAD_CPUTIME_ID = 16;

        extern (C) int clock_gettime(int clock, timespec* time) nothrow @nogc;
    } else {
        import core.sys.posix.time : CLOCK_MONOTONIC, CLOCK_THREAD_CPUTIME_ID, clock_gettime, timespec;
    }

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

    double threadCpuMilliseconds() {
        timespec used;
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &used);
        return used.tv_sec * MILLISECONDS_PER_SECOND + used.tv_nsec / NANOSECONDS_PER_MILLISECOND;
    }
}

struct Deadline {
    Maybe!double milliseconds;

    static Deadline at(double chosen) {
        return Deadline(Maybe!double.of(chosen));
    }

    bool isBounded() const {
        return milliseconds.exists;
    }

    bool hasPassed(double now) const {
        return isBounded && now >= milliseconds.value;
    }
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
