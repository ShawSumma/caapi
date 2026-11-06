module common.biology.signaling;

import core.stdc.math : expf;
import base.units : Rate, Ratio, Time;
import common.biology.pocket : TRANSDUCER_COUNT;

enum uint MESSENGER_COUNT = 3;
enum uint SIGNAL_COUNT = 3;
enum Rate MESSENGER_RATE = Rate(2.0f);
enum Rate ADAPTATION_RATE = Rate(0.01f);
enum float SIGMOID_MIDPOINT = 0.5f;
enum float SIGMOID_STEEPNESS = 8;
enum uint REST_SETTLE_TICKS = 400;
enum Time REST_TICK = Time(0.05f);

immutable float[TRANSDUCER_COUNT][MESSENGER_COUNT] DRIVE = [
    [1.0f, 0.0f],
    [0.0f, 1.0f],
    [0.5f, 0.5f],
];

immutable float[MESSENGER_COUNT][MESSENGER_COUNT] CROSSTALK = [
    [0.0f, -0.6f, 0.0f],
    [-0.6f, 0.0f, 0.0f],
    [0.4f, 0.4f, 0.0f],
];

immutable float[MESSENGER_COUNT][SIGNAL_COUNT] READOUT = [
    [1.0f, 0.0f, 0.0f],
    [0.0f, 1.0f, 0.0f],
    [0.0f, 0.0f, 1.0f],
];

float sigmoid(float level) {
    return 1 / (1 + expf(-SIGMOID_STEEPNESS * (level - SIGMOID_MIDPOINT)));
}

struct Signaling {
    Ratio[MESSENGER_COUNT] messengers;
    Ratio[SIGNAL_COUNT] adaptation;

    static Signaling atRest() {
        Signaling resting;
        Ratio[TRANSDUCER_COUNT] quiet;
        foreach (_; 0 .. REST_SETTLE_TICKS) {
            resting.advance(quiet, REST_TICK);
        }
        foreach (signal; 0 .. SIGNAL_COUNT) {
            resting.adaptation[signal] = Ratio(resting.rawSignal(signal));
        }
        return resting;
    }

    void advance(Ratio[TRANSDUCER_COUNT] activation, Time step) {
        float settled = expf(-(MESSENGER_RATE * step).value);
        Ratio[MESSENGER_COUNT] next;
        foreach (messenger; 0 .. MESSENGER_COUNT) {
            float target = 0;
            foreach (transducer; 0 .. TRANSDUCER_COUNT) {
                target += DRIVE[messenger][transducer] * activation[transducer].value;
            }
            foreach (other; 0 .. MESSENGER_COUNT) {
                target += CROSSTALK[messenger][other] * sigmoid(messengers[other].value);
            }
            next[messenger] = Ratio(target + (messengers[messenger].value - target) * settled);
        }
        messengers = next;
        float adapted = expf(-(ADAPTATION_RATE * step).value);
        foreach (signal; 0 .. SIGNAL_COUNT) {
            float raw = rawSignal(signal);
            adaptation[signal] = Ratio(raw + (adaptation[signal].value - raw) * adapted);
        }
    }

    float rawSignal(uint signal) const {
        float sum = 0;
        foreach (messenger; 0 .. MESSENGER_COUNT) {
            sum += READOUT[signal][messenger] * messengers[messenger].value;
        }
        return sum;
    }

    Ratio signalOf(uint signal) const {
        return Ratio(rawSignal(signal) - adaptation[signal].value);
    }

    Ratio[SIGNAL_COUNT] signals() const {
        Ratio[SIGNAL_COUNT] all;
        foreach (signal; 0 .. SIGNAL_COUNT) {
            all[signal] = signalOf(signal);
        }
        return all;
    }
}
