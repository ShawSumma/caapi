module common.dodeca;

import core.math : fabs, sqrt;
import core.stdc.math : acoshf;
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
enum float TABLE_TOLERANCE = 1e-5f;

alias SidesToVertex = ubyte[SIDE_COUNT][SIDE_COUNT][SIDE_COUNT];

struct DodecaTables {
    MIsometry!float[VERTEX_COUNT] dualToNode;
    MIsometry!float[VERTEX_COUNT] nodeToDual;
    MIsometry!float[SIDE_COUNT] reflections;
    MDirection!float[SIDE_COUNT] sideNormals;
    MPoint!float[VERTEX_COUNT] chunkBoundingSphereCenters;
    float dualToChunkFactor;
    float chunkGridCenterCornerCosh;
    ChunkAxisPermutation[3][VERTEX_COUNT] chunkAxisPermutations;
    Side[3][VERTEX_COUNT] vertexCanonicalSides;
    Vertex[3][VERTEX_COUNT] adjacentVertices;
    bool[SIDE_COUNT][SIDE_COUNT] isAdjacent;
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
            t.isAdjacent[i][j] = product > -ADJACENCY_PRODUCT_LIMIT && product < ADJACENCY_PRODUCT_LIMIT;
        }
    }

    SidesToVertex sidesToVertex;
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
                if (t.isAdjacent[a][b] && t.isAdjacent[b][c] && t.isAdjacent[c][a]) {
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

    foreach (vi; 0 .. VERTEX_COUNT) {
        MIsometry!double dualToNode = vertexDualFrame(sideNormals, t.vertexCanonicalSides[vi]);
        t.dualToNode[vi] = dualToNode.toType!float();
        t.nodeToDual[vi] = dualToNode.inverse().toType!float();
        MPoint!double corner = dualToNode * MPoint!double.origin();
        t.chunkBoundingSphereCenters[vi] = corner.midpoint(MPoint!double.origin()).toType!float();
    }
    MIsometry!double referenceFrame = vertexDualFrame(sideNormals, t.vertexCanonicalSides[0]);
    MVector!double nodeCenterInDual = referenceFrame.inverse() * MVector!double.origin();
    double dualToChunk = nodeCenterInDual.data[3] / nodeCenterInDual.data[0];
    t.dualToChunkFactor = cast(float) dualToChunk;
    MPoint!double gridCenter = (referenceFrame * MVector!double(0.5 / dualToChunk, 0.5 / dualToChunk, 0.5 / dualToChunk, 1.0)).normalizedPoint();
    double farthestCosh = 1.0;
    foreach (corner; 0 .. 8) {
        MVector!double chunkCorner = MVector!double((corner & 1) / dualToChunk, ((corner >> 1) & 1) / dualToChunk, ((corner >> 2) & 1) / dualToChunk, 1.0);
        double cornerCosh = -gridCenter.mip((referenceFrame * chunkCorner).normalizedPoint().vec);
        if (cornerCosh > farthestCosh) {
            farthestCosh = cornerCosh;
        }
    }
    t.chunkGridCenterCornerCosh = cast(float) farthestCosh;

    foreach (vi; 0 .. VERTEX_COUNT) {
        foreach (axisIndex; 0 .. 3) {
            Side[3] testSides = sidesAcrossAxis(&sidesToVertex, t.vertexCanonicalSides[vi], axisIndex);
            ubyte adjacentVertex = sidesToVertex[testSides[0]][testSides[1]][testSides[2]];
            t.adjacentVertices[vi][axisIndex] = cast(Vertex) adjacentVertex;
            t.chunkAxisPermutations[vi][axisIndex] = permutationFromSides(testSides, t.vertexCanonicalSides[adjacentVertex]);
        }
    }
    return t;
}

Side[3] sidesAcrossAxis(const(SidesToVertex)* sidesToVertex, Side[3] sides, size_t axis) {
    foreach (testSide; 0 .. SIDE_COUNT) {
        Side[3] candidate;
        foreach (k; 0 .. 3) {
            if (k == axis) {
                candidate[k] = cast(Side) testSide;
            } else {
                candidate[k] = sides[k];
            }
        }
        if (testSide != sides[axis] && (*sidesToVertex)[candidate[0]][candidate[1]][candidate[2]] != NO_VERTEX_INDEX) {
            return candidate;
        }
    }
    assert(false);
}

