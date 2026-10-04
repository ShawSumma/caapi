module client.meshing;

import core.stdc.stdlib : free, malloc;
import common.chunk_neighbors : AXIS_COUNT, cellOccupied, outsideInterior;
import common.graph : Graph;
import common.margins : CoordsWithMargins;
import common.node : ChunkSlot;
import common.world : Material;

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
}

struct ChunkCells {
    const(Material)[] padded;
    const(Graph)* graph;
    ChunkSlot chunk;
    ubyte dimension;

    bool occupied(int[3] voxel) const {
        CoordsWithMargins coords;
        uint outside = 0;
        foreach (axis; 0 .. AXIS_COUNT) {
            coords.data[axis] = cast(ubyte)(voxel[axis] + MARGIN_CELLS);
            if (outsideInterior(dimension, coords.data[axis])) {
                outside += 1;
            }
        }
        bool result = padded[coords.toIndex(dimension)] != Material.Void;
        if (outside > 1) {
            result = cellOccupied(graph, chunk, coords);
        }
        return result;
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

    const(Face)[] mesh(const(Graph)* graph, ChunkSlot chunk) {
        ChunkCells cells = ChunkCells(graph.nodeAt(chunk.slot).chunks[chunk.vertex].voxels.denseData, graph, chunk, graph.layout.dimension);
        return faces[0 .. extractFaces(&cells, faces)];
    }
}

size_t paddedCellCount(ubyte dimension) {
    size_t side = dimension + 2 * MARGIN_CELLS;
    return side * side * side;
}

uint maxFaces(ubyte dimension) {
    return AXIS_COUNT * (dimension * dimension * dimension + dimension * dimension);
}

uint[CORNERS_PER_FACE] faceOcclusion(const(ChunkCells)* cells, int[3] base, size_t axis) {
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
        bool occludedB = cells.occupied(edgeB);
        bool occludedC = cells.occupied(edgeC);
        result[corner] = 0;
        if (!(occludedB && occludedC)) {
            result[corner] = OCCLUSION_LEVELS - occludedB - occludedC - cells.occupied(diagonal);
        }
    }
    return result;
}

Face packFace(int[3] voxel, size_t axis, bool inward, Material material, uint[CORNERS_PER_FACE] occlusion) {
    uint axisCode = cast(uint) axis;
    if (inward) {
        axisCode += REVERSED_AXIS_OFFSET;
    }
    if (occlusion[1] + occlusion[2] > occlusion[0] + occlusion[3]) {
        axisCode += FLIPPED_DIAGONAL_OFFSET;
    }
    Face face;
    face.posAxis = cast(uint) voxel[0] | cast(uint) voxel[1] << COORD_BITS | cast(uint) voxel[2] << (2 * COORD_BITS) | axisCode << AXIS_SHIFT;
    face.occlusionMaterial = material;
    foreach (corner; 0 .. CORNERS_PER_FACE) {
        face.occlusionMaterial |= occlusion[corner] << (OCCLUSION_SHIFT + OCCLUSION_BITS * corner);
    }
    return face;
}

uint extractFaces(const(ChunkCells)* cells, Face* faces) {
    ubyte dimension = cells.dimension;
    size_t side = dimension + 2 * MARGIN_CELLS;
    size_t[AXIS_COUNT] strides = [1, side, side * side];
    const(Material)* padded = cells.padded.ptr;
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
                    bool selfVoid = padded[index] == Material.Void;
                    bool otherVoid = padded[index - step] == Material.Void;
                    if (selfVoid != otherVoid && !(selfVoid && a == dimension) && !(otherVoid && a == 0)) {
                        int[3] voxel;
                        voxel[axis] = cast(int) a;
                        voxel[bAxis] = cast(int) b;
                        voxel[cAxis] = cast(int) c;
                        int[3] base = voxel;
                        Material material = padded[index];
                        if (!selfVoid) {
                            base[axis] -= 1;
                        } else {
                            material = padded[index - step];
                        }
                        faces[count] = packFace(voxel, axis, selfVoid, material, faceOcclusion(cells, base, axis));
                        count += 1;
                    }
                }
            }
        }
    }
    return count;
}

unittest {
    Material[] padded = (cast(Material*) malloc(paddedCellCount(TEST_DIMENSION) * Material.sizeof))[0 .. paddedCellCount(TEST_DIMENSION)];
    padded[] = Material.Void;
    int[3] center = [TEST_CELL, TEST_CELL, TEST_CELL];
    ChunkCells cells = ChunkCells(padded, null, ChunkSlot.init, TEST_DIMENSION);
    size_t stride = TEST_DIMENSION + 2 * MARGIN_CELLS;
    padded[(TEST_CELL + MARGIN_CELLS) + (TEST_CELL + MARGIN_CELLS) * stride + (TEST_CELL + MARGIN_CELLS) * stride * stride] = Material.Granite;
    assert(cells.occupied(center));
    Face* faces = cast(Face*) malloc(maxFaces(TEST_DIMENSION) * Face.sizeof);
    uint count = extractFaces(&cells, faces);
    assert(count == 2 * AXIS_COUNT);
    uint[CORNERS_PER_FACE] unoccluded = OCCLUSION_LEVELS;
    foreach (face; faces[0 .. count]) {
        assert(face.occlusionMaterial == packFace(center, 0, false, Material.Granite, unoccluded).occlusionMaterial);
    }
    free(faces);
    free(padded.ptr);
}
