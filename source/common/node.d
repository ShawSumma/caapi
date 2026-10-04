module common.node;

import core.stdc.math : floorf;
import core.stdc.stdlib : free, malloc;
import common.dodeca : Vertex, vertexDualToChunkFactor;
import common.graph : NodeId;
import common.margins : CoordsWithMargins, MarginFace, boundaryCoordWithMargins, clampToInterior, marginCoord, tuvToXyz;
import common.voxel_math : CHUNK_DIRECTIONS, ChunkDirection, Coords;
import common.world : Material;

enum int OUTSIDE_GRID = -1;
enum ubyte TEST_DIMENSION = 4;

struct ChunkId {
    NodeId node;
    Vertex vertex;
}

struct ChunkSlot {
    uint slot;
    Vertex vertex;
}

struct ChunkLayout {
    float dualToGridFactor;
    ubyte dimension;

    this(ubyte chunkDimension) {
        dimension = chunkDimension;
        dualToGridFactor = vertexDualToChunkFactor() * chunkDimension;
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
    Solid,
    Dense,
}

struct VoxelData {
    Material[] denseData;
    VoxelKind kind;
    Material solidMaterial;

    static VoxelData solid(Material material) {
        VoxelData result;
        result.kind = VoxelKind.Solid;
        result.solidMaterial = material;
        return result;
    }

    Material get(size_t index) const {
        if (kind == VoxelKind.Dense) {
            return denseData[index];
        } else {
            return solidMaterial;
        }
    }

    Material[] dataMut(ubyte dimension) {
        if (kind == VoxelKind.Solid) {
            size_t side = cast(size_t) dimension + 2;
            size_t count = side * side * side;
            Material* memory = cast(Material*) malloc(count * Material.sizeof);
            denseData = memory[0 .. count];
            foreach (i; 0 .. count) {
                denseData[i] = solidMaterial;
            }
            kind = VoxelKind.Dense;
        }
        return denseData;
    }

    bool isSolid() const {
        return kind == VoxelKind.Solid;
    }

    bool isSolidVoid() const {
        return kind == VoxelKind.Solid && solidMaterial == Material.Void;
    }

    bool isUniform(ubyte dimension) const {
        ubyte[3] origin = [0, 0, 0];
        Material first = get(Coords(origin).toIndex(dimension));
        foreach (x; 0 .. dimension) {
            foreach (y; 0 .. dimension) {
                foreach (z; 0 .. dimension) {
                    ubyte[3] coords = [cast(ubyte) x, cast(ubyte) y, cast(ubyte) z];
                    if (get(Coords(coords).toIndex(dimension)) != first) {
                        return false;
                    }
                }
            }
        }
        return true;
    }

    void compressUniform(ubyte dimension) {
        if (kind == VoxelKind.Dense && isUniform(dimension)) {
            ubyte[3] origin = [0, 0, 0];
            Material first = get(Coords(origin).toIndex(dimension));
            release();
            this = VoxelData.solid(first);
        }
    }

    void fixMargins(VoxelData* neighbor, ubyte dimension, Vertex vertex, ChunkDirection direction) {
        MarginFace face = MarginFace.make(dimension, vertex, direction);
        immutable bool isOursStale = face.isMarginStale(&this, neighbor, true);
        immutable bool isTheirsStale = face.isMarginStale(neighbor, &this, false);
        if (isOursStale) {
            dataMut(dimension);
        }
        if (isTheirsStale) {
            neighbor.dataMut(dimension);
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
            foreach (direction; CHUNK_DIRECTIONS) {
                ubyte margin = marginCoord(dimension, direction.sign);
                foreach (j; 1 .. dimension + 1) {
                    foreach (i; 1 .. dimension + 1) {
                        if (get(tuvToXyz(margin, cast(ubyte) i, cast(ubyte) j, direction.axis).toIndex(dimension)) == Material.Void) {
                            return true;
                        }
                    }
                }
            }
            return false;
        }
    }

    void initializeMargins(ubyte dimension) {
        if (!isSolid()) {
            Material[] data = dataMut(dimension);
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

    void release() {
        if (kind == VoxelKind.Dense) {
            free(denseData.ptr);
        }
        denseData = null;
        kind = VoxelKind.Solid;
    }
}

unittest {
    VoxelData stone = VoxelData.solid(Material.Granite);
    VoxelData dirt = VoxelData.solid(Material.Dirt);
    stone.fixMargins(&dirt, TEST_DIMENSION, Vertex.A, CHUNK_DIRECTIONS[0]);
    assert(stone.isSolid() && dirt.isSolid());
    VoxelData buried = VoxelData.solid(Material.Dirt);
    buried.dataMut(TEST_DIMENSION);
    buried.initializeMargins(TEST_DIMENSION);
    stone.fixMargins(&buried, TEST_DIMENSION, Vertex.A, CHUNK_DIRECTIONS[3]);
    assert(stone.isSolid());
    VoxelData air = VoxelData.solid(Material.Void);
    stone.fixMargins(&air, TEST_DIMENSION, Vertex.A, CHUNK_DIRECTIONS[4]);
    assert(!stone.isSolid() && !air.isSolid());
    stone.release();
    air.release();
    buried.release();
}

enum ChunkState : ubyte {
    Fresh,
    Generating,
    Populated,
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