MIsometry!double vertexDualFrame(MDirection!double[SIDE_COUNT] sideNormals, Side[3] sides) {
    MDirection!double na = sideNormals[sides[0]];
    MDirection!double nb = sideNormals[sides[1]];
    MDirection!double nc = sideNormals[sides[2]];
    double mipOriginNormal = MVector!double.origin().mip(na.vec);
    MPoint!double vertexPosition = (MVector!double.origin() - (na.vec + nb.vec + nc.vec) * mipOriginNormal).normalizedPoint();
    MDirection!double[3] columns = [-na, -nb, -nc];
    return MIsometry!double.fromColumnsUnchecked(columns, vertexPosition);
}

MDirection!float normal(Side side) {
    return DODECA_TABLES.sideNormals[side];
}

MIsometry!float reflection(Side side) {
    return DODECA_TABLES.reflections[side];
}

bool isAdjacentTo(Side a, Side b) {
    return DODECA_TABLES.isAdjacent[a][b];
}

bool isFacing(Side side, MPoint!float p) {
    float[4] r = DODECA_TABLES.reflections[side].row(3);
    float dot = r[0] * p.vec.data[0] + r[1] * p.vec.data[1] + r[2] * p.vec.data[2] + r[3] * p.vec.data[3];
    return dot < p.vec.data[3];
}

Side[3] canonicalSides(Vertex v) {
    return DODECA_TABLES.vertexCanonicalSides[v];
}

Vertex[3] adjacentVertices(Vertex v) {
    return DODECA_TABLES.adjacentVertices[v];
}

ChunkAxisPermutation[3] chunkAxisPermutations(Vertex v) {
    return DODECA_TABLES.chunkAxisPermutations[v];
}

MIsometry!float nodeToDual(Vertex v) {
    return DODECA_TABLES.nodeToDual[v];
}

float vertexDualToChunkFactor() {
    return DODECA_TABLES.dualToChunkFactor;
}

float chunkGridCenterRadius() {
    return acoshf(DODECA_TABLES.chunkGridCenterCornerCosh);
}

MPoint!float chunkBoundingSphereCenter(Vertex v) {
    return DODECA_TABLES.chunkBoundingSphereCenters[v];
}

Matrix4!float chunkToNode(Vertex v) {
    return DODECA_TABLES.dualToNode[v].mat * Matrix4!float.newScaling(1.0f / DODECA_TABLES.dualToChunkFactor);
}

unittest {
    foreach (v; 0 .. VERTEX_COUNT) {
        Vertex vertex = cast(Vertex) v;
        MPoint!float vertexPoint = DODECA_TABLES.dualToNode[v] * MPoint!float.origin();
        assert(fabs(MPoint!float.origin().distance(vertexPoint) - BOUNDING_SPHERE_RADIUS) < TABLE_TOLERANCE);
        MVector!float nodeCenter = vertex.nodeToDual * MVector!float.origin();
        foreach (axis; 0 .. 3) {
            assert(fabs(nodeCenter.data[axis] / nodeCenter.data[3] * DODECA_TABLES.dualToChunkFactor - 1) < TABLE_TOLERANCE);
        }
        MPoint!float center = vertex.chunkBoundingSphereCenter;
        MPoint!float gridCenter = (vertex.chunkToNode * MVector!float(0.5f, 0.5f, 0.5f, 1)).normalizedPoint();
        foreach (corner; 0 .. 8) {
            MVector!float chunkCorner = MVector!float(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1, 1);
            MPoint!float cornerPoint = (vertex.chunkToNode * chunkCorner).normalizedPoint();
            assert(center.distance(cornerPoint) < CHUNK_BOUNDING_SPHERE_RADIUS + TABLE_TOLERANCE);
            assert(gridCenter.distance(cornerPoint) < chunkGridCenterRadius() + TABLE_TOLERANCE);
        }
    }
}
