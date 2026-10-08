module client.meshing;

import core.stdc.stdlib : free, malloc;
import common.graph : Graph;
import common.margins : CoordsWithMargins;
import common.material : Material;
import common.neighbors : AXIS_COUNT, isCellOccupied, isOutsideInterior;
import common.node : ChunkSlot;

enum uint CORNERS_PER_FACE = 4;
enum uint OCCLUSION_LEVELS = 3;
enum uint COORD_BITS = 8;
enum uint AXIS_SHIFT = 3 * COORD_BITS;
enum uint OCCLUSION_SHIFT = 24;
enum uint OCCLUSION_BITS = 2;
enum uint REVERSED_AXIS_OFFSET = AXIS_COUNT;
enum uint FLIPPED_DIAGONAL_OFFSET = 2 * AXIS_COUNT;
enum int MARGIN_CELLS = 1;
enum ubyte TEST_DIMENSION = 4;
enum ubyte TEST_CELL = 2;

struct Face {
    uint posAxis;
    uint occlusionMaterial;

    static Face fromVoxel(int[3] voxel, size_t axis, bool isInward, Material material, uint[CORNERS_PER_FACE] occlusion) {
        uint axisCode = cast(uint) axis + reversedOffset(isInward) + flippedOffset(occlusion);
        uint packed = material;
        foreach (corner; 0 .. CORNERS_PER_FACE) {
            packed |= occlusion[corner] << (OCCLUSION_SHIFT + OCCLUSION_BITS * corner);
        }
        return Face(cast(uint) voxel[0] | cast(uint) voxel[1] << COORD_BITS | cast(uint) voxel[2] << (2 * COORD_BITS) | axisCode << AXIS_SHIFT, packed);
    }
}

struct ChunkCells {
    const(Material)[] padded;
    const(Graph)* graph;
    ChunkSlot chunk;
    ubyte dimension;

    bool isOccupied(int[3] voxel) const {
        CoordsWithMargins coords;
        uint outside = 0;
        foreach (axis; 0 .. AXIS_COUNT) {
            coords.data[axis] = cast(ubyte)(voxel[axis] + MARGIN_CELLS);
            if (isOutsideInterior(dimension, coords.data[axis])) {
                outside += 1;
            }
        }
        if (outside > 1) {
            return (*graph).isCellOccupied(chunk, coords);
        } else {
            return padded[coords.toIndex(dimension)] != Material.none;
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

    uint extractFaces(Face* faces) const {
        size_t side = dimension + 2 * MARGIN_CELLS;
        size_t[AXIS_COUNT] strides = [1, side, side * side];
        uint count = 0;
        foreach (axis; 0 .. AXIS_COUNT) {
            size_t bAxis = (axis + 1) % AXIS_COUNT;
            size_t cAxis = (axis + 2) % AXIS_COUNT;
            size_t step = strides[axis];
            foreach (c; 0 .. dimension) {
                foreach (b; 0 .. dimension) {
                    size_t rowStart = (b + MARGIN_CELLS) * strides[bAxis] + (c + MARGIN_CELLS) * strides[cAxis] + MARGIN_CELLS * step;
                    foreach (a; 0 .. dimension + 1) {
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
                            faces[count] = Face.fromVoxel(voxel, axis, isOtherShown, solidMaterial(index, step, isOtherShown), faceOcclusion(base, axis));
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
    Face* faces;

    void setup(ubyte dimension) {
        faces = cast(Face*) malloc(maxFaces(dimension) * Face.sizeof);
    }

    void release() {
        free(faces);
        faces = null;
    }

    const(Face)[] mesh(ref const Graph graph, ChunkSlot chunk) {
        ChunkCells cells = ChunkCells(graph.chunkAt(chunk).voxels.denseData, &graph, chunk, graph.layout.dimension);
        return faces[0 .. cells.extractFaces(faces)];
    }
}

size_t paddedCellCount(ubyte dimension) {
    size_t side = dimension + 2 * MARGIN_CELLS;
    return side * side * side;
}

uint maxFaces(ubyte dimension) {
    return AXIS_COUNT * (dimension * dimension * dimension + dimension * dimension);
}

uint cornerOcclusion(bool isEdgeBOccupied, bool isEdgeCOccupied, bool isDiagonalOccupied) {
    if (isEdgeBOccupied && isEdgeCOccupied) {
        return 0;
    } else {
        return OCCLUSION_LEVELS - isEdgeBOccupied - isEdgeCOccupied - isDiagonalOccupied;
    }
}

uint reversedOffset(bool isInward) {
    if (isInward) {
        return REVERSED_AXIS_OFFSET;
    } else {
        return 0;
    }
}

uint flippedOffset(uint[CORNERS_PER_FACE] occlusion) {
    if (occlusion[1] + occlusion[2] > occlusion[0] + occlusion[3]) {
        return FLIPPED_DIAGONAL_OFFSET;
    } else {
        return 0;
    }
}

int solidSideStep(bool isOtherShown) {
    if (isOtherShown) {
        return 0;
    } else {
        return 1;
    }
}

bool isSeeThrough(Material material) {
    return material == Material.none || material == Material.glass;
}

bool isShownAgainst(Material material, Material beside) {
    return material != Material.none && isSeeThrough(beside) && !(material == Material.glass && beside == Material.glass);
}

unittest {
    Material[] padded = (cast(Material*) malloc(paddedCellCount(TEST_DIMENSION) * Material.sizeof))[0 .. paddedCellCount(TEST_DIMENSION)];
    padded[] = Material.none;
    int[3] center = [TEST_CELL, TEST_CELL, TEST_CELL];
    ChunkCells cells = ChunkCells(padded, null, ChunkSlot.init, TEST_DIMENSION);
    size_t stride = TEST_DIMENSION + 2 * MARGIN_CELLS;
    padded[(TEST_CELL + MARGIN_CELLS) + (TEST_CELL + MARGIN_CELLS) * stride + (TEST_CELL + MARGIN_CELLS) * stride * stride] = Material.granite;
    assert(cells.isOccupied(center));
    Face* faces = cast(Face*) malloc(maxFaces(TEST_DIMENSION) * Face.sizeof);
    uint count = cells.extractFaces(faces);
    assert(count == 2 * AXIS_COUNT);
    uint[CORNERS_PER_FACE] unoccluded = OCCLUSION_LEVELS;
    foreach (face; faces[0 .. count]) {
        assert(face.occlusionMaterial == Face.fromVoxel(center, 0, false, Material.granite, unoccluded).occlusionMaterial);
    }
    padded[(TEST_CELL - 1 + MARGIN_CELLS) + (TEST_CELL + MARGIN_CELLS) * stride + (TEST_CELL + MARGIN_CELLS) * stride * stride] = Material.glass;
    uint glassCount = cells.extractFaces(faces);
    uint glassFaces = 0;
    foreach (face; faces[0 .. glassCount]) {
        if ((face.occlusionMaterial & ((1u << OCCLUSION_SHIFT) - 1)) == Material.glass) {
            glassFaces += 1;
        }
    }
    assert(glassCount == 2 * AXIS_COUNT + 2 * AXIS_COUNT - 1);
    assert(glassFaces == 2 * AXIS_COUNT - 1);
    free(faces);
    free(padded.ptr);
}
