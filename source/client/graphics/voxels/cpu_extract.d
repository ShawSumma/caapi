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
    auto solid = (int x, int y, int z) {
        if (x < 0 || y < 0 || z < 0 || x >= dim || y >= dim || z >= dim) {
            return false;
        }
        return voxels[idx(x, y, z)] != 0;
    };

    for (int z = 0; z < cast(int)dim; z++) {
        for (int y = 0; y < cast(int)dim; y++) {
            for (int x = 0; x < cast(int)dim; x++) {
                bool here = solid(x, y, z);
                // For each axis a, emit a face if exactly one of (here, neighbor on -axis) is solid.
                // axis 0 = X, 1 = Y, 2 = Z
                static immutable int[3][3] dirs = [[1,0,0],[0,1,0],[0,0,1]];
                foreach (axis; 0 .. 3) {
                    int nx = x - dirs[axis][0];
                    int ny = y - dirs[axis][1];
                    int nz = z - dirs[axis][2];
                    bool there = solid(nx, ny, nz);
                    if (here == there) {
                        continue;
                    }
                    uint mat = here ? voxels[idx(x, y, z)] : voxels[idx(nx, ny, nz)];
                    bool reverse = there; // face points toward solid side
                    // Position of the face's voxel corner: we place at the solid voxel.
                    int fx = here ? x : nx;
                    int fy = here ? y : ny;
                    int fz = here ? z : nz;
                    // Surface struct expects the position of the negative neighbor for -axis faces.
                    // Following hypermine convention: store the position of the +X/+Y/+Z voxel.
                    int px = here ? x : x;
                    int py = here ? y : y;
                    int pz = here ? z : z;
                    cast(void) fx; cast(void) fy; cast(void) fz;
                    Surface s;
                    uint[4] occ = [3, 3, 3, 3];
                    Surface.pack(cast(uint) px, cast(uint) py, cast(uint) pz,
                                 cast(uint) axis, reverse, false, mat, occ,
                                 s.pos_axis, s.occlusion_mat);
                    out_ ~= s;
                }
            }
        }
    }
    return out_;
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
