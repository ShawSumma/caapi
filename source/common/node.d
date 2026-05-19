module common.node;

import common.chunks;
import common.dodeca;
import common.graph;
import common.voxel_math;
import common.world;
import std.math : floor;

struct ChunkId {
    NodeId node;
    Vertex vertex;
}

struct ChunkLayout {
    ubyte dimension;
    float dualToGridFactor;

    this(ubyte dim) {
        dimension = dim;
        dualToGridFactor = vertexDualToChunkFactor() * dim;
    }

    int dualToVoxel(float dualCoord) const {
        float floorGridCoord = _floor(dualCoord * dualToGridFactor);
        if (!(floorGridCoord >= 0.0f && floorGridCoord < cast(float) dimension)) {
            return -1;
        }
        return cast(int) floorGridCoord;
    }

    float gridToDual(ubyte gridCoord) const {
        return cast(float) gridCoord / dualToGridFactor;
    }

    static float _floor(float x) {
        return floor(x);
    }
}

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
            case Kind.Solid:
                return solidMaterial;
            case Kind.Dense:
                return denseData[index];
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

enum ChunkState { Fresh, Generating, Populated }

struct Chunk {
    ChunkState state = ChunkState.Fresh;
    VoxelData voxels;
    uint surface;
    uint oldSurface;
    uint generation;
}

struct Node {
    Chunks!Chunk chunks;
    void* state;
}
