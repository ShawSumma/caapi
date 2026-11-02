module unit.units;

import base.units : Acceleration, Angle, AngularSpeed, Blocks, Length, LocalBlock, Rate, Ratio, Speed, Time;

enum float TOLERANCE = 1e-6f;

unittest {
    static assert(is(typeof(Speed(2) * Time(3)) == Length));
    static assert(is(typeof(Acceleration(2) * Time(3)) == Speed));
    static assert(is(typeof(Length(2) / Time(4)) == Speed));
    static assert(is(typeof(Rate(2) * Time(3)) == Ratio));
    static assert(is(typeof(AngularSpeed(2) * Time(3)) == Angle));
    static assert(!is(typeof(Length(1) + Time(1))));
    Length traveled = Speed(0.5f) * Time(4) - Length(0.5f);
    assert(traveled.value > 1.5f - TOLERANCE && traveled.value < 1.5f + TOLERANCE);
    assert(Length(1) < Length(2));
    assert(LocalBlock(Length(0.05f)).heightOf(Blocks(2)).value > 0.1f - TOLERANCE);
}
