module common.node;

import core.stdc.math : coshf, fabsf, floorf, logf, powf;
import core.stdc.stdlib : free, malloc;
import base.numbers : higherOf, lowerOf;
import common.graph : NodeId;
import common.material : MATERIAL_COUNT, Material, isSeeThrough;
import geometry.honeycomb : CORNER_COUNT, Corner, NODE_RADIUS, NODE_VOLUME, cubeScale;

enum int OUTSIDE_GRID = -1;
enum float DENSITY_EXPONENT = -4.0f / 3.0f;
enum ubyte VOLUME_TEST_DIMENSION = 12;
enum float MAX_VOLUME_SPREAD = 2.0f;
enum float GRID_TOLERANCE = 1e-3f;
enum float VOLUME_TOLERANCE = 1e-3f;
immutable float[3] GAUSS_POINTS = [-0.7745967f, 0.0f, 0.7745967f];
immutable float[3] GAUSS_WEIGHTS = [5.0f / 9.0f, 8.0f / 9.0f, 5.0f / 9.0f];
enum ubyte TEST_DIMENSION = 4;

struct ChunkId {
    NodeId node;
    Corner corner;
}

struct ChunkSlot {
    uint slot;
    Corner corner;

    static ChunkSlot fromIndex(size_t index) {
        return ChunkSlot(cast(uint)(index / CORNER_COUNT), cast(Corner)(index % CORNER_COUNT));
    }
}

// Where a cube's cell walls sit. Cube coordinates run from 0 at the corner to 1 at the node's center, and the corner
// frame's Klein coordinates are those scaled by the cube size. Cells shrink geometrically toward the center, where
// the Klein coordinates stretch space least, so that every cell holds about the same volume.
struct ChunkLayout {
    float kleinToCube;
    float cellRatio;
    float cubeSpan;
    ubyte dimension;

    static ChunkLayout make(ubyte dimension) {
        float cellRatio = powf(coshf(NODE_RADIUS), DENSITY_EXPONENT / dimension);
        return ChunkLayout(1 / cubeScale(), cellRatio, 1.0f - powf(cellRatio, dimension), dimension);
    }

    float gridToCube(float grid) const {
        return (1.0f - powf(cellRatio, grid)) / cubeSpan;
    }

    float cubeToGrid(float cube) const {
        float remaining = 1.0f - cube * cubeSpan;
        if (remaining > 0) {
            return logf(remaining) / logf(cellRatio);
        } else {
            return float.infinity;
        }
    }

    float gridToKlein(float grid) const {
        return gridToCube(grid) / kleinToCube;
    }

    float kleinToGrid(float klein) const {
        return cubeToGrid(klein * kleinToCube);
    }

    float[3] cellCenter(int[3] cell) const {
        return [cellCenterAlong(cell[0]), cellCenterAlong(cell[1]), cellCenterAlong(cell[2])];
    }

    float cellCenterAlong(int cell) const {
        return gridToCube(cell + 0.5f);
    }

    int kleinToCell(float klein) const {
        float grid = floorf(kleinToGrid(klein));
        if (grid >= 0.0f && grid < cast(float) dimension) {
            return cast(int) grid;
        } else {
            return OUTSIDE_GRID;
        }
    }
}

float kleinBoxVolume(float[3] low, float[3] high) {
    float[3] middle = [(low[0] + high[0]) / 2, (low[1] + high[1]) / 2, (low[2] + high[2]) / 2];
    float[3] half = [(high[0] - low[0]) / 2, (high[1] - low[1]) / 2, (high[2] - low[2]) / 2];
    float total = 0;
    foreach (i; 0 .. GAUSS_POINTS.length) {
        foreach (j; 0 .. GAUSS_POINTS.length) {
            foreach (k; 0 .. GAUSS_POINTS.length) {
                float x = middle[0] + half[0] * GAUSS_POINTS[i];
                float y = middle[1] + half[1] * GAUSS_POINTS[j];
                float z = middle[2] + half[2] * GAUSS_POINTS[k];
                float inside = 1.0f - x * x - y * y - z * z;
                total += GAUSS_WEIGHTS[i] * GAUSS_WEIGHTS[j] * GAUSS_WEIGHTS[k] / (inside * inside);
            }
        }
    }
    return total * half[0] * half[1] * half[2];
}

