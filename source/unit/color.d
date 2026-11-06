module unit.color;

import core.stdc.math : fabsf;
import base.numbers : PI;
import base.units : Angle;
import common.color : CHROMA_AXES, CHROMA_BASIS, COLOR_CHANNELS, ColorTurn, Seen, Spectrum, TURN_PLANES, dotOf, grayOf, seenOf, spectrumOf, turned;

enum float COLOR_TOLERANCE = 1e-5f;
immutable Seen SAMPLE = [0.6f, 0.2f, 0.05f];

ColorTurn turnOf(float radians) {
    ColorTurn turn;
    foreach (index; 0 .. TURN_PLANES) {
        turn.angles[index] = Angle(radians * (index + 1));
    }
    return turn;
}

bool isNear(float a, float b) {
    return fabsf(a - b) <= COLOR_TOLERANCE;
}

unittest {
    foreach (axis; 0 .. CHROMA_AXES) {
        float sum = 0;
        foreach (channel; CHROMA_BASIS[axis]) {
            sum += channel;
        }
        assert(isNear(sum, 0));
        foreach (other; 0 .. CHROMA_AXES) {
            float expected = 0;
            if (other == axis) {
                expected = 1;
            }
            assert(isNear(dotOf(CHROMA_BASIS[axis], CHROMA_BASIS[other]), expected));
        }
    }
}

unittest {
    Spectrum color = spectrumOf(SAMPLE);
    ColorTurn still;
    Seen same = seenOf(turned(color, still));
    foreach (channel; 0 .. 3) {
        assert(isNear(same[channel], SAMPLE[channel]));
    }
    ColorTurn whole;
    foreach (index; 0 .. TURN_PLANES) {
        whole.angles[index] = Angle(2 * PI);
    }
    Spectrum around = turned(color, whole);
    foreach (channel; 0 .. COLOR_CHANNELS) {
        assert(isNear(around[channel], color[channel]));
    }
}

unittest {
    Spectrum gray = 0.4f;
    Spectrum moved = turned(gray, turnOf(0.7f));
    foreach (channel; moved) {
        assert(isNear(channel, 0.4f));
    }
    Spectrum color = spectrumOf(SAMPLE);
    Spectrum other = turned(color, turnOf(1.3f));
    assert(isNear(grayOf(other), grayOf(color)));
    float before = 0;
    float after = 0;
    foreach (channel; 0 .. COLOR_CHANNELS) {
        before += (color[channel] - grayOf(color)) * (color[channel] - grayOf(color));
        after += (other[channel] - grayOf(other)) * (other[channel] - grayOf(other));
    }
    assert(isNear(before, after));
    foreach (step; 0 .. 32) {
        Seen seen = seenOf(turned(color, turnOf(step * 0.2f)));
        foreach (channel; seen) {
            assert(channel >= -COLOR_TOLERANCE);
        }
    }
}
