module unit.meshing;

import core.stdc.stdlib : free, malloc;
import client.meshing : CORNERS_PER_FACE, ChunkCells, OCCLUSION_LEVELS, Quad, WINDOW_BITS, WINDOW_SHIFT, maxQuads, paddedCellCount, paddedIndex;
import common.node : ChunkSlot;
import geometry.cube : AXIS_COUNT;
import plugins.api.api : Material;

enum ubyte DIMENSION = 4;
enum ubyte CELL = 2;

unittest {
    Material[] padded = (cast(Material*) malloc(paddedCellCount(DIMENSION)))[0 .. paddedCellCount(DIMENSION)];
    padded[] = Material.none;
    int[3] center = [CELL, CELL, CELL];
    ChunkCells cells = ChunkCells(padded.ptr, null, ChunkSlot.init, DIMENSION, false);
    padded[paddedIndex(DIMENSION, center)] = Material.granite;
    assert(cells.isOccupied(center));
    Quad* quads = cast(Quad*) malloc(maxQuads(DIMENSION) * Quad.sizeof);
    uint count = cells.extractQuads(quads);
    assert(count == 2 * AXIS_COUNT);
    uint[CORNERS_PER_FACE] unoccluded = OCCLUSION_LEVELS;
    foreach (quad; quads[0 .. count]) {
        uint window = (quad.occlusionMaterial >> WINDOW_SHIFT) & ((1u << WINDOW_BITS) - 1);
        assert(quad.occlusionMaterial == Quad.fromVoxel(center, 0, false, Material.granite, unoccluded, window).occlusionMaterial);
    }
    padded[paddedIndex(DIMENSION, [CELL - 1, CELL, CELL])] = Material.glass;
    uint glassCount = cells.extractQuads(quads);
    uint glassQuads = 0;
    foreach (quad; quads[0 .. glassCount]) {
        if ((quad.occlusionMaterial & ((1u << WINDOW_SHIFT) - 1)) == Material.glass) {
            glassQuads += 1;
        }
    }
    assert(glassCount == 2 * AXIS_COUNT + 2 * AXIS_COUNT - 1);
    assert(glassQuads == 2 * AXIS_COUNT - 1);
    free(quads);
    free(padded.ptr);
}
