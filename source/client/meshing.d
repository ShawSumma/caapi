module client.meshing;

import core.stdc.stdlib : free, malloc;
import core.stdc.string : memcpy;
import common.graph : Graph, NO_SLOT;
import common.material : Material, isShownAgainst;
import common.neighbors : acrossBorder, chunkNeighborSlot, indexIn, isCellOccupied, isOutside;
import common.node : Chunk, ChunkSlot, ChunkState, cellIndex;
import geometry.cube : AXIS_COUNT, DIRECTIONS, Sign, boundaryOf;

enum uint CORNERS_PER_FACE = 4;
enum uint OCCLUSION_LEVELS = 3;
enum uint COORD_BITS = 8;
enum uint AXIS_SHIFT = 3 * COORD_BITS;
enum uint OCCLUSION_SHIFT = 24;
enum uint OCCLUSION_BITS = 2;
enum uint REVERSED_BIT = 1 << 2;
enum uint FLIPPED_BIT = 1 << 3;
enum ubyte TEST_DIMENSION = 4;
enum ubyte TEST_CELL = 2;

// A face of a cell: its cell, the axis it faces along with whether it faces down that axis and which diagonal splits
// it, then its material and the shading at its four corners.
struct Quad {
    uint posAxis;
    uint occlusionMaterial;

    static Quad fromVoxel(int[3] voxel, size_t axis, bool isInward, Material material, uint[CORNERS_PER_FACE] occlusion) {
        uint axisCode = cast(uint) axis | (isInward ? REVERSED_BIT : 0) | (isDiagonalFlipped(occlusion) ? FLIPPED_BIT : 0);
        uint packed = material;
        foreach (corner; 0 .. CORNERS_PER_FACE) {
            packed |= occlusion[corner] << (OCCLUSION_SHIFT + OCCLUSION_BITS * corner);
        }
        return Quad(cast(uint) voxel[0] | cast(uint) voxel[1] << COORD_BITS | cast(uint) voxel[2] << (2 * COORD_BITS) | axisCode << AXIS_SHIFT, packed);
    }
}

// A chunk's cells with one more layer around each face, read from the neighbors. Only the layers across faces are
// filled; cells past an edge or a corner are only needed for shading, which asks the graph for them.
struct ChunkCells {
    const(Material)* padded;
    const(Graph)* graph;
    ChunkSlot chunk;
    ubyte dimension;
    bool isUniform;

    bool isOccupied(int[3] voxel) const {
        uint outside = 0;
        foreach (axis; 0 .. AXIS_COUNT) {
            if (isOutside(dimension, voxel[axis])) {
                outside += 1;
            }
        }
        if (outside > 1) {
            return (*graph).isCellOccupied(chunk, voxel);
        } else {
            return padded[paddedIndex(dimension, voxel)] != Material.none;
        }
    }

    uint[CORNERS_PER_FACE] faceOcclusion(int[3] base, size_t axis) const {
        size_t bAxis = (axis + 1) % AXIS_COUNT;
        size_t cAxis = (axis + 2) % AXIS_COUNT;
        uint[CORNERS_PER_FACE] result;
        foreach (corner; 0 .. CORNERS_PER_FACE) {
            int stepB = cast(int)(corner & 1) * 2 - 1;
            int stepC = cast(int)(corner >> 1) * 2 - 1;
            int[3] edgeB = base;
            edgeB[bAxis] += stepB;
            int[3] edgeC = base;
            edgeC[cAxis] += stepC;
            int[3] diagonal = edgeB;
            diagonal[cAxis] += stepC;
            result[corner] = cornerOcclusion(isOccupied(edgeB), isOccupied(edgeC), isOccupied(diagonal));
        }
        return result;
    }

    // Faces sit between neighboring cells along each axis; a uniform chunk has them only on its border.
    uint extractQuads(Quad* quads) const {
        size_t side = dimension + 2;
        size_t[AXIS_COUNT] strides = [1, side, side * side];
        uint stride = isUniform ? dimension : 1;
        uint count = 0;
        foreach (axis; 0 .. AXIS_COUNT) {
            size_t bAxis = (axis + 1) % AXIS_COUNT;
            size_t cAxis = (axis + 2) % AXIS_COUNT;
            size_t step = strides[axis];
            foreach (c; 0 .. dimension) {
                foreach (b; 0 .. dimension) {
                    size_t rowStart = (b + 1) * strides[bAxis] + (c + 1) * strides[cAxis] + step;
                    for (uint a = 0; a <= dimension; a += stride) {
                        size_t index = rowStart + a * step;
                        bool isSelfShown = isShownAgainst(padded[index], padded[index - step]);
                        bool isOtherShown = isShownAgainst(padded[index - step], padded[index]);
                        if ((isSelfShown && a > 0) || (isOtherShown && a < dimension)) {
                            int[3] voxel;
                            voxel[axis] = cast(int) a;
                            voxel[bAxis] = cast(int) b;
                            voxel[cAxis] = cast(int) c;
                            int[3] base = voxel;
                            base[axis] -= solidSideStep(isOtherShown);
                            quads[count] = Quad.fromVoxel(voxel, axis, isOtherShown, solidMaterial(index, step, isOtherShown), faceOcclusion(base, axis));
                            count += 1;
                        }
                    }
                }
            }
        }
        return count;
    }

    Material solidMaterial(size_t index, size_t step, bool isSelfVoid) const {
        if (isSelfVoid) {
            return padded[index - step];
        } else {
            return padded[index];
        }
    }
}

