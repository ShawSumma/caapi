module client.graphics.voxels.cpu_extract;

import client.graphics.voxels.surface : Surface;
import common.world : Material;
import common.dodeca : Vertex;
import common.node : VoxelData;
import common.worldgen.mod_ : ChunkParams, ChunkIncidentEnviroFactors, generateVoxels;

/// Generate packed Surface faces for a voxel grid. Voxel value 0 = empty, > 0 = material id.
/// Emits a face whenever a solid voxel has an empty neighbor in -X/-Y/-Z (matching extract.comp).
Surface[] cpuExtract(const(ubyte)[] voxels, uint dim) {
    Surface[] out_;
    auto idx = (int x, int y, int z) => x + y * cast(int)dim + z * cast(int)dim * cast(int)dim;
    auto getVoxel = (int x, int y, int z) {
        if (x < 0 || y < 0 || z < 0 || x >= dim || y >= dim || z >= dim) {
            return false;
        }
        return voxels[idx(x, y, z)] != 0;
    };

    static immutable int[3][3] uvs = [
        [1, 2, 0], // axis 0 (X): u=Y, v=Z
        [2, 0, 1], // axis 1 (Y): u=Z, v=X
        [0, 1, 2], // axis 2 (Z): u=X, v=Y
    ];

    for (int z = 0; z < cast(int)dim; z++) {
        for (int y = 0; y < cast(int)dim; y++) {
            for (int x = 0; x < cast(int)dim; x++) {
                bool here = getVoxel(x, y, z);
                static immutable int[3][3] dirs = [[1,0,0],[0,1,0],[0,0,1]];
                foreach (axis; 0 .. 3) {
                    int nx = x - dirs[axis][0];
                    int ny = y - dirs[axis][1];
                    int nz = z - dirs[axis][2];
                    bool there = getVoxel(nx, ny, nz);
                    if (here == there) {
                        continue;
                    }
                    uint mat = here ? voxels[idx(x, y, z)] : voxels[idx(nx, ny, nz)];
                    bool inward = here;
                    bool reverse = there;

                    // Compute occlusion matching hypermine's surface_occlusion
                    int[3] voxel = [x, y, z];
                    int[3] occBase = voxel;
                    if (!inward) {
                        occBase[axis] -= 1;
                    }

                    int uAxis = uvs[axis][0];
                    int vAxis = uvs[axis][1];
                    int[3] u = [0, 0, 0];
                    u[uAxis] = 1;
                    int[3] v = [0, 0, 0];
                    v[vAxis] = 1;

                    // 0 1 2
                    // 3 . 4
                    // 5 6 7
                    bool[8] occ;
                    occ[0] = getVoxel(occBase[0]-u[0]-v[0], occBase[1]-u[1]-v[1], occBase[2]-u[2]-v[2]);
                    occ[1] = getVoxel(occBase[0]     -v[0], occBase[1]     -v[1], occBase[2]     -v[2]);
                    occ[2] = getVoxel(occBase[0]+u[0]-v[0], occBase[1]+u[1]-v[1], occBase[2]+u[2]-v[2]);
                    occ[3] = getVoxel(occBase[0]-u[0]     , occBase[1]-u[1]     , occBase[2]-u[2]     );
                    occ[4] = getVoxel(occBase[0]+u[0]     , occBase[1]+u[1]     , occBase[2]+u[2]     );
                    occ[5] = getVoxel(occBase[0]-u[0]+v[0], occBase[1]-u[1]+v[1], occBase[2]-u[2]+v[2]);
                    occ[6] = getVoxel(occBase[0]     +v[0], occBase[1]     +v[1], occBase[2]     +v[2]);
                    occ[7] = getVoxel(occBase[0]+u[0]+v[0], occBase[1]+u[1]+v[1], occBase[2]+u[2]+v[2]);

                    uint[4] occResult = [
                        vertexOcclusion(occ[0], occ[1], occ[3]),
                        vertexOcclusion(occ[2], occ[1], occ[4]),
                        vertexOcclusion(occ[5], occ[6], occ[3]),
                        vertexOcclusion(occ[7], occ[6], occ[4]),
                    ];

                    bool flip = occResult[1] + occResult[2] > occResult[0] + occResult[3];
                    Surface s;
                    Surface.pack(cast(uint) x, cast(uint) y, cast(uint) z,
                                 cast(uint) axis, reverse, flip, mat, occResult,
                                 s.pos_axis, s.occlusion_mat);
                    out_ ~= s;
                }
            }
        }
    }
    return out_;
}

private uint vertexOcclusion(bool a, bool b, bool c) {
    if (b && c) {
        return 0;
    }
    return 3 - cast(uint)a - cast(uint)b - cast(uint)c;
}

/// Make a simple test voxel grid: a sphere of voxels in the middle of the chunk
/// with a few materials.
ubyte[] makeTestVoxels(uint dim) {
    // One cube-corner per chunk: three perpendicular voxel columns meeting at
    // the chunk's outer corner (where coords are low). Placed at coord 1 (not
    // 0) so the compute extractor's chunk-margin skip doesn't drop the outward
    // faces. Each chunk's "corner" sits at a dodecahedron vertex, producing
    // the honeycomb skeleton when the 20-chunks-per-node × N-nodes are drawn.
    auto data = new ubyte[dim * dim * dim];
    int N = cast(int) dim;
    for (int z = 0; z < N; z++) {
        for (int y = 0; y < N; y++) {
            for (int x = 0; x < N; x++) {
                int oneAxes = 0;
                if (x == 1) {
                    oneAxes++;
                }
                if (y == 1) {
                    oneAxes++;
                }
                if (z == 1) {
                    oneAxes++;
                }
                if (oneAxes >= 2) {
                    data[x + y * N + z * N * N] = 1;
                }
            }
        }
    }
    return data;
}
