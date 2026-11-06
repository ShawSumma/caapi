module unit.signaling;

import base.units : Ratio, Time;
import common.biology.pocket : TRANSDUCER_COUNT;
import common.biology.signaling : Signaling;

enum Time TICK = Time(0.05f);
enum uint DOSED_TICKS = 20000;
enum uint WITHDRAWN_TICKS = 60;
enum uint BASELINE_TICKS = 2000;
enum float REBOUND_SHARE = 0.9f;

unittest {
    Ratio[TRANSDUCER_COUNT] resting;
    Ratio[TRANSDUCER_COUNT] driven = [Ratio(1), Ratio(0)];
    Signaling baseline;
    foreach (_; 0 .. BASELINE_TICKS) {
        baseline.advance(resting, TICK);
    }
    float rawOff = baseline.rawSignal(0);
    Signaling dosed = baseline;
    foreach (_; 0 .. DOSED_TICKS) {
        dosed.advance(driven, TICK);
    }
    float rawOn = dosed.rawSignal(0);
    assert(rawOn > rawOff);
    foreach (_; 0 .. WITHDRAWN_TICKS) {
        dosed.advance(resting, TICK);
    }
    assert(dosed.signalOf(0).value <= -REBOUND_SHARE * (rawOn - rawOff));
}