struct Mesher {
    Quad* quads;
    Material* padded;

    void setup(ubyte dimension) {
        quads = cast(Quad*) malloc(maxQuads(dimension) * Quad.sizeof);
        padded = cast(Material*) malloc(paddedCellCount(dimension));
    }

    void release() {
        free(quads);
        free(padded);
        quads = null;
        padded = null;
    }

    const(Quad)[] mesh(ref const Graph graph, ChunkSlot chunk) {
        pad(graph, chunk);
        ChunkCells cells = ChunkCells(padded, &graph, chunk, graph.layout.dimension, graph.chunks.at(chunk).voxels.isUniform());
        return quads[0 .. cells.extractQuads(quads)];
    }

    // A face against a neighbor that is not loaded yet is left out: the cell past it copies the one inside, and the
    // chunk is meshed again when the neighbor arrives.
    void pad(ref const Graph graph, ChunkSlot chunk) {
        ubyte dimension = graph.layout.dimension;
        const(Chunk)* own = graph.chunks.at(chunk);
        foreach (z; 0 .. dimension) {
            foreach (y; 0 .. dimension) {
                Material* row = padded + paddedIndex(dimension, [0, y, z]);
                if (own.voxels.isUniform()) {
                    row[0 .. dimension] = own.voxels.fill;
                } else {
                    memcpy(row, own.voxels.cells(dimension).ptr + cellIndex(dimension, 0, y, z), dimension);
                }
            }
        }
        foreach (direction; DIRECTIONS) {
            ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
            const(Chunk)* other = null;
            if (neighbor.slot != NO_SLOT && graph.chunks.at(neighbor).state == ChunkState.populated) {
                other = graph.chunks.at(neighbor);
            }
            size_t u = (direction.axis + 1) % AXIS_COUNT;
            size_t v = (direction.axis + 2) % AXIS_COUNT;
            int[3] past;
            past[direction.axis] = direction.sign == Sign.plus ? dimension : -1;
            int[3] inside;
            inside[direction.axis] = boundaryOf(dimension, direction.sign);
            foreach (j; 0 .. dimension) {
                foreach (i; 0 .. dimension) {
                    past[u] = i;
                    past[v] = j;
                    inside[u] = i;
                    inside[v] = j;
                    if (other is null) {
                        padded[paddedIndex(dimension, past)] = own.voxels.at(indexIn(dimension, inside));
                    } else {
                        padded[paddedIndex(dimension, past)] = other.voxels.at(indexIn(dimension, acrossBorder(dimension, chunk.corner, past, direction)));
                    }
                }
            }
        }
    }
}

size_t paddedIndex(ubyte dimension, int[3] cell) {
    size_t side = dimension + 2;
    return (cell[0] + 1) + (cell[1] + 1) * side + (cell[2] + 1) * side * side;
}

size_t paddedCellCount(ubyte dimension) {
    size_t side = dimension + 2;
    return side * side * side;
}

uint maxQuads(ubyte dimension) {
    return AXIS_COUNT * (dimension * dimension * dimension + dimension * dimension);
}

uint cornerOcclusion(bool isEdgeBOccupied, bool isEdgeCOccupied, bool isDiagonalOccupied) {
    if (isEdgeBOccupied && isEdgeCOccupied) {
        return 0;
    } else {
        return OCCLUSION_LEVELS - isEdgeBOccupied - isEdgeCOccupied - isDiagonalOccupied;
    }
}

// A quad is split along the diagonal joining its brighter pair of corners, so its shading runs evenly across.
bool isDiagonalFlipped(uint[CORNERS_PER_FACE] occlusion) {
    return occlusion[1] + occlusion[2] > occlusion[0] + occlusion[3];
}

int solidSideStep(bool isOtherShown) {
    if (isOtherShown) {
        return 0;
    } else {
        return 1;
    }
}

unittest {
    Material[] padded = (cast(Material*) malloc(paddedCellCount(TEST_DIMENSION)))[0 .. paddedCellCount(TEST_DIMENSION)];
    padded[] = Material.none;
    int[3] center = [TEST_CELL, TEST_CELL, TEST_CELL];
    ChunkCells cells = ChunkCells(padded.ptr, null, ChunkSlot.init, TEST_DIMENSION, false);
    padded[paddedIndex(TEST_DIMENSION, center)] = Material.granite;
    assert(cells.isOccupied(center));
    Quad* quads = cast(Quad*) malloc(maxQuads(TEST_DIMENSION) * Quad.sizeof);
    uint count = cells.extractQuads(quads);
    assert(count == 2 * AXIS_COUNT);
    uint[CORNERS_PER_FACE] unoccluded = OCCLUSION_LEVELS;
    foreach (quad; quads[0 .. count]) {
        assert(quad.occlusionMaterial == Quad.fromVoxel(center, 0, false, Material.granite, unoccluded).occlusionMaterial);
    }
    padded[paddedIndex(TEST_DIMENSION, [TEST_CELL - 1, TEST_CELL, TEST_CELL])] = Material.glass;
    uint glassCount = cells.extractQuads(quads);
    uint glassQuads = 0;
    foreach (quad; quads[0 .. glassCount]) {
        if ((quad.occlusionMaterial & ((1u << OCCLUSION_SHIFT) - 1)) == Material.glass) {
            glassQuads += 1;
        }
    }
    assert(glassCount == 2 * AXIS_COUNT + 2 * AXIS_COUNT - 1);
    assert(glassQuads == 2 * AXIS_COUNT - 1);
    free(quads);
    free(padded.ptr);
}
