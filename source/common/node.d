module common.node;

import core.stdc.math : coshf, fabsf, floorf, logf, powf;
import core.stdc.stdlib : free, malloc;
import common.coords : CHUNK_DIRECTIONS, ChunkDirection, Coords;
import common.dodeca : BOUNDING_SPHERE_RADIUS, NODE_VOLUME, VERTEX_COUNT, Vertex, vertexDualToChunkFactor;
import common.graph : NodeId;
import common.margins : CoordsWithMargins, MarginList, MarginTables, boundaryCoordWithMargins, clampToInterior, copyMargin, directionIndex, hasVoidnessOtherThan, marginCoord;
import common.material : Material;
import common.math : higherOf, lowerOf;

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
    Vertex vertex;
}

struct ChunkSlot {
    uint slot;
    Vertex vertex;

    static ChunkSlot fromIndex(size_t index) {
        return ChunkSlot(cast(uint)(index / VERTEX_COUNT), cast(Vertex)(index % VERTEX_COUNT));
    }
}

struct ChunkLayout {
    float dualToChunkFactor;
    float cellRatio;
    float chunkSpan;
    ubyte dimension;

    static ChunkLayout make(ubyte dimension) {
        float cellRatio = powf(coshf(BOUNDING_SPHERE_RADIUS), DENSITY_EXPONENT / dimension);
        return ChunkLayout(vertexDualToChunkFactor(), cellRatio, 1.0f - powf(cellRatio, dimension), dimension);
    }

    float gridToChunk(float gridCoord) const {
        return (1.0f - powf(cellRatio, gridCoord)) / chunkSpan;
    }

    float chunkToGrid(float chunkCoord) const {
        float remaining = 1.0f - chunkCoord * chunkSpan;
        if (remaining > 0) {
            return logf(remaining) / logf(cellRatio);
        } else {
            return float.infinity;
        }
    }

    float gridToDual(float gridCoord) const {
        return gridToChunk(gridCoord) / dualToChunkFactor;
    }

    float dualToGrid(float dualCoord) const {
        return chunkToGrid(dualCoord * dualToChunkFactor);
    }

    float[3] cellCenter(int[3] cell) const {
        return [cellCenterCoord(cell[0]), cellCenterCoord(cell[1]), cellCenterCoord(cell[2])];
    }

    float cellCenterCoord(int cell) const {
        return gridToChunk(cell + 0.5f);
    }

    int dualToVoxel(float dualCoord) const {
        float floorGridCoord = floorf(dualToGrid(dualCoord));
        if (floorGridCoord >= 0.0f && floorGridCoord < cast(float) dimension) {
            return cast(int) floorGridCoord;
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
                assert(fabsf(layout.chunkToGrid(layout.gridToChunk(x)) - x) < GRID_TOLERANCE);
                float volume = kleinBoxVolume([layout.gridToDual(x), layout.gridToDual(y), layout.gridToDual(z)], [layout.gridToDual(x + 1), layout.gridToDual(y + 1), layout.gridToDual(z + 1)]);
                smallest = lowerOf(smallest, volume);
                largest = higherOf(largest, volume);
                total += volume;
            }
        }
    }
    assert(largest / smallest < MAX_VOLUME_SPREAD);
    assert(fabsf(total * VERTEX_COUNT / NODE_VOLUME - 1) < VOLUME_TOLERANCE);
}

enum VoxelKind : ubyte {
    solid,
    dense,
}

Coords interiorCellAt(ubyte dimension, size_t cell) {
    size_t row = cell / dimension;
    return Coords([cast(ubyte)(cell % dimension), cast(ubyte)(row % dimension), cast(ubyte)(row / dimension)]);
}

CoordsWithMargins marginCellAt(ubyte dimension, size_t cell) {
    size_t faceCells = cast(size_t) dimension * dimension;
    ChunkDirection direction = CHUNK_DIRECTIONS[cell / faceCells];
    size_t inFace = cell % faceCells;
    return CoordsWithMargins.fromTuv(marginCoord(dimension, direction.sign), cast(ubyte)(inFace % dimension + 1), cast(ubyte)(inFace / dimension + 1), direction.axis);
}

struct VoxelData {
    Material[] denseData;
    VoxelKind kind;
    Material solidMaterial;

    static VoxelData fromMaterial(Material material) {
        return VoxelData(null, VoxelKind.solid, material);
    }

    Material get(size_t index) const {
        if (kind == VoxelKind.dense) {
            return denseData[index];
        } else {
            return solidMaterial;
        }
    }

    Material[] toDense(ubyte dimension) {
        if (kind == VoxelKind.solid) {
            size_t side = cast(size_t) dimension + 2;
            size_t count = side * side * side;
            Material* memory = cast(Material*) malloc(count * Material.sizeof);
            denseData = memory[0 .. count];
            foreach (i; 0 .. count) {
                denseData[i] = solidMaterial;
            }
            kind = VoxelKind.dense;
        }
        return denseData;
    }

