module base.units;

enum float TEST_TOLERANCE = 1e-6f;

struct Quantity(int lengthPower, int timePower, int anglePower) {
    float value = 0;

    Quantity opBinary(string op)(Quantity other) const if (op == "+" || op == "-") {
        return Quantity(mixin("value " ~ op ~ " other.value"));
    }

    Quantity opBinary(string op)(float scale) const if (op == "*" || op == "/") {
        return Quantity(mixin("value " ~ op ~ " scale"));
    }

    Quantity!(lengthPower + otherLength, timePower + otherTime, anglePower + otherAngle) opBinary(string op : "*", int otherLength, int otherTime, int otherAngle)(Quantity!(otherLength, otherTime, otherAngle) other) const {
        return Quantity!(lengthPower + otherLength, timePower + otherTime, anglePower + otherAngle)(value * other.value);
    }

    Quantity!(lengthPower - otherLength, timePower - otherTime, anglePower - otherAngle) opBinary(string op : "/", int otherLength, int otherTime, int otherAngle)(Quantity!(otherLength, otherTime, otherAngle) other) const {
        return Quantity!(lengthPower - otherLength, timePower - otherTime, anglePower - otherAngle)(value / other.value);
    }

    Quantity opUnary(string op)() const if (op == "-") {
        return Quantity(-value);
    }

    int opCmp(Quantity other) const {
        if (value < other.value) {
            return -1;
        } else if (value > other.value) {
            return 1;
        } else {
            return 0;
        }
    }
}

struct Blocks {
    float value = 0;
}

struct LocalBlock {
    Length height;

    Length heightOf(Blocks count) const {
        return height * count.value;
    }
}

alias Ratio = Quantity!(0, 0, 0);
alias Length = Quantity!(1, 0, 0);
alias Time = Quantity!(0, 1, 0);
alias Angle = Quantity!(0, 0, 1);
alias Rate = Quantity!(0, -1, 0);
alias Speed = Quantity!(1, -1, 0);
alias Acceleration = Quantity!(1, -2, 0);
alias AngularSpeed = Quantity!(0, -1, 1);

unittest {
    static assert(is(typeof(Speed(2) * Time(3)) == Length));
    static assert(is(typeof(Acceleration(2) * Time(3)) == Speed));
    static assert(is(typeof(Length(2) / Time(4)) == Speed));
    static assert(is(typeof(Rate(2) * Time(3)) == Ratio));
    static assert(is(typeof(AngularSpeed(2) * Time(3)) == Angle));
    static assert(!is(typeof(Length(1) + Time(1))));
    Length traveled = Speed(0.5f) * Time(4) - Length(0.5f);
    assert(traveled.value > 1.5f - TEST_TOLERANCE && traveled.value < 1.5f + TEST_TOLERANCE);
    assert(Length(1) < Length(2));
    assert(LocalBlock(Length(0.05f)).heightOf(Blocks(2)).value > 0.1f - TEST_TOLERANCE);
}
