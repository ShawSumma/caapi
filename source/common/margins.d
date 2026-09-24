module common.margins;

import common.dodeca : Vertex, vertexChunkAxisPermutations;
import common.node : VoxelData;
import common.voxel_math : CHUNK_DIRECTIONS, ChunkAxisPermutation, ChunkDirection, CoordSign, IDENTITY_PERMUTATION;
import common.world : Material;

struct CoordsWithMargins {
    ubyte[3] data;

    size_t toIndex(ubyte chunkSize) const {
        size_t stride = chunkSize + 2;
        return data[0] + data[1] * stride + data[2] * stride * stride;
    }
}

ubyte marginCoord(ubyte chunkSize, CoordSign sign) {
    ubyte result = 0;
    if (sign == CoordSign.Plus) {
        result = cast(ubyte)(chunkSize + 1);
    }
    return result;
}

ubyte boundaryCoordWithMargins(ubyte chunkSize, CoordSign sign) {
    ubyte result = 1;
    if (sign == CoordSign.Plus) {
        result = chunkSize;
    }
    return result;
}

ubyte clampToInterior(size_t index, ubyte dimension) {
    ubyte result = cast(ubyte) index;
    if (index < 1) {
        result = 1;
    } else if (index > dimension) {
        result = dimension;
    }
    return result;
}

CoordsWithMargins permuteCoordsWithMargins(ChunkAxisPermutation permutation, CoordsWithMargins rhs) {
    CoordsWithMargins result;
    foreach (i; 0 .. 3) {
        result.data[permutation.axes[i]] = rhs.data[i];
    }
    return result;
}

ChunkAxisPermutation neighborAxisPermutation(Vertex vertex, ChunkDirection direction) {
    ChunkAxisPermutation result = IDENTITY_PERMUTATION;
    if (direction.sign == CoordSign.Plus) {
        result = vertexChunkAxisPermutations(vertex)[direction.axis];
    }
    return result;
}

CoordsWithMargins tuvToXyz(ubyte t, ubyte u, ubyte v, size_t tAxis) {
    CoordsWithMargins result;
    result.data[tAxis] = t;
    result.data[(tAxis + 1) % 3] = u;
    result.data[(tAxis + 2) % 3] = v;
    return result;
}

void fixMargins(ubyte dimension, Vertex vertex, VoxelData* voxels, ChunkDirection direction, VoxelData* neighborVoxels) {
    if (!(voxels.isSolid() && neighborVoxels.isSolid() && (voxels.get(0) == Material.Void) == (neighborVoxels.get(0) == Material.Void))) {
        ChunkAxisPermutation neighborPermutation = neighborAxisPermutation(vertex, direction);
        ubyte margin = marginCoord(dimension, direction.sign);
        ubyte boundary = boundaryCoordWithMargins(dimension, direction.sign);
        Material[] voxelData = voxels.dataMut(dimension);
        Material[] neighborVoxelData = neighborVoxels.dataMut(dimension);
        foreach (j; 0 .. dimension + 2) {
            foreach (i; 0 .. dimension + 2) {
                CoordsWithMargins boundaryCoords = tuvToXyz(boundary, clampToInterior(i, dimension), clampToInterior(j, dimension), direction.axis);
                CoordsWithMargins marginCoords = tuvToXyz(margin, cast(ubyte) i, cast(ubyte) j, direction.axis);
                size_t neighborBoundary = permuteCoordsWithMargins(neighborPermutation, boundaryCoords).toIndex(dimension);
                size_t neighborMargin = permuteCoordsWithMargins(neighborPermutation, marginCoords).toIndex(dimension);
                voxelData[marginCoords.toIndex(dimension)] = neighborVoxelData[neighborBoundary];
                neighborVoxelData[neighborMargin] = voxelData[boundaryCoords.toIndex(dimension)];
            }
        }
    }
}

void initializeMargins(ubyte dimension, VoxelData* voxels) {
    if (!voxels.isSolid()) {
        Material[] data = voxels.dataMut(dimension);
        foreach (direction; CHUNK_DIRECTIONS) {
            ubyte margin = marginCoord(dimension, direction.sign);
            ubyte boundary = boundaryCoordWithMargins(dimension, direction.sign);
            foreach (j; 0 .. dimension + 2) {
                foreach (i; 0 .. dimension + 2) {
                    CoordsWithMargins boundaryCoords = tuvToXyz(boundary, clampToInterior(i, dimension), clampToInterior(j, dimension), direction.axis);
                    CoordsWithMargins marginCoords = tuvToXyz(margin, cast(ubyte) i, cast(ubyte) j, direction.axis);
                    data[marginCoords.toIndex(dimension)] = data[boundaryCoords.toIndex(dimension)];
                }
            }
        }
    }
}
