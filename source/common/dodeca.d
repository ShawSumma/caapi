module common.dodeca;

import common.math : Matrix4, MIsometry, MVector, MPoint, MDirection, sqrt;
import common.voxel_math : ChunkAxisPermutation;

enum Side : ubyte {
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
}

enum Vertex : ubyte {
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
}

enum double BOUNDING_SPHERE_RADIUS_F64 = 1.2264568712514068;
enum float BOUNDING_SPHERE_RADIUS = cast(float) BOUNDING_SPHERE_RADIUS_F64;
enum double CHUNK_BOUNDING_SPHERE_RADIUS_F64 = BOUNDING_SPHERE_RADIUS_F64 * 0.5;
enum float CHUNK_BOUNDING_SPHERE_RADIUS = cast(float) CHUNK_BOUNDING_SPHERE_RADIUS_F64;

struct DodecaTables {
    MDirection!double[12] sideNormalsF64;
    MDirection!float[12] sideNormalsF32;
    MIsometry!double[12] reflectionsF64;
    MIsometry!float[12] reflectionsF32;
    bool[12][12] adjacent;
    Side[3][20] vertexCanonicalSidesData;
    Vertex[3][20] adjacentVerticesData;
    ChunkAxisPermutation[3][20] chunkAxisPermutationsData;
    MIsometry!double[20] dualToNodeF64;
    MIsometry!float[20] dualToNodeF32;
    MIsometry!double[20] nodeToDualF64;
    MIsometry!float[20] nodeToDualF32;
    double dualToChunkFactorF64;
    float dualToChunkFactorF32;
    double chunkToDualFactorF64;
    float chunkToDualFactorF32;
    MPoint!double[20] chunkBoundingSphereCentersF64;
    MPoint!float[20] chunkBoundingSphereCentersF32;
    bool[20] chunkToNodeParity;
    Vertex[12][12][12] sidesToVertex;
}

immutable DodecaTables tables = buildTables();