unittest {
    ChunkLayout layout = ChunkLayout.make(VOLUME_TEST_DIMENSION);
    float smallest = float.infinity;
    float largest = 0;
    float total = 0;
    foreach (x; 0 .. VOLUME_TEST_DIMENSION) {
        foreach (y; 0 .. VOLUME_TEST_DIMENSION) {
            foreach (z; 0 .. VOLUME_TEST_DIMENSION) {
                assert(fabsf(layout.cubeToGrid(layout.gridToCube(x)) - x) < GRID_TOLERANCE);
                float volume = kleinBoxVolume([layout.gridToKlein(x), layout.gridToKlein(y), layout.gridToKlein(z)], [layout.gridToKlein(x + 1), layout.gridToKlein(y + 1), layout.gridToKlein(z + 1)]);
                smallest = lowerOf(smallest, volume);
                largest = higherOf(largest, volume);
                total += volume;
            }
        }
    }
    assert(largest / smallest < MAX_VOLUME_SPREAD);
    assert(fabsf(total * CORNER_COUNT / NODE_VOLUME - 1) < VOLUME_TOLERANCE);
}

size_t cellCount(ubyte dimension) {
    return cast(size_t) dimension * dimension * dimension;
}

size_t cellIndex(ubyte dimension, uint x, uint y, uint z) {
    return x + dimension * (y + cast(size_t) dimension * z);
}

// A chunk's cells: either a pointer to all of them, or the one material that fills the chunk. No allocation lives
// below MATERIAL_COUNT, so a value that small is a fill material.
struct Voxels {
    size_t bits;

    static Voxels filled(Material material) {
        return Voxels(material);
    }

    bool isUniform() const {
        return bits < MATERIAL_COUNT;
    }

    bool isFilledWith(Material material) const {
        return bits == material;
    }

    // Chunks filled with something opaque show no faces of their own: every face on their border is drawn by the
    // see-through neighbor in front of it.
    bool isOpaqueFill() const {
        return isUniform() && !isSeeThrough(cast(Material) bits);
    }

    Material fill() const {
        assert(isUniform());
        return cast(Material) bits;
    }

    Material at(size_t index) const {
        if (isUniform()) {
            return cast(Material) bits;
        } else {
            return (cast(const(Material)*) bits)[index];
        }
    }

    const(Material)[] cells(ubyte dimension) const {
        assert(!isUniform());
        return (cast(const(Material)*) bits)[0 .. cellCount(dimension)];
    }

    Material[] toDense(ubyte dimension) {
        size_t count = cellCount(dimension);
        if (isUniform()) {
            Material* memory = cast(Material*) malloc(count);
            memory[0 .. count] = cast(Material) bits;
            bits = cast(size_t) memory;
        }
        return (cast(Material*) bits)[0 .. count];
    }

    void compress(ubyte dimension) {
        if (!isUniform()) {
            const(Material)[] all = cells(dimension);
            size_t index = 1;
            while (index < all.length && all[index] == all[0]) {
                index += 1;
            }
            if (index == all.length) {
                Material first = all[0];
                release();
                bits = first;
            }
        }
    }

    void release() {
        if (!isUniform()) {
            free(cast(void*) bits);
            bits = Material.none;
        }
    }
}

unittest {
    Voxels stone = Voxels.filled(Material.granite);
    assert(stone.isUniform() && stone.isOpaqueFill() && stone.at(5) == Material.granite);
    Material[] cells = stone.toDense(TEST_DIMENSION);
    assert(!stone.isUniform() && cells.length == cellCount(TEST_DIMENSION) && stone.at(5) == Material.granite);
    stone.compress(TEST_DIMENSION);
    assert(stone.isFilledWith(Material.granite));
    stone.toDense(TEST_DIMENSION)[cellIndex(TEST_DIMENSION, 1, 2, 3)] = Material.glass;
    stone.compress(TEST_DIMENSION);
    assert(!stone.isUniform() && stone.at(cellIndex(TEST_DIMENSION, 1, 2, 3)) == Material.glass);
    stone.release();
    assert(!Voxels.filled(Material.none).isOpaqueFill() && !Voxels.filled(Material.glass).isOpaqueFill());
}

enum ChunkState : ubyte {
    fresh,
    generating,
    populated,
    dropped,
}

enum Occupancy : ubyte {
    unknown,
    full,
    empty,
}

struct Chunk {
    Voxels voxels;
    ChunkState state;
    Occupancy predicted;
    bool hasDeferredMaterials;
    bool isQueued;
    bool isEdited;
}

static assert(Chunk.sizeof == 16);
