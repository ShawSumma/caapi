module geometry.cube;

import geometry.honeycomb : Face;

// Cells inside one cube of a dodecahedron, addressed by their position along its three axes.

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

immutable int[3][6] CELL_STEPS = [
    [-1, 0, 0],
    [1, 0, 0],
    [0, -1, 0],
    [0, 1, 0],
    [0, 0, -1],
    [0, 0, 1],
];

size_t directionIndex(Direction direction) {
    return direction.sign == Sign.plus ? direction.axis : direction.axis + AXIS_COUNT;
}

struct Cell {
    ubyte[3] c;
}

ubyte boundaryOf(ubyte dimension, Sign sign) {
    return sign == Sign.plus ? cast(ubyte)(dimension - 1) : 0;
}

// How a neighboring cube's axes line up with this one's: axis i here is axis to[i] there.
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

    T[3] apply(T)(T[3] cell) const {
        T[3] result;
        foreach (i; 0 .. 3) {
            result[to[i]] = cell[i];
        }
        return result;
    }
}
