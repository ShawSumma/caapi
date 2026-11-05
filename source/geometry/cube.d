module geometry.cube;

import base.vector3 : Vec3;
import geometry.honeycomb : Face;

enum Axis : ubyte {
    x,
    y,
    z,
}

enum uint AXIS_COUNT = 3;

enum Sign : byte {
    plus = 1,
    minus = -1,
}

struct Direction {
    Axis axis;
    Sign sign;
}

immutable Direction[6] DIRECTIONS = [
    Direction(Axis.x, Sign.plus),
    Direction(Axis.y, Sign.plus),
    Direction(Axis.z, Sign.plus),
    Direction(Axis.x, Sign.minus),
    Direction(Axis.y, Sign.minus),
    Direction(Axis.z, Sign.minus),
];

immutable Vec3!int[6] CELL_STEPS = [
    Vec3!int(-1, 0, 0),
    Vec3!int(1, 0, 0),
    Vec3!int(0, -1, 0),
    Vec3!int(0, 1, 0),
    Vec3!int(0, 0, -1),
    Vec3!int(0, 0, 1),
];

size_t directionIndex(Direction direction) {
    if (direction.sign == Sign.plus) {
        return direction.axis;
    } else {
        return direction.axis + AXIS_COUNT;
    }
}

alias Cell = Vec3!ubyte;

ubyte boundaryOf(ubyte dimension, Sign sign) {
    if (sign == Sign.plus) {
        return cast(ubyte)(dimension - 1);
    } else {
        return 0;
    }
}

int beyondBoundary(ubyte dimension, Sign sign) {
    if (sign == Sign.plus) {
        return dimension;
    } else {
        return -1;
    }
}

struct AxisMap {
    Axis[3] to = [Axis.x, Axis.y, Axis.z];

    static AxisMap between(Face[3] from, Face[3] onto) {
        AxisMap map;
        foreach (i; 0 .. 3) {
            foreach (j; 0 .. 3) {
                if (from[i] == onto[j]) {
                    map.to[i] = cast(Axis) j;
                }
            }
        }
        return map;
    }

    Vec3!T apply(T)(Vec3!T cell) const {
        Vec3!T result;
        foreach (i; 0 .. 3) {
            result[to[i]] = cell[i];
        }
        return result;
    }
}
