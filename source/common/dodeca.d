module common.dodeca;

import std.math : sqrt;
import common.math : Matrix4, MIsometry, MVector, MPoint, MDirection;
import common.voxel_math : ChunkAxisPermutation;

enum Side : ubyte {
    A, B, C, D, E, F, G, H, I, J, K, L,
}

enum Vertex : ubyte {
    A, B, C, D, E, F, G, H, I, J,
    K, L, M, N, O, P, Q, R, S, T,
}

enum double BOUNDING_SPHERE_RADIUS_F64 = 1.2264568712514068;
enum float BOUNDING_SPHERE_RADIUS = cast(float) BOUNDING_SPHERE_RADIUS_F64;
enum double CHUNK_BOUNDING_SPHERE_RADIUS_F64 = BOUNDING_SPHERE_RADIUS_F64 * 0.5;
enum float CHUNK_BOUNDING_SPHERE_RADIUS = cast(float) CHUNK_BOUNDING_SPHERE_RADIUS_F64;

__gshared MDirection!double[12] sideNormalsF64;
__gshared MDirection!float[12] sideNormalsF32;
__gshared MIsometry!double[12] reflectionsF64;
__gshared MIsometry!float[12] reflectionsF32;
__gshared bool[12][12] adjacent;
__gshared Side[3][20] vertexCanonicalSidesData;
__gshared Vertex[3][20] adjacentVerticesData;
__gshared ChunkAxisPermutation[3][20] chunkAxisPermutationsData;
__gshared MIsometry!double[20] dualToNodeF64;
__gshared MIsometry!float[20] dualToNodeF32;
__gshared MIsometry!double[20] nodeToDualF64;
__gshared MIsometry!float[20] nodeToDualF32;
__gshared double dualToChunkFactorF64;
__gshared float dualToChunkFactorF32;
__gshared double chunkToDualFactorF64;
__gshared float chunkToDualFactorF32;
__gshared MPoint!double[20] chunkBoundingSphereCentersF64;
__gshared MPoint!float[20] chunkBoundingSphereCentersF32;
__gshared bool[20] chunkToNodeParity;
__gshared Vertex[12][12][12] sidesToVertex;

shared static this() {
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
        sideNormalsF64[sideIdx] = tuvToXyz(sn, tAxis);
    }

    foreach (i; 0 .. 12) {
        foreach (j; 0 .. 12) {
            double mipVal = sideNormalsF64[i].mip(sideNormalsF64[j]);
            adjacent[i][j] = mipVal > -0.5 && mipVal < 0.5;
        }
    }

    foreach (i; 0 .. 12) {
        reflectionsF64[i] = MIsometry!double.reflection(sideNormalsF64[i]);
    }

    size_t vIdx = 0;
    foreach (a; 0 .. 12) {
        foreach (b; a + 1 .. 12) {
            foreach (c; b + 1 .. 12) {
                if (adjacent[a][b] && adjacent[b][c] && adjacent[c][a]) {
                    vertexCanonicalSidesData[vIdx] = [cast(Side)a, cast(Side)b, cast(Side)c];
                    vIdx++;
                }
            }
        }
    }
    assert(vIdx == 20);

    foreach (ref Vertex[12][12] plane; sidesToVertex) {
        foreach (ref Vertex[12] row; plane) {
            row[] = cast(Vertex) 255;
        }
    }

    foreach (vi; 0 .. 20) {
        Side[3] s = vertexCanonicalSidesData[vi];
        ubyte a = s[0];
        ubyte b = s[1];
        ubyte c = s[2];
        sidesToVertex[a][b][c] = cast(Vertex) vi;
        sidesToVertex[a][c][b] = cast(Vertex) vi;
        sidesToVertex[b][a][c] = cast(Vertex) vi;
        sidesToVertex[b][c][a] = cast(Vertex) vi;
        sidesToVertex[c][a][b] = cast(Vertex) vi;
        sidesToVertex[c][b][a] = cast(Vertex) vi;
    }

    double mipOriginNormal = MVector!double.origin().mip(sideNormalsF64[0].vec);
    foreach (vi; 0 .. 20) {
        Side[3] sides = vertexCanonicalSidesData[vi];
        MDirection!double na_ = sideNormalsF64[sides[0]];
        MDirection!double nb = sideNormalsF64[sides[1]];
        MDirection!double nc = sideNormalsF64[sides[2]];

        MPoint!double vertexPos = (MVector!double.origin() - (na_.vec + nb.vec + nc.vec) * mipOriginNormal).normalizedPoint();

        MDirection!double[3] dirs = [
            MDirection!double(-na_.vec),
            MDirection!double(-nb.vec),
            MDirection!double(-nc.vec),
        ];
        dualToNodeF64[vi] = MIsometry!double.fromColumnsUnchecked(dirs, vertexPos);
    }

    foreach (vi; 0 .. 20) {
        nodeToDualF64[vi] = dualToNodeF64[vi].inverse();
    }

    foreach (vi; 0 .. 20) {
        Side[3] canonical = vertexCanonicalSidesData[vi];
        foreach (axisIdx; 0 .. 3) {
            bool found = false;
            foreach (testSide; 0 .. 12) {
                if (cast(Side) testSide == canonical[axisIdx]) {
                    continue;
                }
                Side[3] testSides = canonical;
                testSides[axisIdx] = cast(Side) testSide;
                Vertex v = vertexFromSides(testSides);
                if (v != cast(Vertex) 255) {
                    adjacentVerticesData[vi][axisIdx] = v;
                    found = true;
                    break;
                }
            }
            assert(found);
        }
    }

    foreach (vi; 0 .. 20) {
        Side[3] canonical = vertexCanonicalSidesData[vi];
        foreach (axisIdx; 0 .. 3) {
            foreach (testSide; 0 .. 12) {
                if (cast(Side) testSide == canonical[axisIdx]) {
                    continue;
                }
                Side[3] testSides = canonical;
                testSides[axisIdx] = cast(Side) testSide;
                Vertex adjV = vertexFromSides(testSides);
                if (adjV != cast(Vertex) 255) {
                    chunkAxisPermutationsData[vi][axisIdx] = ChunkAxisPermutation.fromPermutation(
                        testSides, vertexCanonicalSidesData[adjV]
                    );
                    break;
                }
            }
        }
    }

    dualToChunkFactorF64 = sqrt(2.0 + sqrt(5.0));
    dualToChunkFactorF32 = cast(float) dualToChunkFactorF64;
    chunkToDualFactorF64 = 1.0 / dualToChunkFactorF64;
    chunkToDualFactorF32 = cast(float) chunkToDualFactorF64;

    foreach (i; 0 .. 12) {
        sideNormalsF32[i] = sideNormalsF64[i].toType!float();
        reflectionsF32[i] = reflectionsF64[i].toType!float();
    }
    foreach (vi; 0 .. 20) {
        dualToNodeF32[vi] = dualToNodeF64[vi].toType!float();
        nodeToDualF32[vi] = nodeToDualF64[vi].toType!float();
    }

    foreach (vi; 0 .. 20) {
        MPoint!double corner = dualToNodeF64[vi] * MPoint!double.origin();
        chunkBoundingSphereCentersF64[vi] = corner.midpoint(MPoint!double.origin());
        chunkBoundingSphereCentersF32[vi] = chunkBoundingSphereCentersF64[vi].toType!float();
    }

    foreach (vi; 0 .. 20) {
        chunkToNodeParity[vi] = dualToNodeF64[vi].parity();
    }
}

