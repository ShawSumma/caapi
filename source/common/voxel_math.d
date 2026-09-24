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

struct Coords {
    ubyte[3] data;

    size_t toIndex(ubyte chunkSize) const {
        size_t stride = chunkSize + 2;
        return (data[0] + 1) + (data[1] + 1) * stride + (data[2] + 1) * stride * stride;
    }
}

ubyte boundaryCoord(ubyte chunkSize, CoordSign sign) {
    ubyte result = 0;
    if (sign == CoordSign.Plus) {
        result = cast(ubyte)(chunkSize - 1);
    }
    return result;
}

struct ChunkDirection {
    CoordAxis axis;
    CoordSign sign;
}

immutable ChunkDirection[6] CHUNK_DIRECTIONS = [
    ChunkDirection(CoordAxis.X, CoordSign.Plus),
    ChunkDirection(CoordAxis.Y, CoordSign.Plus),
    ChunkDirection(CoordAxis.Z, CoordSign.Plus),
    ChunkDirection(CoordAxis.X, CoordSign.Minus),
    ChunkDirection(CoordAxis.Y, CoordSign.Minus),
    ChunkDirection(CoordAxis.Z, CoordSign.Minus),
];

struct ChunkAxisPermutation {
    CoordAxis[3] axes = [CoordAxis.X, CoordAxis.Y, CoordAxis.Z];

    Coords apply(Coords rhs) const {
        Coords result;
        foreach (i; 0 .. 3) {
            result.data[axes[i]] = rhs.data[i];
        }
        return result;
    }
}

enum ChunkAxisPermutation IDENTITY_PERMUTATION = ChunkAxisPermutation.init;

ChunkAxisPermutation permutationFromSides(Side[3] from, Side[3] to) {
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
