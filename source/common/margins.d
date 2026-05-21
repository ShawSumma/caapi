module common.margins;

import common.dodeca : Vertex, vertexChunkAxisPermutations;
import common.node : VoxelData;
import common.voxel_math : Coords, CoordAxis, CoordSign, ChunkDirection, ChunkAxisPermutation;
import common.world : Material;

/// Coordinates for a voxel including margins
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
        return sign == CoordSign.Plus ? cast(ubyte)(chunkSize + 1) : 0;
    }

    static ubyte boundaryCoord(ubyte chunkSize, CoordSign sign) {
        return sign == CoordSign.Plus ? chunkSize : 1;
    }

    ref ubyte opIndex(CoordAxis axis) return {
        return data[axis];
    }

    ubyte opIndex(CoordAxis axis) const {
        return data[axis];
    }
}

CoordsWithMargins fromCoords(Coords c) {
    return CoordsWithMargins([cast(ubyte)(c.data[0] + 1), cast(ubyte)(c.data[1] + 1), cast(ubyte)(c.data[2] + 1)]);
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

/// Updates the margins of both voxels and neighborVoxels at the side they meet at.
void fixMargins(
    ubyte dimension,
    Vertex vertex,
    ref VoxelData voxels,
    ChunkDirection direction,
    ref VoxelData neighborVoxels
) {
    ChunkAxisPermutation neighborPerm = neighborAxisPermutation(vertex, direction);

    ubyte marginC = CoordsWithMargins.marginCoord(dimension, direction.sign);
    ubyte boundaryC = CoordsWithMargins.boundaryCoord(dimension, direction.sign);

    // If both solid and same void-ness, nothing to do
    if (voxels.isSolid() && neighborVoxels.isSolid()) {
        if ((voxels.get(0) == Material.Void) == (neighborVoxels.get(0) == Material.Void)) {
            return;
        }
    }

    Material[] voxelData = voxels.dataMut(dimension);
    Material[] neighborVoxelData = neighborVoxels.dataMut(dimension);

    foreach (j; 0 .. dimension + 2) {
        foreach (i; 0 .. dimension + 2) {
            ubyte si = i < 1 ? 1 : (i > dimension ? dimension : cast(ubyte) i);
            ubyte sj = j < 1 ? 1 : (j > dimension ? dimension : cast(ubyte) j);
            CoordsWithMargins boundaryCoords = CoordsWithMargins(tuvToXyz(
                [boundaryC, si, sj], direction.axis
            ));
            CoordsWithMargins marginCoords = CoordsWithMargins(tuvToXyz(
                [marginC, cast(ubyte) i, cast(ubyte) j], direction.axis
            ));

            voxelData[marginCoords.toIndex(dimension)] =
                neighborVoxelData[permuteCoordsWithMargins(neighborPerm, boundaryCoords).toIndex(dimension)];
            neighborVoxelData[permuteCoordsWithMargins(neighborPerm, marginCoords).toIndex(dimension)] =
                voxelData[boundaryCoords.toIndex(dimension)];
        }
    }
}

/// Initialize margins by copying boundary voxels outward
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
                ubyte si = i < 1 ? 1 : (i > dimension ? dimension : cast(ubyte) i);
                ubyte sj = j < 1 ? 1 : (j > dimension ? dimension : cast(ubyte) j);
                CoordsWithMargins bc = CoordsWithMargins(tuvToXyz(
                    [boundaryC, si, sj], dir.axis
                ));
                CoordsWithMargins mc = CoordsWithMargins(tuvToXyz(
                    [cast(ubyte) marginC, cast(ubyte) i, cast(ubyte) j], dir.axis
                ));
                data[mc.toIndex(dimension)] = data[bc.toIndex(dimension)];
            }
        }
    }
}
