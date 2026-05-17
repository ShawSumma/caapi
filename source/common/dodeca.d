/// Tools for processing the geometry of a right dodecahedron
module common.dodeca;

import std.math;
import common.math;
import common.voxel_math : ChunkAxisPermutation;

/// Sides of a right dodecahedron
enum Side : ubyte {
    A, B, C, D, E, F, G, H, I, J, K, L,
}

enum SIDE_COUNT = 12;

/// Vertices of a right dodecahedron (20 chunks per node)
enum Vertex : ubyte {
    A, B, C, D, E, F, G, H, I, J,
    K, L, M, N, O, P, Q, R, S, T,
}

enum VERTEX_COUNT = 20;

enum double BOUNDING_SPHERE_RADIUS_F64 = 1.2264568712514068;
enum float BOUNDING_SPHERE_RADIUS = cast(float) BOUNDING_SPHERE_RADIUS_F64;
enum double CHUNK_BOUNDING_SPHERE_RADIUS_F64 = BOUNDING_SPHERE_RADIUS_F64 * 0.5;
enum float CHUNK_BOUNDING_SPHERE_RADIUS = cast(float) CHUNK_BOUNDING_SPHERE_RADIUS_F64;

private {
    // Lazily computed static data
    __gshared bool _dataInitialized = false;
    __gshared MDirection!double[SIDE_COUNT] _sideNormalsF64;
    __gshared MDirection!float[SIDE_COUNT] _sideNormalsF32;
    __gshared MIsometry!double[SIDE_COUNT] _reflectionsF64;
    __gshared MIsometry!float[SIDE_COUNT] _reflectionsF32;
    __gshared bool[SIDE_COUNT][SIDE_COUNT] _adjacent;
    __gshared Side[3][VERTEX_COUNT] _vertexCanonicalSides;
    __gshared Vertex[3][VERTEX_COUNT] _adjacentVertices;
    __gshared ChunkAxisPermutation[3][VERTEX_COUNT] _chunkAxisPermutations;
    __gshared MIsometry!double[VERTEX_COUNT] _dualToNodeF64;
    __gshared MIsometry!float[VERTEX_COUNT] _dualToNodeF32;
    __gshared MIsometry!double[VERTEX_COUNT] _nodeToDualF64;
    __gshared MIsometry!float[VERTEX_COUNT] _nodeToDualF32;
    __gshared double _dualToChunkFactorF64;
    __gshared float _dualToChunkFactorF32;
    __gshared double _chunkToDualFactorF64;
    __gshared float _chunkToDualFactorF32;
    __gshared MPoint!double[VERTEX_COUNT] _chunkBoundingSphereCentersF64;
    __gshared MPoint!float[VERTEX_COUNT] _chunkBoundingSphereCentersF32;
    __gshared bool[VERTEX_COUNT] _chunkToNodeParity;
    __gshared Vertex[SIDE_COUNT][SIDE_COUNT][SIDE_COUNT] _sidesToVertex;
    __gshared bool _sidesToVertexValid;

    void ensureDataInitialized() {
        if (_dataInitialized) return;
        initializeData();
        _dataInitialized = true;
    }

    void initializeData() {
        // Compute side normals
        double phi = sqrt(1.25) + 0.5;
        auto templateNormal = MVector!double(1.0, phi, 0.0, sqrt(phi)).normalizedDirection();

        MDirection!double[4] signedNormals = [
            MDirection!double.newUnchecked(templateNormal[0], templateNormal[1], templateNormal[2], templateNormal[3]),
            MDirection!double.newUnchecked(-templateNormal[0], templateNormal[1], -templateNormal[2], templateNormal[3]),
            MDirection!double.newUnchecked(templateNormal[0], -templateNormal[1], -templateNormal[2], templateNormal[3]),
            MDirection!double.newUnchecked(-templateNormal[0], -templateNormal[1], templateNormal[2], templateNormal[3]),
        ];

        foreach (sideIdx; 0 .. SIDE_COUNT) {
            auto sn = signedNormals[sideIdx / 3];
            size_t tAxis = (3 - sideIdx % 3) % 3;
            _sideNormalsF64[sideIdx] = tuvToXyz(sn, tAxis);
        }

        // Compute adjacency
        foreach (i; 0 .. SIDE_COUNT) {
            foreach (j; 0 .. SIDE_COUNT) {
                double mipVal = _sideNormalsF64[i].mip(_sideNormalsF64[j]);
                _adjacent[i][j] = mipVal > -0.5 && mipVal < 0.5;
            }
        }

        // Compute reflections
        foreach (i; 0 .. SIDE_COUNT) {
            _reflectionsF64[i] = MIsometry!double.reflection(_sideNormalsF64[i]);
        }

        // Compute vertex canonical sides (brute force)
        size_t vIdx = 0;
        foreach (a; 0 .. SIDE_COUNT) {
            foreach (b; a + 1 .. SIDE_COUNT) {
                foreach (c; b + 1 .. SIDE_COUNT) {
                    if (_adjacent[a][b] && _adjacent[b][c] && _adjacent[c][a]) {
                        _vertexCanonicalSides[vIdx] = [cast(Side)a, cast(Side)b, cast(Side)c];
                        vIdx++;
                    }
                }
            }
        }
        assert(vIdx == VERTEX_COUNT);

        // Build sides-to-vertex lookup
        foreach (ref plane; _sidesToVertex) {
            foreach (ref row; plane) {
                row[] = cast(Vertex) 255; // sentinel for "no vertex"
            }
        }

        foreach (vi; 0 .. VERTEX_COUNT) {
            auto s = _vertexCanonicalSides[vi];
            ubyte a = s[0], b = s[1], c = s[2];
            _sidesToVertex[a][b][c] = cast(Vertex) vi;
            _sidesToVertex[a][c][b] = cast(Vertex) vi;
            _sidesToVertex[b][a][c] = cast(Vertex) vi;
            _sidesToVertex[b][c][a] = cast(Vertex) vi;
            _sidesToVertex[c][a][b] = cast(Vertex) vi;
            _sidesToVertex[c][b][a] = cast(Vertex) vi;
        }
        _sidesToVertexValid = true;

        // Compute dual-to-node transforms
        double mipOriginNormal = MVector!double.origin().mip(_sideNormalsF64[0].vec);
        foreach (vi; 0 .. VERTEX_COUNT) {
            auto sides = _vertexCanonicalSides[vi];
            auto na_ = _sideNormalsF64[sides[0]];
            auto nb = _sideNormalsF64[sides[1]];
            auto nc = _sideNormalsF64[sides[2]];

            auto vertexPos = (MVector!double.origin() - (na_.vec + nb.vec + nc.vec) * mipOriginNormal).normalizedPoint();

            MDirection!double[3] dirs = [
                MDirection!double(-na_.vec),
                MDirection!double(-nb.vec),
                MDirection!double(-nc.vec),
            ];
            _dualToNodeF64[vi] = MIsometry!double.fromColumnsUnchecked(dirs, vertexPos);
        }

        // Node-to-dual is inverse of dual-to-node
        foreach (vi; 0 .. VERTEX_COUNT) {
            _nodeToDualF64[vi] = _dualToNodeF64[vi].inverse();
        }

        // Compute adjacent vertices
        foreach (vi; 0 .. VERTEX_COUNT) {
            auto canonical = _vertexCanonicalSides[vi];
            foreach (axisIdx; 0 .. 3) {
                bool found = false;
                foreach (testSide; 0 .. SIDE_COUNT) {
                    if (cast(Side) testSide == canonical[axisIdx]) continue;
                    Side[3] testSides = canonical;
                    testSides[axisIdx] = cast(Side) testSide;
                    auto v = vertexFromSides(testSides);
                    if (v != cast(Vertex) 255) {
                        _adjacentVertices[vi][axisIdx] = v;
                        found = true;
                        break;
                    }
                }
                assert(found);
            }
        }

        // Compute chunk axis permutations
        foreach (vi; 0 .. VERTEX_COUNT) {
            auto canonical = _vertexCanonicalSides[vi];
            foreach (axisIdx; 0 .. 3) {
                foreach (testSide; 0 .. SIDE_COUNT) {
                    if (cast(Side) testSide == canonical[axisIdx]) continue;
                    Side[3] testSides = canonical;
                    testSides[axisIdx] = cast(Side) testSide;
                    auto adjV = vertexFromSides(testSides);
                    if (adjV != cast(Vertex) 255) {
                        _chunkAxisPermutations[vi][axisIdx] = ChunkAxisPermutation.fromPermutation(
                            testSides, _vertexCanonicalSides[adjV]
                        );
                        break;
                    }
                }
            }
        }

        // Scaling factors
        _dualToChunkFactorF64 = sqrt(2.0 + sqrt(5.0));
        _dualToChunkFactorF32 = cast(float) _dualToChunkFactorF64;
        _chunkToDualFactorF64 = 1.0 / _dualToChunkFactorF64;
        _chunkToDualFactorF32 = cast(float) _chunkToDualFactorF64;

        // f32 versions
        foreach (i; 0 .. SIDE_COUNT) {
            _sideNormalsF32[i] = _sideNormalsF64[i].toType!float();
            _reflectionsF32[i] = _reflectionsF64[i].toType!float();
        }
        foreach (vi; 0 .. VERTEX_COUNT) {
            _dualToNodeF32[vi] = _dualToNodeF64[vi].toType!float();
            _nodeToDualF32[vi] = _nodeToDualF64[vi].toType!float();
        }

        // Bounding sphere centers
        foreach (vi; 0 .. VERTEX_COUNT) {
            auto corner = _dualToNodeF64[vi] * MPoint!double.origin();
            _chunkBoundingSphereCentersF64[vi] = corner.midpoint(MPoint!double.origin());
            _chunkBoundingSphereCentersF32[vi] = _chunkBoundingSphereCentersF64[vi].toType!float();
        }

        // Parity
        foreach (vi; 0 .. VERTEX_COUNT) {
            _chunkToNodeParity[vi] = _dualToNodeF64[vi].parity();
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
        auto v = _sidesToVertex[sides[0]][sides[1]][sides[2]];
        return v;
    }
}

// Public API for Side
ref const(MDirection!float) sideNormal(Side side) {
    ensureDataInitialized();
    return _sideNormalsF32[side];
}

ref const(MDirection!double) sideNormalF64(Side side) {
    ensureDataInitialized();
    return _sideNormalsF64[side];
}

ref const(MIsometry!float) sideReflection(Side side) {
    ensureDataInitialized();
    return _reflectionsF32[side];
}

ref const(MIsometry!double) sideReflectionF64(Side side) {
    ensureDataInitialized();
    return _reflectionsF64[side];
}

bool sideAdjacentTo(Side a, Side b) {
    ensureDataInitialized();
    return _adjacent[a][b];
}

bool sideIsFacing(Side side, const ref MPoint!float p) {
    ensureDataInitialized();
    auto r = _reflectionsF32[side].row(3);
    float dot = r[0] * p[0] + r[1] * p[1] + r[2] * p[2] + r[3] * p[3];
    return dot < p[3];
}

// Public API for Vertex
Side[3] vertexCanonicalSides(Vertex v) {
    ensureDataInitialized();
    return _vertexCanonicalSides[v];
}

Vertex[3] vertexAdjacentVertices(Vertex v) {
    ensureDataInitialized();
    return _adjacentVertices[v];
}

ref const(ChunkAxisPermutation[3]) vertexChunkAxisPermutations(Vertex v) {
    ensureDataInitialized();
    return _chunkAxisPermutations[v];
}

Vertex vertexFromThreeSides(Side[3] sides) {
    ensureDataInitialized();
    return _sidesToVertex[sides[0]][sides[1]][sides[2]];
}

ref const(MIsometry!float) vertexDualToNode(Vertex v) {
    ensureDataInitialized();
    return _dualToNodeF32[v];
}

ref const(MIsometry!double) vertexDualToNodeF64(Vertex v) {
    ensureDataInitialized();
    return _dualToNodeF64[v];
}

ref const(MIsometry!float) vertexNodeToDual(Vertex v) {
    ensureDataInitialized();
    return _nodeToDualF32[v];
}

ref const(MIsometry!double) vertexNodeToDualF64(Vertex v) {
    ensureDataInitialized();
    return _nodeToDualF64[v];
}

float vertexDualToChunkFactor() {
    ensureDataInitialized();
    return _dualToChunkFactorF32;
}

double vertexDualToChunkFactorF64() {
    ensureDataInitialized();
    return _dualToChunkFactorF64;
}

float vertexChunkToDualFactor() {
    ensureDataInitialized();
    return _chunkToDualFactorF32;
}

double vertexChunkToDualFactorF64() {
    ensureDataInitialized();
    return _chunkToDualFactorF64;
}

ref const(MPoint!float) vertexChunkBoundingSphereCenter(Vertex v) {
    ensureDataInitialized();
    return _chunkBoundingSphereCentersF32[v];
}

ref const(MPoint!double) vertexChunkBoundingSphereCenterF64(Vertex v) {
    ensureDataInitialized();
    return _chunkBoundingSphereCentersF64[v];
}

bool vertexParity(Vertex v) {
    ensureDataInitialized();
    return _chunkToNodeParity[v];
}

Matrix4!float vertexChunkToNode(Vertex v) {
    ensureDataInitialized();
    auto dtn = _dualToNodeF32[v].mat;
    auto scale = Matrix4!float.newScaling(1.0f / _dualToChunkFactorF32);
    return dtn * scale;
}

Matrix4!double vertexChunkToNodeF64(Vertex v) {
    ensureDataInitialized();
    auto dtn = _dualToNodeF64[v].mat;
    auto scale = Matrix4!double.newScaling(1.0 / _dualToChunkFactorF64);
    return dtn * scale;
}

Matrix4!float vertexNodeToChunk(Vertex v) {
    ensureDataInitialized();
    auto scale = Matrix4!float.newScaling(_dualToChunkFactorF32);
    return scale * _nodeToDualF32[v].mat;
}

Matrix4!double vertexNodeToChunkF64(Vertex v) {
    ensureDataInitialized();
    auto scale = Matrix4!double.newScaling(_dualToChunkFactorF64);
    return scale * _nodeToDualF64[v].mat;
}
