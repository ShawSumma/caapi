module common.worldgen;

import std.math : floor;
import common.math : Matrix4, MVector;
import common.world : DIM, Material, voxelIndex;
import common.graph : Cube, State;

/// Generate voxels for a single cube. Pure function of the cube's transform, so
/// it is deterministic and thread-safe: it reads only `c.transform` and writes a
/// fresh voxel array, then publishes it.
void generate(Cube* c) {
    ushort[] v = new ushort[DIM * DIM * DIM];

    foreach (z; 0 .. DIM) {
        foreach (y; 0 .. DIM) {
            foreach (x; 0 .. DIM) {
                // Voxel center in cube-local coords, range roughly [-0.5, 0.5].
                float lx = (x + 0.5f) / DIM - 0.5f;
                float ly = (y + 0.5f) / DIM - 0.5f;
                float lz = (z + 0.5f) / DIM - 0.5f;

                // Map through the cube transform into the root frame so the world
                // is continuous across cube boundaries.
                MVector local = MVector(lx, ly, lz, 1.0f);
                MVector world = (c.transform * local).normalized();

                v[voxelIndex(x, y, z)] = cast(ushort) materialAt(world);
            }
        }
    }

    c.voxels = v;
}

/// Terrain material at a world point. A gently rolling surface (value noise)
/// separates air above from grass, dirt and stone below.
private Material materialAt(MVector p) {
    float x = p.data[0];
    float y = p.data[1];
    float z = p.data[2];

    float h = surfaceHeight(x, z);
    if (y > h) {
        return Material.Void;
    }
    if (y > h - 0.04f) {
        return Material.Grass;
    }
    if (y > h - 0.16f) {
        return Material.Dirt;
    }
    return Material.Stone;
}

private float surfaceHeight(float x, float z) {
    float h = 0;
    h += 0.12f * valueNoise(x * 1.7f, z * 1.7f);
    h += 0.06f * valueNoise(x * 3.9f + 11.0f, z * 3.9f - 7.0f);
    h += 0.03f * valueNoise(x * 8.3f - 5.0f, z * 8.3f + 3.0f);
    return h;
}

private float valueNoise(float x, float z) {
    int xi = cast(int) floor(x);
    int zi = cast(int) floor(z);
    float xf = x - xi;
    float zf = z - zi;
    float a = hashNoise(xi, zi);
    float b = hashNoise(xi + 1, zi);
    float c = hashNoise(xi, zi + 1);
    float d = hashNoise(xi + 1, zi + 1);
    float u = smooth(xf);
    float w = smooth(zf);
    return lerp(lerp(a, b, u), lerp(c, d, u), w);
}

private float smooth(float t) {
    return t * t * (3.0f - 2.0f * t);
}

private float lerp(float a, float b, float t) {
    return a + (b - a) * t;
}

private float hashNoise(int x, int z) {
    uint h = cast(uint)(x * 374761393) ^ cast(uint)(z * 668265263);
    h = (h ^ (h >> 13)) * 1274126177;
    h ^= h >> 16;
    return (h / cast(float) uint.max) * 2.0f - 1.0f;
}
