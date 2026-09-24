module common.dodeca;

import core.math : sqrt;
import common.math : MDirection, MIsometry, MPoint, MVector, Matrix4;
import common.voxel_math : ChunkAxisPermutation, permutationFromSides;

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

enum uint SIDE_COUNT = 12;
enum uint VERTEX_COUNT = 20;
enum ubyte NO_VERTEX_INDEX = 255;
enum double BOUNDING_SPHERE_RADIUS_F64 = 1.2264568712514068;
enum float BOUNDING_SPHERE_RADIUS = cast(float) BOUNDING_SPHERE_RADIUS_F64;
enum float CHUNK_BOUNDING_SPHERE_RADIUS = cast(float)(BOUNDING_SPHERE_RADIUS_F64 * 0.5);
enum double ADJACENCY_PRODUCT_LIMIT = 0.5;

struct DodecaTables {
    MIsometry!float[VERTEX_COUNT] dualToNode;
    MIsometry!float[VERTEX_COUNT] nodeToDual;
    MIsometry!float[SIDE_COUNT] reflections;
    MDirection!float[SIDE_COUNT] sideNormals;
    MPoint!float[VERTEX_COUNT] chunkBoundingSphereCenters;
    float dualToChunkFactor;
    ChunkAxisPermutation[3][VERTEX_COUNT] chunkAxisPermutations;
    Side[3][VERTEX_COUNT] vertexCanonicalSides;
    Vertex[3][VERTEX_COUNT] adjacentVertices;
    bool[SIDE_COUNT][SIDE_COUNT] adjacent;
}

immutable DodecaTables DODECA_TABLES = buildTables();

MDirection!double rotateAxes(MVector!double v, size_t tAxis) {
    double[4] r;
    r[tAxis] = v.data[0];
    r[(tAxis + 1) % 3] = v.data[1];
    r[(tAxis + 2) % 3] = v.data[2];
    r[3] = v.data[3];
    return MDirection!double(MVector!double(r[0], r[1], r[2], r[3]));
}

