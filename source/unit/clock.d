module unit.clock;

import base.clock : FrameClock, SMOOTHED_FRAMES;

immutable double[2] UNEVEN_FRAMES = [0.012, 0.021];
enum double MOST_FRAME = 0.1;
enum double FRAME_TOLERANCE = 1e-9;

unittest {
    FrameClock clock = FrameClock.startingAt(0);
    double now = 0;
    double smoothed = 0;
    foreach (frame; 0 .. 4 * SMOOTHED_FRAMES) {
        now += UNEVEN_FRAMES[frame % UNEVEN_FRAMES.length];
        smoothed = clock.tick(now, MOST_FRAME);
    }
    double mean = (UNEVEN_FRAMES[0] + UNEVEN_FRAMES[1]) / 2;
    assert(smoothed > mean - FRAME_TOLERANCE && smoothed < mean + FRAME_TOLERANCE);
    assert(clock.worst > UNEVEN_FRAMES[1] - FRAME_TOLERANCE && clock.worst < UNEVEN_FRAMES[1] + FRAME_TOLERANCE);
    smoothed = clock.tick(now + 1, MOST_FRAME);
    assert(smoothed < mean + MOST_FRAME / SMOOTHED_FRAMES + FRAME_TOLERANCE);
}
