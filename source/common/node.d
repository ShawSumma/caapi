module common.node;

import std.math : floor;
import common.chunks : Chunks;
import common.dodeca : Vertex, vertexDualToChunkFactor;
import common.graph : NodeId;
import common.world : Material;

struct ChunkId {
    NodeId node;
    Vertex vertex;

    bool opEquals(const ChunkId other) const {
        return node == other.node && vertex == other.vertex;
    }

    size_t toHash() const nothrow @safe {
        return cast(size_t)(node.value[0] + node.value[1] * 0x9E3779B97F4A7C15 + cast(ulong) vertex * 0x517CC1B727220A95);
    }
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
