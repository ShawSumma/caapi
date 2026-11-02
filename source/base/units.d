module base.units;

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
