module common.worldgen.mod_;

import common.dodeca;
import common.graph;
import common.margins;
import common.math;
import common.node;
import common.voxel_math;
import common.world;
import std.math;
import core.bitop : rol;

private enum NodeStateKind { Sky, DeepSky, Land, DeepLand }
private enum NodeStateRoad { East, DeepEast, West, DeepWest }

private enum float TERRAIN_SMOOTHNESS = 10.0f;

/// Contains minimal information about a node deduced from parents
struct PartialNodeState {
    // Placeholder - full implementation would include horosphere data
}

/// Contains all information about a node used for world generation
struct NodeState {
    private NodeStateKind kind;
    private NodeStateRoad roadState;
    private EnviroFactors enviro;
    private float[4] surfaceNormal = [0, 0, 1, 0];

    MVector!float upDirection() const {
        return MVector!float(surfaceNormal[0], surfaceNormal[1], surfaceNormal[2], surfaceNormal[3]);
    }
}

private struct EnviroFactors {
    float maxElevation = 0;
    float temperature = 0;
    float rainfall = 0;
    float blockiness = 0;
}

struct ChunkIncidentEnviroFactors {
    float[8] maxElevations;
    float[8] temperatures;
    float[8] rainfalls;
    float[8] blockinesses;
}

/// Data needed to generate a chunk
struct ChunkParams {
    ubyte dimension;
    Vertex chunk;
    ChunkIncidentEnviroFactors env;
    float[8] surfaceDists;
    bool isRoad;
    bool isRoadSupport;
    ulong nodeSpice;
}

/// Generate voxels for a chunk
VoxelData generateVoxels(const ref ChunkParams params) {
    auto voxels = VoxelData.solid(Material.Void);

    generateTerrain(params, voxels);
    initializeMargins(params.dimension, voxels);

    return voxels;
}

private void generateTerrain(const ref ChunkParams params, ref VoxelData voxels) {
    ubyte dim = params.dimension;

    // Simple terrain: check if close to surface
    float meMin = params.env.maxElevations[0];
    float meMax = params.env.maxElevations[0];
    foreach (me; params.env.maxElevations[1 .. $]) {
        if (me < meMin) meMin = me;
        if (me > meMax) meMax = me;
    }

    enum float ELEVATION_MARGIN = 0.7f;

    // Simple solid checks
    if (meMax / TERRAIN_SMOOTHNESS < -ELEVATION_MARGIN) {
        voxels = VoxelData.solid(Material.Void);
        return;
    }
    if (meMin / TERRAIN_SMOOTHNESS > ELEVATION_MARGIN) {
        voxels = VoxelData.solid(Material.Dirt);
        return;
    }

    // Full terrain generation
    foreach (x; 0 .. dim) {
        foreach (y; 0 .. dim) {
            foreach (z; 0 .. dim) {
                float[3] center = voxelCenter(dim, x, y, z);
                float[3] trilerpCoords = [
                    (1.0f - center[0]) * 0.5f,
                    (1.0f - center[1]) * 0.5f,
                    (1.0f - center[2]) * 0.5f,
                ];

                float elev = trilerp(params.env.maxElevations, trilerpCoords);
                float dist = elev / TERRAIN_SMOOTHNESS;

                if (dist >= 0.0f) {
                    auto mat = chooseMaterial(elev,
                        trilerp(params.env.rainfalls, trilerpCoords),
                        trilerp(params.env.temperatures, trilerpCoords),
                        dist);
                    size_t idx = index(dim, x, y, z);
                    voxels.dataMut(dim)[idx] = mat;
                }
            }
        }
    }
}

private Material chooseMaterial(float elev, float rain, float temp, float dist) {
    if (dist < 0.1f) {
        if (temp > 1.0f) return Material.Sand;
        if (rain > 1.0f) return Material.LushGrass;
        return Material.Grass;
    }
    if (dist < 0.3f) return Material.Dirt;
    if (elev > 5.0f) return Material.Granite;
    return Material.Limestone;
}

private float[3] voxelCenter(ubyte dimension, int x, int y, int z) {
    float d = cast(float) dimension;
    return [
        (cast(float) x + 0.5f) / d,
        (cast(float) y + 0.5f) / d,
        (cast(float) z + 0.5f) / d,
    ];
}

private size_t index(ubyte dimension, int x, int y, int z) {
    size_t lwm = dimension + 2;
    return (x + 1) + (y + 1) * lwm + (z + 1) * lwm * lwm;
}

/// Linearly interpolate at the interior of a cube given values at eight corners
float trilerp(const ref float[8] values, float[3] t) {
    float lerp(float v0, float v1, float s) { return v0 * (1.0f - s) + v1 * s; }
    float bilerp(float v00, float v01, float v10, float v11, float tx, float ty) {
        return lerp(lerp(v00, v01, tx), lerp(v10, v11, tx), ty);
    }
    return lerp(
        bilerp(values[0], values[4], values[2], values[6], t[0], t[1]),
        bilerp(values[1], values[5], values[3], values[7], t[0], t[1]),
        t[2]
    );
}

private ulong worldgenHash(ulong a, ulong b) {
    return (rol(a, 5) ^ b) * 0x517c_c1b7_2722_0a95;
}
