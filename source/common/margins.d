module common.margins;

import core.stdc.stdlib : free, malloc;
import common.coords : CHUNK_DIRECTIONS, ChunkAxisPermutation, ChunkDirection, CoordSign, Coords, IDENTITY_PERMUTATION;
import common.dodeca : VERTEX_COUNT, Vertex, chunkAxisPermutations;
import common.material : Material;
import common.node : VoxelData;

struct CoordsWithMargins {
    ubyte[3] data;

    static CoordsWithMargins fromCoords(Coords coords) {
        CoordsWithMargins result;
        foreach (axis; 0 .. 3) {
            result.data[axis] = cast(ubyte)(coords.data[axis] + 1);
        }
        return result;
    }

    static CoordsWithMargins fromTuv(ubyte t, ubyte u, ubyte v, size_t tAxis) {
        CoordsWithMargins result;
        result.data[tAxis] = t;
        result.data[(tAxis + 1) % 3] = u;
        result.data[(tAxis + 2) % 3] = v;
        return result;
    }

    size_t toIndex(ubyte chunkSize) const {
        size_t stride = chunkSize + 2;
        return data[0] + data[1] * stride + data[2] * stride * stride;
    }
}

ubyte marginCoord(ubyte chunkSize, CoordSign sign) {
    if (sign == CoordSign.plus) {
        return cast(ubyte)(chunkSize + 1);
    } else {
        return 0;
    }
}

ubyte boundaryCoordWithMargins(ubyte chunkSize, CoordSign sign) {
    if (sign == CoordSign.plus) {
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
    if (direction.sign == CoordSign.plus) {
        return vertex.chunkAxisPermutations[direction.axis];
    } else {
        return IDENTITY_PERMUTATION;
    }
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
        return CoordsWithMargins.fromTuv(boundary, clampToInterior(i, dimension), clampToInterior(j, dimension), axis);
    }

    CoordsWithMargins marginCell(size_t i, size_t j) const {
        return CoordsWithMargins.fromTuv(margin, cast(ubyte) i, cast(ubyte) j, axis);
    }

    size_t neighborIndex(CoordsWithMargins coords) const {
        return permutation.apply(coords).toIndex(dimension);
    }
}

enum MarginList : ubyte {
    ownBoundary,
    ownMargin,
    theirBoundary,
    theirMargin,
}

enum uint MARGIN_LIST_COUNT = MarginList.max + 1;

struct MarginTables {
    ushort* indices;
    uint faceCells;
    ubyte dimension;

    static MarginTables make(ubyte dimension) {
        uint side = dimension + 2;
        MarginTables tables = MarginTables(null, side * side, dimension);
        tables.indices = cast(ushort*) malloc(cast(size_t) VERTEX_COUNT * CHUNK_DIRECTIONS.length * MARGIN_LIST_COUNT * tables.faceCells * ushort.sizeof);
        foreach (vertex; 0 .. VERTEX_COUNT) {
            foreach (direction; 0 .. CHUNK_DIRECTIONS.length) {
                MarginFace face = MarginFace.make(dimension, cast(Vertex) vertex, CHUNK_DIRECTIONS[direction]);
                ushort[] ownBoundary = tables.list(cast(Vertex) vertex, direction, MarginList.ownBoundary);
                ushort[] ownMargin = tables.list(cast(Vertex) vertex, direction, MarginList.ownMargin);
                ushort[] theirBoundary = tables.list(cast(Vertex) vertex, direction, MarginList.theirBoundary);
                ushort[] theirMargin = tables.list(cast(Vertex) vertex, direction, MarginList.theirMargin);
                foreach (j; 0 .. side) {
                    foreach (i; 0 .. side) {
                        size_t cell = i + j * side;
                        CoordsWithMargins boundary = face.boundaryCell(i, j);
                        CoordsWithMargins margin = face.marginCell(i, j);
                        ownBoundary[cell] = cast(ushort) boundary.toIndex(dimension);
                        ownMargin[cell] = cast(ushort) margin.toIndex(dimension);
                        theirBoundary[cell] = cast(ushort) face.neighborIndex(boundary);
                        theirMargin[cell] = cast(ushort) face.neighborIndex(margin);
                    }
                }
            }
        }
        return tables;
    }

    inout(ushort)[] list(Vertex vertex, size_t direction, MarginList kind) inout {
        size_t start = ((cast(size_t) vertex * CHUNK_DIRECTIONS.length + direction) * MARGIN_LIST_COUNT + kind) * faceCells;
        return indices[start .. start + faceCells];
    }

    bool isInterior(size_t cell) const {
        size_t side = dimension + 2;
        size_t i = cell % side;
        size_t j = cell / side;
        return i >= 1 && i <= dimension && j >= 1 && j <= dimension;
    }

    void release() {
        free(indices);
        indices = null;
    }
}

size_t directionIndex(ChunkDirection direction) {
    if (direction.sign == CoordSign.plus) {
        return direction.axis;
    } else {
        return direction.axis + 3;
    }
}

bool hasVoidnessOtherThan(ref const MarginTables tables, ref const VoxelData source, const(ushort)[] boundary, bool isVoid) {
    if (source.isSolid()) {
        return (source.solidMaterial == Material.none) != isVoid;
    } else {
        size_t cell = 0;
        while (cell < boundary.length && (!tables.isInterior(cell) || (source.denseData[boundary[cell]] == Material.none) == isVoid)) {
            cell += 1;
        }
        return cell < boundary.length;
    }
}

void copyMargin(ref VoxelData target, const(ushort)[] margin, ref const VoxelData source, const(ushort)[] boundary) {
    if (source.isSolid()) {
        foreach (cell; margin) {
            target.denseData[cell] = source.solidMaterial;
        }
    } else {
        foreach (cell, index; margin) {
            target.denseData[index] = source.denseData[boundary[cell]];
        }
    }
}