DodecaTables buildTables() {
    DodecaTables t;
    double phi = sqrt(1.25) + 0.5;
    MDirection!double templateNormal = MVector!double(1.0, phi, 0.0, sqrt(phi)).normalizedDirection();

    MDirection!double[4] signedNormals = [
        MDirection!double.newUnchecked(templateNormal[0], templateNormal[1], templateNormal[2], templateNormal[3]),
        MDirection!double.newUnchecked(-templateNormal[0], templateNormal[1], -templateNormal[2], templateNormal[3]),
        MDirection!double.newUnchecked(templateNormal[0], -templateNormal[1], -templateNormal[2], templateNormal[3]),
        MDirection!double.newUnchecked(-templateNormal[0], -templateNormal[1], templateNormal[2], templateNormal[3]),
    ];

    foreach (sideIdx; 0 .. 12) {
        MDirection!double sn = signedNormals[sideIdx / 3];
        size_t tAxis = (3 - sideIdx % 3) % 3;
        t.sideNormalsF64[sideIdx] = tuvToXyz(sn, tAxis);
    }

    foreach (i; 0 .. 12) {
        foreach (j; 0 .. 12) {
            double mipVal = t.sideNormalsF64[i].mip(t.sideNormalsF64[j]);
            t.adjacent[i][j] = mipVal > -0.5 && mipVal < 0.5;
        }
    }

    foreach (i; 0 .. 12) {
        t.reflectionsF64[i] = MIsometry!double.reflection(t.sideNormalsF64[i]);
    }

    size_t vIdx = 0;
    foreach (a; 0 .. 12) {
        foreach (b; a + 1 .. 12) {
            foreach (c; b + 1 .. 12) {
                if (t.adjacent[a][b] && t.adjacent[b][c] && t.adjacent[c][a]) {
                    t.vertexCanonicalSidesData[vIdx] = [cast(Side)a, cast(Side)b, cast(Side)c];
                    vIdx++;
                }
            }
        }
    }
    assert(vIdx == 20);

    foreach (i; 0 .. 12) {
        foreach (j; 0 .. 12) {
            foreach (k; 0 .. 12) {
                t.sidesToVertex[i][j][k] = cast(Vertex) 255;
            }
        }
    }

    foreach (vi; 0 .. 20) {
        Side[3] s = t.vertexCanonicalSidesData[vi];
        ubyte a = s[0];
        ubyte b = s[1];
        ubyte c = s[2];
        t.sidesToVertex[a][b][c] = cast(Vertex) vi;
        t.sidesToVertex[a][c][b] = cast(Vertex) vi;
        t.sidesToVertex[b][a][c] = cast(Vertex) vi;
        t.sidesToVertex[b][c][a] = cast(Vertex) vi;
        t.sidesToVertex[c][a][b] = cast(Vertex) vi;
        t.sidesToVertex[c][b][a] = cast(Vertex) vi;
    }

    double mipOriginNormal = MVector!double.origin().mip(t.sideNormalsF64[0].vec);
    foreach (vi; 0 .. 20) {
        Side[3] sides = t.vertexCanonicalSidesData[vi];
        MDirection!double na_ = t.sideNormalsF64[sides[0]];
        MDirection!double nb = t.sideNormalsF64[sides[1]];
        MDirection!double nc = t.sideNormalsF64[sides[2]];

        MPoint!double vertexPos = (MVector!double.origin() - (na_.vec + nb.vec + nc.vec) * mipOriginNormal).normalizedPoint();

        MDirection!double[3] dirs = [
            MDirection!double(-na_.vec),
            MDirection!double(-nb.vec),
            MDirection!double(-nc.vec),
        ];
        t.dualToNodeF64[vi] = MIsometry!double.fromColumnsUnchecked(dirs, vertexPos);
    }

    foreach (vi; 0 .. 20) {
        t.nodeToDualF64[vi] = t.dualToNodeF64[vi].inverse();
    }

    foreach (vi; 0 .. 20) {
        Side[3] canonical = t.vertexCanonicalSidesData[vi];
        foreach (axisIdx; 0 .. 3) {
            bool found = false;
            foreach (testSide; 0 .. 12) {
                if (cast(Side) testSide == canonical[axisIdx]) {
                    continue;
                }
                // Element-wise: copy-then-mutate static arrays alias in CTFE.
                Side[3] testSides;
                foreach (k; 0 .. 3) {
                    testSides[k] = k == axisIdx ? cast(Side) testSide : canonical[k];
                }
                Vertex v = t.sidesToVertex[testSides[0]][testSides[1]][testSides[2]];
                if (v != cast(Vertex) 255) {
                    t.adjacentVerticesData[vi][axisIdx] = v;
                    found = true;
                    break;
                }
            }
            assert(found);
        }
    }

    foreach (vi; 0 .. 20) {
        Side[3] canonical = t.vertexCanonicalSidesData[vi];
        foreach (axisIdx; 0 .. 3) {
            foreach (testSide; 0 .. 12) {
                if (cast(Side) testSide == canonical[axisIdx]) {
                    continue;
                }
                // Element-wise: copy-then-mutate static arrays alias in CTFE.
                Side[3] testSides;
                foreach (k; 0 .. 3) {
                    testSides[k] = k == axisIdx ? cast(Side) testSide : canonical[k];
                }
                Vertex adjV = t.sidesToVertex[testSides[0]][testSides[1]][testSides[2]];
                if (adjV != cast(Vertex) 255) {
                    t.chunkAxisPermutationsData[vi][axisIdx] = ChunkAxisPermutation.fromPermutation(
                        testSides, t.vertexCanonicalSidesData[adjV]
                    );
                    break;
                }
            }
        }
    }

    t.dualToChunkFactorF64 = sqrt(2.0 + sqrt(5.0));
    t.dualToChunkFactorF32 = cast(float) t.dualToChunkFactorF64;
    t.chunkToDualFactorF64 = 1.0 / t.dualToChunkFactorF64;
    t.chunkToDualFactorF32 = cast(float) t.chunkToDualFactorF64;

    foreach (i; 0 .. 12) {
        t.sideNormalsF32[i] = t.sideNormalsF64[i].toType!float();
        t.reflectionsF32[i] = t.reflectionsF64[i].toType!float();
    }
    foreach (vi; 0 .. 20) {
        t.dualToNodeF32[vi] = t.dualToNodeF64[vi].toType!float();
        t.nodeToDualF32[vi] = t.nodeToDualF64[vi].toType!float();
    }

    foreach (vi; 0 .. 20) {
        MPoint!double corner = t.dualToNodeF64[vi] * MPoint!double.origin();
        t.chunkBoundingSphereCentersF64[vi] = corner.midpoint(MPoint!double.origin());
        t.chunkBoundingSphereCentersF32[vi] = t.chunkBoundingSphereCentersF64[vi].toType!float();
    }

    foreach (vi; 0 .. 20) {
        t.chunkToNodeParity[vi] = t.dualToNodeF64[vi].parity();
    }
    return t;
}