MDirection!double tuvToXyz(MDirection!double n, size_t tAxis) {
    double[4] d = n.vec.data;
    double[4] r = d;
    r[tAxis] = d[0];
    r[(tAxis + 1) % 3] = d[1];
    r[(tAxis + 2) % 3] = d[2];
    return MDirection!double(MVector!double(r[0], r[1], r[2], r[3]));
}

Vertex vertexFromSides(Side[3] sides) {
    Vertex v = sidesToVertex[sides[0]][sides[1]][sides[2]];
    return v;
}

ref const(MDirection!float) sideNormal(Side side) {
    return sideNormalsF32[side];
}

ref const(MDirection!double) sideNormalF64(Side side) {
    return sideNormalsF64[side];
}

ref const(MIsometry!float) sideReflection(Side side) {
    return reflectionsF32[side];
}

ref const(MIsometry!double) sideReflectionF64(Side side) {
    return reflectionsF64[side];
}

bool sideAdjacentTo(Side a, Side b) {
    return adjacent[a][b];
}

bool sideIsFacing(Side side, const ref MPoint!float p) {
    float[4] r = reflectionsF32[side].row(3);
    float dot = r[0] * p[0] + r[1] * p[1] + r[2] * p[2] + r[3] * p[3];
    return dot < p[3];
}

Side[3] vertexCanonicalSides(Vertex v) {
    return vertexCanonicalSidesData[v];
}

Vertex[3] vertexAdjacentVertices(Vertex v) {
    return adjacentVerticesData[v];
}

ref const(ChunkAxisPermutation[3]) vertexChunkAxisPermutations(Vertex v) {
    return chunkAxisPermutationsData[v];
}

Vertex vertexFromThreeSides(Side[3] sides) {
    return sidesToVertex[sides[0]][sides[1]][sides[2]];
}

ref const(MIsometry!float) vertexDualToNode(Vertex v) {
    return dualToNodeF32[v];
}

ref const(MIsometry!double) vertexDualToNodeF64(Vertex v) {
    return dualToNodeF64[v];
}

ref const(MIsometry!float) vertexNodeToDual(Vertex v) {
    return nodeToDualF32[v];
}

ref const(MIsometry!double) vertexNodeToDualF64(Vertex v) {
    return nodeToDualF64[v];
}

float vertexDualToChunkFactor() {
    return dualToChunkFactorF32;
}

double vertexDualToChunkFactorF64() {
    return dualToChunkFactorF64;
}

float vertexChunkToDualFactor() {
    return chunkToDualFactorF32;
}

double vertexChunkToDualFactorF64() {
    return chunkToDualFactorF64;
}

ref const(MPoint!float) vertexChunkBoundingSphereCenter(Vertex v) {
    return chunkBoundingSphereCentersF32[v];
}

ref const(MPoint!double) vertexChunkBoundingSphereCenterF64(Vertex v) {
    return chunkBoundingSphereCentersF64[v];
}

bool vertexParity(Vertex v) {
    return chunkToNodeParity[v];
}

Matrix4!float vertexChunkToNode(Vertex v) {
    Matrix4!float dtn = dualToNodeF32[v].mat;
    Matrix4!float scale = Matrix4!float.newScaling(1.0f / dualToChunkFactorF32);
    return dtn * scale;
}

Matrix4!double vertexChunkToNodeF64(Vertex v) {
    Matrix4!double dtn = dualToNodeF64[v].mat;
    Matrix4!double scale = Matrix4!double.newScaling(1.0 / dualToChunkFactorF64);
    return dtn * scale;
}

Matrix4!float vertexNodeToChunk(Vertex v) {
    Matrix4!float scale = Matrix4!float.newScaling(dualToChunkFactorF32);
    return scale * nodeToDualF32[v].mat;
}

Matrix4!double vertexNodeToChunkF64(Vertex v) {
    Matrix4!double scale = Matrix4!double.newScaling(dualToChunkFactorF64);
    return scale * nodeToDualF64[v].mat;
}
