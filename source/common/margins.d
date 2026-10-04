module common.margins;

import common.dodeca : Vertex, chunkAxisPermutations;
import common.node : VoxelData;
import common.voxel_math : ChunkAxisPermutation, ChunkDirection, CoordSign, Coords, IDENTITY_PERMUTATION;
import common.world : Material;

struct CoordsWithMargins {
    ubyte[3] data;

    size_t toIndex(ubyte chunkSize) const {
        size_t stride = chunkSize + 2;
        return data[0] + data[1] * stride + data[2] * stride * stride;
    }
}

CoordsWithMargins withMargins(Coords coords) {
    CoordsWithMargins result;
    foreach (axis; 0 .. 3) {
        result.data[axis] = cast(ubyte)(coords.data[axis] + 1);
    }
    return result;
}

ubyte marginCoord(ubyte chunkSize, CoordSign sign) {
    if (sign == CoordSign.Plus) {
        return cast(ubyte)(chunkSize + 1);
    } else {
        return 0;
    }
}

ubyte boundaryCoordWithMargins(ubyte chunkSize, CoordSign sign) {
    if (sign == CoordSign.Plus) {
        return chunkSize;
    } else {
        return 1;
    }
}

ubyte clampToInterior(size_t index, ubyte dimension) {
    if (index < 1) {
        return 1;
    } else if (index > dimension) {
        return dimension;
    } else {
        return cast(ubyte) index;
    }
}

ChunkAxisPermutation neighborAxisPermutation(Vertex vertex, ChunkDirection direction) {
    if (direction.sign == CoordSign.Plus) {
        return vertex.chunkAxisPermutations[direction.axis];
    } else {
        return IDENTITY_PERMUTATION;
    }
}

CoordsWithMargins tuvToXyz(ubyte t, ubyte u, ubyte v, size_t tAxis) {
    CoordsWithMargins result;
    result.data[tAxis] = t;
    result.data[(tAxis + 1) % 3] = u;
    result.data[(tAxis + 2) % 3] = v;
    return result;
}

struct MarginFace {
    ChunkAxisPermutation permutation;
    ubyte dimension;
    ubyte axis;
    ubyte margin;
    ubyte boundary;

    static MarginFace make(ubyte dimension, Vertex vertex, ChunkDirection direction) {
        return MarginFace(neighborAxisPermutation(vertex, direction), dimension, direction.axis, marginCoord(dimension, direction.sign), boundaryCoordWithMargins(dimension, direction.sign));
    }

    CoordsWithMargins boundaryCell(size_t i, size_t j) const {
        return tuvToXyz(boundary, clampToInterior(i, dimension), clampToInterior(j, dimension), axis);
    }

    CoordsWithMargins marginCell(size_t i, size_t j) const {
        return tuvToXyz(margin, cast(ubyte) i, cast(ubyte) j, axis);
    }

    size_t neighborIndex(CoordsWithMargins coords) const {
        return permutation.apply(coords).toIndex(dimension);
    }

    size_t boundaryIndex(size_t i, size_t j, bool isNeighborSide) const {
        if (isNeighborSide) {
            return neighborIndex(boundaryCell(i, j));
        } else {
            return boundaryCell(i, j).toIndex(dimension);
        }
    }

    bool hasBoundaryVoidnessOtherThan(const(VoxelData)* source, bool isNeighborSide, bool isVoid) const {
        if (source.isSolid()) {
            return (source.solidMaterial == Material.Void) != isVoid;
        } else {
            foreach (j; 1 .. dimension + 1) {
                foreach (i; 1 .. dimension + 1) {
                    if ((source.get(boundaryIndex(i, j, isNeighborSide)) == Material.Void) != isVoid) {
                        return true;
                    }
                }
            }
            return false;
        }
    }

    bool isMarginStale(const(VoxelData)* target, const(VoxelData)* source, bool isSourceNeighbor) const {
        return !target.isSolid() || hasBoundaryVoidnessOtherThan(source, isSourceNeighbor, target.solidMaterial == Material.Void);
    }
}