MDirection!double tuvToXyz(MDirection!double n, size_t tAxis) {
    // Fresh output array: initializing it from `d` and writing in place hits
    // a CTFE aliasing bug where the copy shares storage with the source.
    double[4] d = n.vec.data;
    double[4] r;
    r[tAxis] = d[0];
    r[(tAxis + 1) % 3] = d[1];
    r[(tAxis + 2) % 3] = d[2];
    r[3] = d[3];
    return MDirection!double(MVector!double(r[0], r[1], r[2], r[3]));
}

ref const(MDirection!float) sideNormal(Side side) {
    return tables.sideNormalsF32[side];
}

ref const(MDirection!double) sideNormalF64(Side side) {
    return tables.sideNormalsF64[side];
}

ref const(MIsometry!float) sideReflection(Side side) {
    return tables.reflectionsF32[side];
}

ref const(MIsometry!double) sideReflectionF64(Side side) {
    return tables.reflectionsF64[side];
}

bool sideAdjacentTo(Side a, Side b) {
    return tables.adjacent[a][b];
}

bool sideIsFacing(Side side, const ref MPoint!float p) {
    float[4] r = tables.reflectionsF32[side].row(3);
    float dot = r[0] * p[0] + r[1] * p[1] + r[2] * p[2] + r[3] * p[3];
    return dot < p[3];
}

Side[3] vertexCanonicalSides(Vertex v) {
    return tables.vertexCanonicalSidesData[v];
}

Vertex[3] vertexAdjacentVertices(Vertex v) {
    return tables.adjacentVerticesData[v];
}

ref const(ChunkAxisPermutation[3]) vertexChunkAxisPermutations(Vertex v) {
    return tables.chunkAxisPermutationsData[v];
}

Vertex vertexFromThreeSides(Side[3] sides) {
    return tables.sidesToVertex[sides[0]][sides[1]][sides[2]];
}

ref const(MIsometry!float) vertexDualToNode(Vertex v) {
    return tables.dualToNodeF32[v];
}

ref const(MIsometry!double) vertexDualToNodeF64(Vertex v) {
    return tables.dualToNodeF64[v];
}

ref const(MIsometry!float) vertexNodeToDual(Vertex v) {
    return tables.nodeToDualF32[v];
}

ref const(MIsometry!double) vertexNodeToDualF64(Vertex v) {
    return tables.nodeToDualF64[v];
}

float vertexDualToChunkFactor() {
    return tables.dualToChunkFactorF32;
}

double vertexDualToChunkFactorF64() {
    return tables.dualToChunkFactorF64;
}

float vertexChunkToDualFactor() {
    return tables.chunkToDualFactorF32;
}

double vertexChunkToDualFactorF64() {
    return tables.chunkToDualFactorF64;
}

ref const(MPoint!float) vertexChunkBoundingSphereCenter(Vertex v) {
    return tables.chunkBoundingSphereCentersF32[v];
}

ref const(MPoint!double) vertexChunkBoundingSphereCenterF64(Vertex v) {
    return tables.chunkBoundingSphereCentersF64[v];
}

bool vertexParity(Vertex v) {
    return tables.chunkToNodeParity[v];
}

Matrix4!float vertexChunkToNode(Vertex v) {
    Matrix4!float dtn = tables.dualToNodeF32[v].mat;
    Matrix4!float scale = Matrix4!float.newScaling(1.0f / tables.dualToChunkFactorF32);
    return dtn * scale;
}

Matrix4!double vertexChunkToNodeF64(Vertex v) {
    Matrix4!double dtn = tables.dualToNodeF64[v].mat;
    Matrix4!double scale = Matrix4!double.newScaling(1.0 / tables.dualToChunkFactorF64);
    return dtn * scale;
}

Matrix4!float vertexNodeToChunk(Vertex v) {
    Matrix4!float scale = Matrix4!float.newScaling(tables.dualToChunkFactorF32);
    return scale * tables.nodeToDualF32[v].mat;
}

Matrix4!double vertexNodeToChunkF64(Vertex v) {
    Matrix4!double scale = Matrix4!double.newScaling(tables.dualToChunkFactorF64);
    return scale * tables.nodeToDualF64[v].mat;
}
