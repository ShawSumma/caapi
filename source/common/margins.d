module common.margins;

import common.dodeca : Vertex, vertexChunkAxisPermutations;
import common.node : VoxelData;
import common.voxel_math : Coords, CoordAxis, CoordSign, ChunkDirection, ChunkAxisPermutation;
import common.world : Material;

// Coordinates for a voxel including margins.
struct CoordsWithMargins {
    ubyte[3] data;

    this(ubyte[3] d) {
        data = d;
    }

    size_t toIndex(ubyte chunkSize) const {
        size_t csm = chunkSize + 2;
        return data[0] + data[1] * csm + data[2] * csm * csm;
    }

    static ubyte marginCoord(ubyte chunkSize, CoordSign sign) {
        if (sign == CoordSign.Plus) {
            return cast(ubyte)(chunkSize + 1);
        }
        return 0;
    }

    static ubyte boundaryCoord(ubyte chunkSize, CoordSign sign) {
        if (sign == CoordSign.Plus) {
            return chunkSize;
        }
        return 1;
    }

    ref ubyte opIndex(CoordAxis axis) return {
        return data[axis];
    }

    ubyte opIndex(CoordAxis axis) const {
        return data[axis];
    }
}

CoordsWithMargins fromCoords(Coords c) {
    ubyte[3] shifted;
    shifted[0] = cast(ubyte)(c.data[0] + 1);
    shifted[1] = cast(ubyte)(c.data[1] + 1);
    shifted[2] = cast(ubyte)(c.data[2] + 1);
    return CoordsWithMargins(shifted);
}

CoordsWithMargins permuteCoordsWithMargins(ChunkAxisPermutation perm, CoordsWithMargins rhs) {
    CoordsWithMargins result;
    foreach (i; 0 .. 3) {
        result.data[perm.axes[i]] = rhs.data[i];
    }
    return result;
}

ChunkAxisPermutation neighborAxisPermutation(Vertex vertex, ChunkDirection direction) {
    if (direction.sign == CoordSign.Plus) {
        return vertexChunkAxisPermutations(vertex)[direction.axis];
    }
    return ChunkAxisPermutation.IDENTITY;
}

ubyte[3] tuvToXyz(ubyte[3] input, size_t tAxis) {
    ubyte[3] r = input;
    r[tAxis] = input[0];
    r[(tAxis + 1) % 3] = input[1];
    r[(tAxis + 2) % 3] = input[2];
    return r;
}

// The margin ring runs one wider than the chunk on each side, so the sample it
// copies from is the nearest boundary voxel rather than one off the end.
ubyte clampToBoundary(int v, ubyte dimension) {
    if (v < 1) {
        return 1;
    }
    if (v > dimension) {
        return dimension;
    }
    return cast(ubyte) v;
}

// Updates the margins of both voxels and neighborVoxels at the side they meet.
void fixMargins(
    ubyte dimension,
    Vertex vertex,
    ref VoxelData voxels,
    ChunkDirection direction,
    ref VoxelData neighborVoxels,
) {
    ChunkAxisPermutation neighborPerm = neighborAxisPermutation(vertex, direction);

    ubyte marginC = CoordsWithMargins.marginCoord(dimension, direction.sign);
    ubyte boundaryC = CoordsWithMargins.boundaryCoord(dimension, direction.sign);

    // Two solid chunks that agree on being void or not have nothing to share.
    if (voxels.isSolid() && neighborVoxels.isSolid()) {
        bool selfVoid = voxels.get(0) == Material.Void;
        bool neighborVoid = neighborVoxels.get(0) == Material.Void;
        if (selfVoid == neighborVoid) {
            return;
        }
    }

    Material[] voxelData = voxels.dataMut(dimension);
    Material[] neighborVoxelData = neighborVoxels.dataMut(dimension);

    foreach (j; 0 .. dimension + 2) {
        foreach (i; 0 .. dimension + 2) {
            ubyte si = clampToBoundary(i, dimension);
            ubyte sj = clampToBoundary(j, dimension);

            ubyte[3] boundaryTuv = [boundaryC, si, sj];
            ubyte[3] marginTuv = [marginC, cast(ubyte) i, cast(ubyte) j];
            ubyte[3] boundaryXyz = tuvToXyz(boundaryTuv, direction.axis);
            ubyte[3] marginXyz = tuvToXyz(marginTuv, direction.axis);

            CoordsWithMargins boundaryCoords = CoordsWithMargins(boundaryXyz);
            CoordsWithMargins marginCoords = CoordsWithMargins(marginXyz);
            CoordsWithMargins permBoundary =
                permuteCoordsWithMargins(neighborPerm, boundaryCoords);
            CoordsWithMargins permMargin =
                permuteCoordsWithMargins(neighborPerm, marginCoords);

            voxelData[marginCoords.toIndex(dimension)] =
                neighborVoxelData[permBoundary.toIndex(dimension)];
            neighborVoxelData[permMargin.toIndex(dimension)] =
                voxelData[boundaryCoords.toIndex(dimension)];
        }
    }
}

// Initialize margins by copying boundary voxels outward.
void initializeMargins(ubyte dimension, ref VoxelData voxels) {
    if (voxels.isSolid()) {
        return;
    }

    foreach (dir; ChunkDirection.ALL) {
        ubyte marginC = CoordsWithMargins.marginCoord(dimension, dir.sign);
        ubyte boundaryC = CoordsWithMargins.boundaryCoord(dimension, dir.sign);
        Material[] data = voxels.dataMut(dimension);
        foreach (j; 0 .. dimension + 2) {
            foreach (i; 0 .. dimension + 2) {
                ubyte si = clampToBoundary(i, dimension);
                ubyte sj = clampToBoundary(j, dimension);

                ubyte[3] boundaryTuv = [boundaryC, si, sj];
                ubyte[3] marginTuv = [marginC, cast(ubyte) i, cast(ubyte) j];
                ubyte[3] boundaryXyz = tuvToXyz(boundaryTuv, dir.axis);
                ubyte[3] marginXyz = tuvToXyz(marginTuv, dir.axis);

                CoordsWithMargins bc = CoordsWithMargins(boundaryXyz);
                CoordsWithMargins mc = CoordsWithMargins(marginXyz);
                data[mc.toIndex(dimension)] = data[bc.toIndex(dimension)];
            }
        }
    }
}
