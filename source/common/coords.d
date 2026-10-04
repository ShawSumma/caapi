module common.coords;

import common.dodeca : Side;

enum CoordAxis : ubyte {
    x = 0,
    y = 1,
    z = 2,
}

enum CoordSign : byte {
    plus = 1,
    minus = -1,
}

struct Coords {
    ubyte[3] data;

    size_t toIndex(ubyte chunkSize) const {
        size_t stride = chunkSize + 2;
        return (data[0] + 1) + (data[1] + 1) * stride + (data[2] + 1) * stride * stride;
    }
}

ubyte boundaryCoord(ubyte chunkSize, CoordSign sign) {
    if (sign == CoordSign.plus) {
        return cast(ubyte)(chunkSize - 1);
    } else {
        return 0;
    }
}

struct ChunkDirection {
    CoordAxis axis;
    CoordSign sign;
}

immutable ChunkDirection[6] CHUNK_DIRECTIONS = [
    ChunkDirection(CoordAxis.x, CoordSign.plus),
    ChunkDirection(CoordAxis.y, CoordSign.plus),
    ChunkDirection(CoordAxis.z, CoordSign.plus),
    ChunkDirection(CoordAxis.x, CoordSign.minus),
    ChunkDirection(CoordAxis.y, CoordSign.minus),
    ChunkDirection(CoordAxis.z, CoordSign.minus),
];

struct ChunkAxisPermutation {
    CoordAxis[3] axes = [CoordAxis.x, CoordAxis.y, CoordAxis.z];

    static ChunkAxisPermutation fromSides(Side[3] from, Side[3] to) {
        ChunkAxisPermutation result;
        foreach (i; 0 .. 3) {
            foreach (j; 0 .. 3) {
                if (from[i] == to[j]) {
                    result.axes[i] = cast(CoordAxis) j;
                }
            }
        }
        return result;
    }

    C apply(C)(C rhs) const {
        C result;
        foreach (i; 0 .. 3) {
            result.data[axes[i]] = rhs.data[i];
        }
        return result;
    }
}

enum ChunkAxisPermutation IDENTITY_PERMUTATION = ChunkAxisPermutation.init;
