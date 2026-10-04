module common.node;

import core.stdc.math : floorf;
import core.stdc.stdlib : free, malloc;
import common.coords : CHUNK_DIRECTIONS, ChunkDirection, Coords;
import common.dodeca : VERTEX_COUNT, Vertex, vertexDualToChunkFactor;
import common.graph : NodeId;
import common.margins : CoordsWithMargins, MarginFace, boundaryCoordWithMargins, clampToInterior, marginCoord;
import common.material : Material;

enum int OUTSIDE_GRID = -1;
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
    float dualToGridFactor;
    ubyte dimension;

    static ChunkLayout fromDimension(ubyte dimension) {
        return ChunkLayout(vertexDualToChunkFactor() * dimension, dimension);
    }

    int dualToVoxel(float dualCoord) const {
        float floorGridCoord = floorf(dualCoord * dualToGridFactor);
        if (floorGridCoord >= 0.0f && floorGridCoord < cast(float) dimension) {
            return cast(int) floorGridCoord;
        } else {
            return OUTSIDE_GRID;
        }
    }

    float gridToDual(ubyte gridCoord) const {
        return cast(float) gridCoord / dualToGridFactor;
    }
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

    void fixMargins(ref VoxelData neighbor, ubyte dimension, Vertex vertex, ChunkDirection direction) {
        MarginFace face = MarginFace.make(dimension, vertex, direction);
        bool isOursStale = face.isMarginStale(this, neighbor, true);
        bool isTheirsStale = face.isMarginStale(neighbor, this, false);
        if (isOursStale) {
            toDense(dimension);
        }
        if (isTheirsStale) {
            neighbor.toDense(dimension);
        }
        if (isOursStale || isTheirsStale) {
            foreach (j; 0 .. dimension + 2) {
                foreach (i; 0 .. dimension + 2) {
                    CoordsWithMargins boundaryCoords = face.boundaryCell(i, j);
                    CoordsWithMargins marginCoords = face.marginCell(i, j);
                    if (isOursStale) {
                        denseData[marginCoords.toIndex(dimension)] = neighbor.get(face.neighborIndex(boundaryCoords));
                    }
                    if (isTheirsStale) {
                        neighbor.denseData[face.neighborIndex(marginCoords)] = get(boundaryCoords.toIndex(dimension));
                    }
                }
            }
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
    VoxelData stone = VoxelData.fromMaterial(Material.granite);
    VoxelData dirt = VoxelData.fromMaterial(Material.dirt);
    stone.fixMargins(dirt, TEST_DIMENSION, Vertex.a, CHUNK_DIRECTIONS[0]);
    assert(stone.isSolid() && dirt.isSolid());
    VoxelData buried = VoxelData.fromMaterial(Material.dirt);
    buried.toDense(TEST_DIMENSION);
    buried.initializeMargins(TEST_DIMENSION);
    stone.fixMargins(buried, TEST_DIMENSION, Vertex.a, CHUNK_DIRECTIONS[3]);
    assert(stone.isSolid());
    VoxelData air = VoxelData.fromMaterial(Material.none);
    stone.fixMargins(air, TEST_DIMENSION, Vertex.a, CHUNK_DIRECTIONS[4]);
    assert(!stone.isSolid() && !air.isSolid());
    stone.release();
    air.release();
    buried.release();
}

enum ChunkState : ubyte {
    fresh,
    generating,
    populated,
}

enum Occupancy : ubyte {
    unknown,
    full,
    empty,
}

struct Chunk {
    VoxelData voxels;
    ChunkState state;
    Occupancy predicted;
    bool hasDeferredMaterials;
    bool isQueued;
}