DodecaTables buildTables() {
    DodecaTables t;
    double phi = sqrt(1.25) + 0.5;
    MDirection!double templateNormal = MVector!double(1.0, phi, 0.0, sqrt(phi)).normalizedDirection();
    double x = templateNormal.vec.data[0];
    double y = templateNormal.vec.data[1];
    double z = templateNormal.vec.data[2];
    double w = templateNormal.vec.data[3];
    MVector!double[4] signedNormals = [
        MVector!double(x, y, z, w),
        MVector!double(-x, y, -z, w),
        MVector!double(x, -y, -z, w),
        MVector!double(-x, -y, z, w),
    ];

    MDirection!double[SIDE_COUNT] sideNormals;
    foreach (sideIndex; 0 .. SIDE_COUNT) {
        sideNormals[sideIndex] = rotateAxes(signedNormals[sideIndex / 3], (3 - sideIndex % 3) % 3);
        t.sideNormals[sideIndex] = sideNormals[sideIndex].toType!float();
        t.reflections[sideIndex] = MIsometry!double.reflection(sideNormals[sideIndex]).toType!float();
    }

    foreach (i; 0 .. SIDE_COUNT) {
        foreach (j; 0 .. SIDE_COUNT) {
            double product = sideNormals[i].mip(sideNormals[j].vec);
            t.adjacent[i][j] = product > -ADJACENCY_PRODUCT_LIMIT && product < ADJACENCY_PRODUCT_LIMIT;
        }
    }

    ubyte[SIDE_COUNT][SIDE_COUNT][SIDE_COUNT] sidesToVertex;
    foreach (i; 0 .. SIDE_COUNT) {
        foreach (j; 0 .. SIDE_COUNT) {
            foreach (k; 0 .. SIDE_COUNT) {
                sidesToVertex[i][j][k] = NO_VERTEX_INDEX;
            }
        }
    }

    uint vertexCount = 0;
    foreach (a; 0 .. SIDE_COUNT) {
        foreach (b; a + 1 .. SIDE_COUNT) {
            foreach (c; b + 1 .. SIDE_COUNT) {
                if (t.adjacent[a][b] && t.adjacent[b][c] && t.adjacent[c][a]) {
                    t.vertexCanonicalSides[vertexCount][0] = cast(Side) a;
                    t.vertexCanonicalSides[vertexCount][1] = cast(Side) b;
                    t.vertexCanonicalSides[vertexCount][2] = cast(Side) c;
                    ubyte v = cast(ubyte) vertexCount;
                    sidesToVertex[a][b][c] = v;
                    sidesToVertex[a][c][b] = v;
                    sidesToVertex[b][a][c] = v;
                    sidesToVertex[b][c][a] = v;
                    sidesToVertex[c][a][b] = v;
                    sidesToVertex[c][b][a] = v;
                    vertexCount += 1;
                }
            }
        }
    }
    assert(vertexCount == VERTEX_COUNT);

    double mipOriginNormal = MVector!double.origin().mip(sideNormals[0].vec);
    t.dualToChunkFactor = cast(float) sqrt(2.0 + sqrt(5.0));
    foreach (vi; 0 .. VERTEX_COUNT) {
        MDirection!double na = sideNormals[t.vertexCanonicalSides[vi][0]];
        MDirection!double nb = sideNormals[t.vertexCanonicalSides[vi][1]];
        MDirection!double nc = sideNormals[t.vertexCanonicalSides[vi][2]];
        MVector!double sum = na.vec + nb.vec + nc.vec;
        MPoint!double vertexPosition = (MVector!double.origin() - sum * mipOriginNormal).normalizedPoint();
        MDirection!double[3] columns = [-na, -nb, -nc];
        MIsometry!double dualToNode = MIsometry!double.fromColumnsUnchecked(columns, vertexPosition);
        t.dualToNode[vi] = dualToNode.toType!float();
        t.nodeToDual[vi] = dualToNode.inverse().toType!float();
        MPoint!double corner = dualToNode * MPoint!double.origin();
        t.chunkBoundingSphereCenters[vi] = corner.midpoint(MPoint!double.origin()).toType!float();
    }

    foreach (vi; 0 .. VERTEX_COUNT) {
        foreach (axisIndex; 0 .. 3) {
            bool found = false;
            foreach (testSide; 0 .. SIDE_COUNT) {
                if (!found && testSide != t.vertexCanonicalSides[vi][axisIndex]) {
                    Side[3] testSides;
                    foreach (k; 0 .. 3) {
                        if (k == axisIndex) {
                            testSides[k] = cast(Side) testSide;
                        } else {
                            testSides[k] = t.vertexCanonicalSides[vi][k];
                        }
                    }
                    ubyte adjacentVertex = sidesToVertex[testSides[0]][testSides[1]][testSides[2]];
                    if (adjacentVertex != NO_VERTEX_INDEX) {
                        Side[3] adjacentSides;
                        foreach (k; 0 .. 3) {
                            adjacentSides[k] = t.vertexCanonicalSides[adjacentVertex][k];
                        }
                        t.adjacentVertices[vi][axisIndex] = cast(Vertex) adjacentVertex;
                        t.chunkAxisPermutations[vi][axisIndex] = permutationFromSides(testSides, adjacentSides);
                        found = true;
                    }
                }
            }
        }
    }
    return t;
}

MDirection!float sideNormal(Side side) {
    return DODECA_TABLES.sideNormals[side];
}

MIsometry!float sideReflection(Side side) {
    return DODECA_TABLES.reflections[side];
}

bool sideAdjacentTo(Side a, Side b) {
    return DODECA_TABLES.adjacent[a][b];
}

bool sideIsFacing(Side side, MPoint!float p) {
    float[4] r = DODECA_TABLES.reflections[side].row(3);
    float dot = r[0] * p.vec.data[0] + r[1] * p.vec.data[1] + r[2] * p.vec.data[2] + r[3] * p.vec.data[3];
    return dot < p.vec.data[3];
}

Side[3] vertexCanonicalSides(Vertex v) {
    return DODECA_TABLES.vertexCanonicalSides[v];
}

Vertex[3] vertexAdjacentVertices(Vertex v) {
    return DODECA_TABLES.adjacentVertices[v];
}

ChunkAxisPermutation[3] vertexChunkAxisPermutations(Vertex v) {
    return DODECA_TABLES.chunkAxisPermutations[v];
}

MIsometry!float vertexNodeToDual(Vertex v) {
    return DODECA_TABLES.nodeToDual[v];
}

float vertexDualToChunkFactor() {
    return DODECA_TABLES.dualToChunkFactor;
}

MPoint!float vertexChunkBoundingSphereCenter(Vertex v) {
    return DODECA_TABLES.chunkBoundingSphereCenters[v];
}

Matrix4!float vertexChunkToNode(Vertex v) {
    return DODECA_TABLES.dualToNode[v].mat * Matrix4!float.newScaling(1.0f / DODECA_TABLES.dualToChunkFactor);
}
