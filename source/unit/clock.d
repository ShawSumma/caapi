module unit.clock;

import base.clock : FrameClock, SMOOTHED_FRAMES;

immutable double[2] UNEVEN_FRAMES = [0.012, 0.021];
enum double MOST_FRAME = 0.1;
enum double FRAME_TOLERANCE = 1e-9;
enum double AWAY_SECONDS = 5;

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
    now += AWAY_SECONDS;
    smoothed = clock.tick(now, MOST_FRAME);
    assert(smoothed > mean - FRAME_TOLERANCE && smoothed < mean + FRAME_TOLERANCE);
    foreach (frame; 0 .. SMOOTHED_FRAMES) {
        now += UNEVEN_FRAMES[frame % UNEVEN_FRAMES.length];
        smoothed = clock.tick(now, MOST_FRAME);
        assert(smoothed > mean - FRAME_TOLERANCE && smoothed < mean + FRAME_TOLERANCE);
    }
}

unittest {
    FrameClock clock = FrameClock.startingAt(0);
    assert(clock.tick(AWAY_SECONDS, MOST_FRAME) == MOST_FRAME);
}
