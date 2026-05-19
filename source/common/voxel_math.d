module common.voxel_math;

import common.dodeca : Side;

enum CoordAxis : ubyte {
    X = 0,
    Y = 1,
    Z = 2,
}

enum CoordSign : byte {
    Plus = 1,
    Minus = -1,
}

CoordSign mul(CoordSign a, CoordSign b) {
    return a == b ? CoordSign.Plus : CoordSign.Minus;
}

struct Coords {
    ubyte[3] data;

    this(ubyte[3] d) {
        data = d;
    }

    this(ubyte x, ubyte y, ubyte z) {
        data = [x, y, z];
    }

    size_t toIndex(ubyte chunkSize) const {
        size_t csm = chunkSize + 2;
        return (data[0] + 1)
             + (data[1] + 1) * csm
             + (data[2] + 1) * csm * csm;
    }

    static ubyte boundaryCoord(ubyte chunkSize, CoordSign sign) {
        return sign == CoordSign.Plus ? cast(ubyte)(chunkSize - 1) : 0;
    }

    ref ubyte opIndex(CoordAxis axis) return {
        return data[axis];
    }

    ubyte opIndex(CoordAxis axis) const {
        return data[axis];
    }
}

struct ChunkDirection {
    CoordAxis axis;
    CoordSign sign;

    static immutable ChunkDirection PLUS_X = ChunkDirection(CoordAxis.X, CoordSign.Plus);
    static immutable ChunkDirection PLUS_Y = ChunkDirection(CoordAxis.Y, CoordSign.Plus);
    static immutable ChunkDirection PLUS_Z = ChunkDirection(CoordAxis.Z, CoordSign.Plus);
    static immutable ChunkDirection MINUS_X = ChunkDirection(CoordAxis.X, CoordSign.Minus);
    static immutable ChunkDirection MINUS_Y = ChunkDirection(CoordAxis.Y, CoordSign.Minus);
    static immutable ChunkDirection MINUS_Z = ChunkDirection(CoordAxis.Z, CoordSign.Minus);

    static immutable ChunkDirection[6] ALL = [
        PLUS_X, PLUS_Y, PLUS_Z, MINUS_X, MINUS_Y, MINUS_Z
    ];
}

struct ChunkAxisPermutation {
    CoordAxis[3] axes = [CoordAxis.X, CoordAxis.Y, CoordAxis.Z];

    static immutable ChunkAxisPermutation IDENTITY = ChunkAxisPermutation([CoordAxis.X, CoordAxis.Y, CoordAxis.Z]);

    static ChunkAxisPermutation fromPermutation(Side[3] from, Side[3] to) {
        CoordAxis[3] result;
        foreach (i; 0 .. 3) {
            bool found = false;
            foreach (j; 0 .. 3) {
                if (from[i] == to[j]) {
                    result[i] = cast(CoordAxis)j;
                    found = true;
                    break;
                }
            }
            assert(found, "from and to must have same set of sides");
        }
        return ChunkAxisPermutation(result);
    }

    CoordAxis opIndex(CoordAxis axis) const {
        return axes[axis];
    }

    Coords opBinary(string op)(Coords rhs) const if (op == "*") {
        Coords result;
        foreach (i; 0 .. 3) {
            result.data[axes[i]] = rhs.data[i];
        }
        return result;
    }

    ChunkDirection opBinary(string op)(ChunkDirection rhs) const if (op == "*") {
        return ChunkDirection(axes[rhs.axis], rhs.sign);
    }
}
