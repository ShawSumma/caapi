module unit.node;

import core.stdc.math : fabsf;
import base.numbers : higherOf, lowerOf;
import base.vector3 : Vec3;
import common.node : ChunkLayout, Voxels, cellCount, cellIndex;
import geometry.honeycomb : CORNER_COUNT;
import plugins.api.api : Material;
import unit.named : blockNamed;

enum ubyte LAYOUT_DIMENSION = 12;
enum ubyte VOXEL_DIMENSION = 4;
enum float NODE_VOLUME = 4.3062076f;
enum float MOST_VOLUME_SPREAD = 2.0f;
enum float GRID_TOLERANCE = 1e-3f;
enum float VOLUME_TOLERANCE = 1e-3f;
immutable float[3] GAUSS_POINTS = [-0.7745967f, 0.0f, 0.7745967f];
immutable float[3] GAUSS_WEIGHTS = [5.0f / 9.0f, 8.0f / 9.0f, 5.0f / 9.0f];

float kleinBoxVolume(Vec3!float low, Vec3!float high) {
    Vec3!float middle = Vec3!float((low.x + high.x) / 2, (low.y + high.y) / 2, (low.z + high.z) / 2);
    Vec3!float half = Vec3!float((high.x - low.x) / 2, (high.y - low.y) / 2, (high.z - low.z) / 2);
    float total = 0;
    foreach (i; 0 .. GAUSS_POINTS.length) {
        foreach (j; 0 .. GAUSS_POINTS.length) {
            foreach (k; 0 .. GAUSS_POINTS.length) {
                float x = middle.x + half.x * GAUSS_POINTS[i];
                float y = middle.y + half.y * GAUSS_POINTS[j];
                float z = middle.z + half.z * GAUSS_POINTS[k];
                float inside = 1.0f - x * x - y * y - z * z;
                total += GAUSS_WEIGHTS[i] * GAUSS_WEIGHTS[j] * GAUSS_WEIGHTS[k] / (inside * inside);
            }
        }
    }
    return total * half.x * half.y * half.z;
}

unittest {
    ChunkLayout layout = ChunkLayout.make(LAYOUT_DIMENSION);
    float smallest = 0;
    float largest = 0;
    float total = 0;
    foreach (x; 0 .. LAYOUT_DIMENSION) {
        foreach (y; 0 .. LAYOUT_DIMENSION) {
            foreach (z; 0 .. LAYOUT_DIMENSION) {
                assert(fabsf(layout.cubeToGrid(layout.gridToCube(x)) - x) < GRID_TOLERANCE);
                float volume = kleinBoxVolume(Vec3!float(layout.gridToKlein(x), layout.gridToKlein(y), layout.gridToKlein(z)), Vec3!float(layout.gridToKlein(x + 1), layout.gridToKlein(y + 1), layout.gridToKlein(z + 1)));
                if (x == 0 && y == 0 && z == 0) {
                    smallest = volume;
                }
                smallest = lowerOf(smallest, volume);
                largest = higherOf(largest, volume);
                total += volume;
            }
        }
    }
    assert(largest / smallest < MOST_VOLUME_SPREAD);
    assert(fabsf(total * CORNER_COUNT / NODE_VOLUME - 1) < VOLUME_TOLERANCE);
}

unittest {
    Voxels stone = Voxels.filled(blockNamed("base:granite"));
    assert(stone.isUniform() && stone.isOpaqueFill() && stone.at(5) == blockNamed("base:granite"));
    Material[] cells = stone.toDense(VOXEL_DIMENSION);
    assert(!stone.isUniform() && cells.length == cellCount(VOXEL_DIMENSION) && stone.at(5) == blockNamed("base:granite"));
    stone.compress(VOXEL_DIMENSION);
    assert(stone.isFilledWith(blockNamed("base:granite")));
    stone.toDense(VOXEL_DIMENSION)[cellIndex(VOXEL_DIMENSION, 1, 2, 3)] = blockNamed("base:glass");
    stone.compress(VOXEL_DIMENSION);
    assert(!stone.isUniform() && stone.at(cellIndex(VOXEL_DIMENSION, 1, 2, 3)) == blockNamed("base:glass"));
    stone.release();
    assert(!Voxels.filled(Material.none).isOpaqueFill() && !Voxels.filled(blockNamed("base:glass")).isOpaqueFill());
}
