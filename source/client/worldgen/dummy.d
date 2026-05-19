module client.worldgen.dummy;

struct Vertex {
    float[3] pos;
    float[3] color;
}

struct CubeMesh {
    Vertex[] vertices;
    uint[] indices;
}

/// Generate cube geometry along the 12 edges of a chunk.
/// A voxel is included if at least two of its (x,y,z) coordinates are at a boundary.
CubeMesh generateChunkEdges(int chunkSize, float voxelSize) {
    CubeMesh mesh;

    // For each face: 4 corner positions (CCW seen from outside) and the face color.
    static immutable float[3][4][6] faceCorners = [
        // -z (back)
        [[0, 0, 0], [0, 1, 0], [1, 1, 0], [1, 0, 0]],
        // +z (front)
        [[0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]],
        // -y (bottom)
        [[0, 0, 0], [1, 0, 0], [1, 0, 1], [0, 0, 1]],
        // +y (top)
        [[0, 1, 0], [0, 1, 1], [1, 1, 1], [1, 1, 0]],
        // -x (left)
        [[0, 0, 0], [0, 0, 1], [0, 1, 1], [0, 1, 0]],
        // +x (right)
        [[1, 0, 0], [1, 1, 0], [1, 1, 1], [1, 0, 1]],
    ];
    static immutable float[3][6] faceColors = [
        [0.8f, 0.3f, 0.3f],
        [0.3f, 0.8f, 0.3f],
        [0.3f, 0.3f, 0.8f],
        [0.9f, 0.9f, 0.3f],
        [0.8f, 0.3f, 0.8f],
        [0.3f, 0.8f, 0.8f],
    ];

    int N = chunkSize;
    for (int x = 0; x < N; x++) {
        for (int y = 0; y < N; y++) {
            for (int z = 0; z < N; z++) {
                int boundaryCount = 0;
                if (x == 0 || x == N - 1) {
                    boundaryCount++;
                }
                if (y == 0 || y == N - 1) {
                    boundaryCount++;
                }
                if (z == 0 || z == N - 1) {
                    boundaryCount++;
                }
                if (boundaryCount < 2) {
                    continue;
                }

                float bx = x * voxelSize;
                float by = y * voxelSize;
                float bz = z * voxelSize;

                foreach (face; 0 .. 6) {
                    uint base = cast(uint) mesh.vertices.length;
                    float[3] color = faceColors[face];
                    foreach (corner; faceCorners[face]) {
                        Vertex v;
                        v.pos = [bx + corner[0] * voxelSize,
                                 by + corner[1] * voxelSize,
                                 bz + corner[2] * voxelSize];
                        v.color = color;
                        mesh.vertices ~= v;
                    }
                    mesh.indices ~= base + 0;
                    mesh.indices ~= base + 1;
                    mesh.indices ~= base + 2;
                    mesh.indices ~= base + 0;
                    mesh.indices ~= base + 2;
                    mesh.indices ~= base + 3;
                }
            }
        }
    }

    return mesh;
}
