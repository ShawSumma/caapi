module common.margins;

import common.dodeca : Vertex, vertexChunkAxisPermutations;
import common.node : VoxelData;
import common.voxel_math : CHUNK_DIRECTIONS, ChunkAxisPermutation, ChunkDirection, CoordSign, Coords, IDENTITY_PERMUTATION;
import common.world : Material;

struct CoordsWithMargins {
    ubyte[3] data;

    size_t toIndex(ubyte chunkSize) const {
        size_t stride = chunkSize + 2;
        return data[0] + data[1] * stride + data[2] * stride * stride;
    }
}

enum ubyte TEST_DIMENSION = 4;

CoordsWithMargins withMargins(Coords coords) {
    CoordsWithMargins result;
    foreach (axis; 0 .. 3) {
        result.data[axis] = cast(ubyte)(coords.data[axis] + 1);
    }
    return result;
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

struct MarginFace {
    ChunkAxisPermutation permutation;
    ubyte dimension;
    ubyte axis;
    ubyte margin;
    ubyte boundary;

    CoordsWithMargins boundaryCell(size_t i, size_t j) const {
        return tuvToXyz(boundary, clampToInterior(i, dimension), clampToInterior(j, dimension), axis);
    }

    CoordsWithMargins marginCell(size_t i, size_t j) const {
        return tuvToXyz(margin, cast(ubyte) i, cast(ubyte) j, axis);
    }

    size_t neighborIndex(CoordsWithMargins coords) const {
        return permuteCoordsWithMargins(permutation, coords).toIndex(dimension);
    }
}

bool boundaryDiffersInVoidness(const(MarginFace)* face, const(VoxelData)* source, bool sourceIsNeighbor, bool voidness) {
    bool differs = false;
    if (source.isSolid()) {
        differs = (source.solidMaterial == Material.Void) != voidness;
    } else {
        foreach (j; 1 .. face.dimension + 1) {
            foreach (i; 1 .. face.dimension + 1) {
                size_t index = face.boundaryCell(i, j).toIndex(face.dimension);
                if (sourceIsNeighbor) {
                    index = face.neighborIndex(face.boundaryCell(i, j));
                }
                if ((source.get(index) == Material.Void) != voidness) {
                    differs = true;
                }
            }
        }
    }
    return differs;
}

bool needsMargin(const(MarginFace)* face, const(VoxelData)* target, const(VoxelData)* source, bool sourceIsNeighbor) {
    return !target.isSolid() || boundaryDiffersInVoidness(face, source, sourceIsNeighbor, target.solidMaterial == Material.Void);
}

void fixMargins(ubyte dimension, Vertex vertex, VoxelData* voxels, ChunkDirection direction, VoxelData* neighborVoxels) {
    MarginFace face = MarginFace(neighborAxisPermutation(vertex, direction), dimension, direction.axis, marginCoord(dimension, direction.sign), boundaryCoordWithMargins(dimension, direction.sign));
    bool writeOurs = needsMargin(&face, voxels, neighborVoxels, true);
    bool writeTheirs = needsMargin(&face, neighborVoxels, voxels, false);
    if (writeOurs) {
        voxels.dataMut(dimension);
    }
    if (writeTheirs) {
        neighborVoxels.dataMut(dimension);
    }
    if (writeOurs || writeTheirs) {
        foreach (j; 0 .. dimension + 2) {
            foreach (i; 0 .. dimension + 2) {
                CoordsWithMargins boundaryCoords = face.boundaryCell(i, j);
                CoordsWithMargins marginCoords = face.marginCell(i, j);
                if (writeOurs) {
                    voxels.denseData[marginCoords.toIndex(dimension)] = neighborVoxels.get(face.neighborIndex(boundaryCoords));
                }
                if (writeTheirs) {
                    neighborVoxels.denseData[face.neighborIndex(marginCoords)] = voxels.get(boundaryCoords.toIndex(dimension));
                }
            }
        }
    }
}

unittest {
    VoxelData stone = VoxelData.solid(Material.Granite);
    VoxelData dirt = VoxelData.solid(Material.Dirt);
    fixMargins(TEST_DIMENSION, Vertex.A, &stone, CHUNK_DIRECTIONS[0], &dirt);
    assert(stone.isSolid() && dirt.isSolid());
    VoxelData buried = VoxelData.solid(Material.Dirt);
    buried.dataMut(TEST_DIMENSION);
    initializeMargins(TEST_DIMENSION, &buried);
    fixMargins(TEST_DIMENSION, Vertex.A, &stone, CHUNK_DIRECTIONS[3], &buried);
    assert(stone.isSolid());
    VoxelData air = VoxelData.solid(Material.Void);
    fixMargins(TEST_DIMENSION, Vertex.A, &stone, CHUNK_DIRECTIONS[4], &air);
    assert(!stone.isSolid() && !air.isSolid());
    stone.release();
    air.release();
    buried.release();
}

bool marginFacesHaveVoid(ubyte dimension, const(VoxelData)* voxels) {
    bool found = false;
    if (!voxels.isSolid()) {
        foreach (direction; CHUNK_DIRECTIONS) {
            ubyte margin = marginCoord(dimension, direction.sign);
            foreach (j; 1 .. dimension + 1) {
                foreach (i; 1 .. dimension + 1) {
                    if (voxels.get(tuvToXyz(margin, cast(ubyte) i, cast(ubyte) j, direction.axis).toIndex(dimension)) == Material.Void) {
                        found = true;
                    }
                }
            }
        }
    }
    return found;
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
