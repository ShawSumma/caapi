module client.mesher;

import common.world : DIM, Material, voxelIndex;

/// One vertex: cube-local position (range ~[-0.5,0.5]) plus an RGB color.
struct Vertex {
    float[3] pos;
    float[3] color;
}

private float[3] colorOf(Material m) {
    final switch (m) {
        case Material.Void:  return [0, 0, 0];
        case Material.Stone: return [0.55, 0.55, 0.58];
        case Material.Dirt:  return [0.45, 0.30, 0.16];
        case Material.Grass: return [0.30, 0.65, 0.25];
        case Material.Sand:  return [0.80, 0.74, 0.45];
        case Material.Water: return [0.20, 0.40, 0.80];
        case Material.Snow:  return [0.92, 0.95, 0.98];
    }
}

// Unit-cube face quads (two triangles each), per direction, as corner offsets.
private static immutable float[3][6] FACE_NORMALS = [
    [-1,0,0], [1,0,0], [0,-1,0], [0,1,0], [0,0,-1], [0,0,1],
];

/// Build a triangle list for one cube's exposed voxel faces. A face is emitted
/// when a solid voxel borders Void (or the cube edge). Positions are cube-local.
Vertex[] meshCube(const ushort[] voxels) {
    Vertex[] verts;
    if (voxels is null) {
        return verts;
    }

    float vs = 1.0f / DIM; // voxel size in local units

    bool solid(int x, int y, int z) {
        if (x < 0 || y < 0 || z < 0 || x >= DIM || y >= DIM || z >= DIM) {
            return false; // treat out-of-cube as air; margins handled by neighbors
        }
        return voxels[voxelIndex(x, y, z)] != Material.Void;
    }

    foreach (z; 0 .. DIM) {
        foreach (y; 0 .. DIM) {
            foreach (x; 0 .. DIM) {
                ushort m = voxels[voxelIndex(x, y, z)];
                if (m == Material.Void) {
                    continue;
                }
                float[3] col = colorOf(cast(Material) m);
                // local corner base
                float bx = x * vs - 0.5f;
                float by = y * vs - 0.5f;
                float bz = z * vs - 0.5f;

                static immutable int[3][6] dirs = [
                    [-1,0,0],[1,0,0],[0,-1,0],[0,1,0],[0,0,-1],[0,0,1],
                ];
                foreach (d; 0 .. 6) {
                    if (solid(x + dirs[d][0], y + dirs[d][1], z + dirs[d][2])) {
                        continue; // face hidden
                    }
                    emitFace(verts, bx, by, bz, vs, d, col);
                }
            }
        }
    }
    return verts;
}

private void emitFace(ref Vertex[] verts, float bx, float by, float bz,
                      float s, int dir, float[3] col) {
    // 4 corners of the face, wound CCW when viewed from outside.
    float[3][4] c;
    final switch (dir) {
        case 0: // -x
            c = [[bx, by, bz], [bx, by, bz+s], [bx, by+s, bz+s], [bx, by+s, bz]];
            break;
        case 1: // +x
            c = [[bx+s, by, bz], [bx+s, by+s, bz], [bx+s, by+s, bz+s], [bx+s, by, bz+s]];
            break;
        case 2: // -y
            c = [[bx, by, bz], [bx+s, by, bz], [bx+s, by, bz+s], [bx, by, bz+s]];
            break;
        case 3: // +y
            c = [[bx, by+s, bz], [bx, by+s, bz+s], [bx+s, by+s, bz+s], [bx+s, by+s, bz]];
            break;
        case 4: // -z
            c = [[bx, by, bz], [bx, by+s, bz], [bx+s, by+s, bz], [bx+s, by, bz]];
            break;
        case 5: // +z
            c = [[bx, by, bz+s], [bx+s, by, bz+s], [bx+s, by+s, bz+s], [bx, by+s, bz+s]];
            break;
    }
    // simple directional shading by face
    float shade = [0.7f, 0.85f, 0.55f, 1.0f, 0.65f, 0.9f][dir];
    float[3] sc = [col[0]*shade, col[1]*shade, col[2]*shade];
    verts ~= Vertex(c[0], sc);
    verts ~= Vertex(c[1], sc);
    verts ~= Vertex(c[2], sc);
    verts ~= Vertex(c[0], sc);
    verts ~= Vertex(c[2], sc);
    verts ~= Vertex(c[3], sc);
}
