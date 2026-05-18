module common.node;

import common.chunks;
import common.dodeca;
import common.graph;
import common.voxel_math;
import common.world;
import std.math : floor;

/// Unique identifier for a single chunk in the graph
struct ChunkId {
    NodeId node;
    Vertex vertex;
}

/// Contains the context needed to know the locations of individual cubes within a chunk
struct ChunkLayout {
    ubyte dimension;
    float dualToGridFactor;

    this(ubyte dim) {
        dimension = dim;
        dualToGridFactor = vertexDualToChunkFactor() * dim;
    }

    /// Converts a single coordinate from dual coordinates to an integer voxel coordinate
    int dualToVoxel(float dualCoord) const {
        float floorGridCoord = _floor(dualCoord * dualToGridFactor);
        if (!(floorGridCoord >= 0.0f && floorGridCoord < cast(float) dimension)) {
            return -1;
        }
        return cast(int) floorGridCoord;
    }

    /// Converts a single grid coordinate to dual coordinates
    float gridToDual(ubyte gridCoord) const {
        return cast(float) gridCoord / dualToGridFactor;
    }

    private static float _floor(float x) {
        return floor(x);
    }
}

/// Stores the voxel data of a chunk
struct VoxelData {
    enum Kind { Solid, Dense }
    Kind kind;
    Material solidMaterial;
    Material[] denseData;

    static VoxelData solid(Material mat) {
        VoxelData v;
        v.kind = Kind.Solid;
        v.solidMaterial = mat;
        return v;
    }

    static VoxelData dense(Material[] data) {
        VoxelData v;
        v.kind = Kind.Dense;
        v.denseData = data;
        return v;
    }

    Material get(size_t index) const {
        final switch (kind) {
            case Kind.Solid: return solidMaterial;
            case Kind.Dense: return denseData[index];
        }
    }

    Material[] dataMut(ubyte dimension) {
        if (kind == Kind.Solid) {
            size_t sz = (cast(size_t) dimension + 2) ^^ 3;
            denseData = new Material[sz];
            denseData[] = solidMaterial;
            kind = Kind.Dense;
        }
        return denseData;
    }

    bool isSolid() const {
        return kind == Kind.Solid;
    }
}

/// Chunk state enum
enum ChunkState { Fresh, Generating, Populated }

/// A single chunk within a node
struct Chunk {
    ChunkState state = ChunkState.Fresh;
    VoxelData voxels;
    uint surface;     // 0 = no surface
    uint oldSurface;  // 0 = no surface
}

/// A single dodecahedral node in the graph
struct Node {
    Chunks!Chunk chunks;
    void* state; // NodeState*, stored as void* to avoid circular imports
}