    bool isSolid() const {
        return kind == VoxelKind.solid;
    }

    bool isSolidVoid() const {
        return kind == VoxelKind.solid && solidMaterial == Material.none;
    }

    bool isUniform(ubyte dimension) const {
        Material first = get(Coords.init.toIndex(dimension));
        size_t cellCount = cast(size_t) dimension * dimension * dimension;
        size_t cell = 0;
        while (cell < cellCount && get(interiorCellAt(dimension, cell).toIndex(dimension)) == first) {
            cell += 1;
        }
        return cell == cellCount;
    }

    void compressUniform(ubyte dimension) {
        if (kind == VoxelKind.dense && isUniform(dimension)) {
            Material first = get(Coords.init.toIndex(dimension));
            release();
            this = VoxelData.fromMaterial(first);
        }
    }

    void fixMargins(ref VoxelData neighbor, ref const MarginTables tables, Vertex vertex, ChunkDirection direction) {
        size_t index = directionIndex(direction);
        const(ushort)[] ownBoundary = tables.list(vertex, index, MarginList.ownBoundary);
        const(ushort)[] theirBoundary = tables.list(vertex, index, MarginList.theirBoundary);
        bool isOursStale = !isSolid() || tables.hasVoidnessOtherThan(neighbor, theirBoundary, solidMaterial == Material.none);
        bool isTheirsStale = !neighbor.isSolid() || tables.hasVoidnessOtherThan(this, ownBoundary, neighbor.solidMaterial == Material.none);
        if (isOursStale) {
            toDense(tables.dimension);
        }
        if (isTheirsStale) {
            neighbor.toDense(tables.dimension);
        }
        if (isOursStale) {
            copyMargin(this, tables.list(vertex, index, MarginList.ownMargin), neighbor, theirBoundary);
        }
        if (isTheirsStale) {
            copyMargin(neighbor, tables.list(vertex, index, MarginList.theirMargin), this, ownBoundary);
        }
    }

    bool hasVoidInMargins(ubyte dimension) const {
        if (isSolid()) {
            return false;
        } else {
            size_t cellCount = CHUNK_DIRECTIONS.length * dimension * dimension;
            size_t cell = 0;
            while (cell < cellCount && get(marginCellAt(dimension, cell).toIndex(dimension)) != Material.none) {
                cell += 1;
            }
            return cell < cellCount;
        }
    }

    void initializeMargins(ubyte dimension) {
        if (!isSolid()) {
            Material[] data = toDense(dimension);
            foreach (direction; CHUNK_DIRECTIONS) {
                ubyte margin = marginCoord(dimension, direction.sign);
                ubyte boundary = boundaryCoordWithMargins(dimension, direction.sign);
                foreach (j; 0 .. dimension + 2) {
                    foreach (i; 0 .. dimension + 2) {
                        CoordsWithMargins boundaryCoords = CoordsWithMargins.fromTuv(boundary, clampToInterior(i, dimension), clampToInterior(j, dimension), direction.axis);
                        CoordsWithMargins marginCoords = CoordsWithMargins.fromTuv(margin, cast(ubyte) i, cast(ubyte) j, direction.axis);
                        data[marginCoords.toIndex(dimension)] = data[boundaryCoords.toIndex(dimension)];
                    }
                }
            }
        }
    }

    void release() {
        if (kind == VoxelKind.dense) {
            free(denseData.ptr);
        }
        denseData = null;
        kind = VoxelKind.solid;
    }
}

unittest {
    MarginTables tables = MarginTables.make(TEST_DIMENSION);
    VoxelData stone = VoxelData.fromMaterial(Material.granite);
    VoxelData dirt = VoxelData.fromMaterial(Material.dirt);
    stone.fixMargins(dirt, tables, Vertex.a, CHUNK_DIRECTIONS[0]);
    assert(stone.isSolid() && dirt.isSolid());
    VoxelData buried = VoxelData.fromMaterial(Material.dirt);
    buried.toDense(TEST_DIMENSION);
    buried.initializeMargins(TEST_DIMENSION);
    stone.fixMargins(buried, tables, Vertex.a, CHUNK_DIRECTIONS[3]);
    assert(stone.isSolid());
    VoxelData empty = VoxelData.fromMaterial(Material.none);
    stone.fixMargins(empty, tables, Vertex.a, CHUNK_DIRECTIONS[4]);
    assert(!stone.isSolid() && !empty.isSolid());
    stone.release();
    empty.release();
    buried.release();
    tables.release();
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

// Set only while a batch of arrived chunks is joined to its neighbors.
enum Integration : ubyte {
    none,
    populating,
    restoring,
    adjacent,
}

struct Chunk {
    VoxelData voxels;
    ChunkState state;
    Occupancy predicted;
    Integration integration;
    bool hasDeferredMaterials;
    bool isQueued;
    bool isEdited;
}

bool isArriving(Integration integration) {
    return integration == Integration.populating || integration == Integration.restoring;
}
