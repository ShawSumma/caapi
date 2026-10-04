module common.node;

import core.stdc.math : floorf;
import core.stdc.stdlib : free, malloc;
import common.dodeca : VERTEX_COUNT, Vertex, vertexDualToChunkFactor;
import common.graph : NodeId;
import common.voxel_math : Coords;
import common.world : Material;
import common.worldgen.generation : NodeState;

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
        int result = -1;
        if (floorGridCoord >= 0.0f && floorGridCoord < cast(float) dimension) {
            result = cast(int) floorGridCoord;
        }
        return result;
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
        Material result = solidMaterial;
        if (kind == VoxelKind.Dense) {
            result = denseData[index];
        }
        return result;
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

    void release() {
        if (kind == VoxelKind.Dense) {
            free(denseData.ptr);
        }
        denseData = null;
        kind = VoxelKind.Solid;
    }
}

void compressUniform(VoxelData* voxels, ubyte dimension) {
    if (voxels.kind == VoxelKind.Dense) {
        ubyte[3] origin = [0, 0, 0];
        Material first = voxels.get(Coords(origin).toIndex(dimension));
        bool uniform = true;
        foreach (x; 0 .. dimension) {
            foreach (y; 0 .. dimension) {
                foreach (z; 0 .. dimension) {
                    ubyte[3] coords = [cast(ubyte) x, cast(ubyte) y, cast(ubyte) z];
                    if (voxels.get(Coords(coords).toIndex(dimension)) != first) {
                        uniform = false;
                    }
                }
            }
        }
        if (uniform) {
            voxels.release();
            *voxels = VoxelData.solid(first);
        }
    }
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
    bool materialsDeferred;
    bool queued;
}

struct Node {
    Chunk[VERTEX_COUNT] chunks;
    NodeState state;
    bool hasState;
}
