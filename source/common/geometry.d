module common.geometry;

import std.math : sqrt, cosh, sinh;
import common.math : Matrix4, MVector;

/// The world is the order-4 dodecahedral honeycomb {5,3,4}: dodecahedral cells,
/// 4 meeting around each edge. A node (one dodecahedron) has 12 pentagon faces,
/// hence 12 neighbors and 12 chunks. This module holds the purely combinatorial
/// structure of one dodecahedron — which faces border each other — derived once
/// from the regular dodecahedron's face normals. No per-node coordinates: this is
/// a fixed table the local graph linking rule consults.

enum int SIDES = 12;

/// The 12 face normals of a regular dodecahedron, as (x,y,z) directions. Built
/// from the standard construction: faces normal to the 12 directions
/// (0, ±1, ±phi), (±1, ±phi, 0), (±phi, 0, ±1).
private immutable double[3][SIDES] FACE_NORMAL = buildNormals();

private double[3][SIDES] buildNormals() {
    enum double phi = 1.6180339887498949; // golden ratio
    double[3][SIDES] n = [
        [0, 1, phi], [0, 1, -phi], [0, -1, phi], [0, -1, -phi],
        [1, phi, 0], [1, -phi, 0], [-1, phi, 0], [-1, -phi, 0],
        [phi, 0, 1], [phi, 0, -1], [-phi, 0, 1], [-phi, 0, -1],
    ];
    foreach (ref v; n) {
        double len = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
        v[0] /= len;
        v[1] /= len;
        v[2] /= len;
    }
    return n;
}

/// adjacent[a][b] is true iff faces a and b share a pentagon edge. Two pentagon
/// faces of a dodecahedron are edge-adjacent iff the angle between their normals
/// is the face-adjacency angle (their normalized dot product ~ 1/sqrt(5)).
immutable bool[SIDES][SIDES] ADJACENT = buildAdjacency();

/// The face directly opposite each face (antipodal normal).
immutable int[SIDES] OPPOSITE = buildOpposite();

private bool[SIDES][SIDES] buildAdjacency() {
    bool[SIDES][SIDES] adj;
    double[3][SIDES] n = buildNormals();
    foreach (a; 0 .. SIDES) {
        foreach (b; 0 .. SIDES) {
            if (a == b) {
                continue;
            }
            double dot = n[a][0] * n[b][0] + n[a][1] * n[b][1] + n[a][2] * n[b][2];
            // Adjacent pentagon faces: dot = 1/sqrt(5) ~= 0.447. Opposite: -1.
            // Non-adjacent (skew): dot = -1/sqrt(5). Pick the positive band.
            adj[a][b] = dot > 0.4 && dot < 0.5;
        }
    }
    return adj;
}

private int[SIDES] buildOpposite() {
    int[SIDES] opp;
    double[3][SIDES] n = buildNormals();
    foreach (a; 0 .. SIDES) {
        opp[a] = -1;
        foreach (b; 0 .. SIDES) {
            double dot = n[a][0] * n[b][0] + n[a][1] * n[b][1] + n[a][2] * n[b][2];
            if (dot < -0.99) {
                opp[a] = b;
            }
        }
    }
    return opp;
}

bool sidesAdjacent(int a, int b) {
    return ADJACENT[a][b];
}

// Order-4 dodecahedral honeycomb {5,3,4}: 4 cells around each edge => dihedral
// angle 2*pi/4 = 90 deg. For a dodecahedron whose faces are mirror planes at
// hyperbolic in-radius t, adjacent face normals (dihedral apart) satisfy
// cos(dihedral) relating to the in-radius. We solve for t numerically once.
private immutable double IN_RADIUS = solveInRadius();

private double solveInRadius() {
    // Two adjacent face mirror planes have unit spacelike poles
    //   m_a = (cosh t) * d_a + (sinh t) * e_w,   m_b = (cosh t) * d_b + (sinh t) e_w
    // where d_a . d_b = 1/sqrt(5) (the dodecahedron's adjacent-normal dot). Their
    // Minkowski dot is the dihedral cosine:
    //   mip(m_a, m_b) = cosh^2(t) * (d_a . d_b) - sinh^2(t).
    // 4 cells around an edge => dihedral 90 deg => mip = cos(90) = 0. Solve for t.
    enum double dot = 0.4472135954999579; // 1/sqrt(5)
    double lo = 0.0, hi = 3.0;
    foreach (_; 0 .. 200) {
        double t = 0.5 * (lo + hi);
        double mip = cosh(t) * cosh(t) * dot - sinh(t) * sinh(t);
        if (mip > 0) {
            lo = t; // mip decreases as t grows; go bigger to reach 0
        } else {
            hi = t;
        }
    }
    return 0.5 * (lo + hi);
}

/// Reflection isometry for crossing side `s`: reflect across that face's mirror
/// plane (normal FACE_NORMAL[s], at in-radius t). Used only transiently to build
/// the bounded local frame within N shells for rendering/terrain — never stored
/// on a node.
Matrix4 sideTransform(int s) {
    double[3] d = faceNormal(s);
    double t = IN_RADIUS;
    double ch = cosh(t);
    double sh = sinh(t);
    // Reflection across plane with unit spacelike normal at distance t from
    // origin: m = (ch*d.x, ch*d.y, ch*d.z, sh) is the unit spacelike pole.
    double[4] m = [ch * d[0], ch * d[1], ch * d[2], sh];
    // Householder-style reflection in Minkowski metric J=diag(1,1,1,-1):
    // R = I - 2 * m (m^T J) / (m^T J m), and m^T J m = +1 (unit spacelike).
    enum double[4] J = [1, 1, 1, -1];
    Matrix4 R;
    foreach (col; 0 .. 4) {
        foreach (row; 0 .. 4) {
            double id = (row == col) ? 1.0 : 0.0;
            R.data[col][row] = cast(float)(id - 2.0 * m[row] * (m[col] * J[col]));
        }
    }
    return R;
}

private double[3] faceNormal(int s) {
    return FACE_NORMAL[s];
}

/// The in-radius (node center to face distance), for cell-boundary tests.
double inRadius() {
    return IN_RADIUS;
}

/// Unit face normal of side `s` as floats, for cell-boundary tests.
float[3] faceNormalF(int s) {
    return [cast(float) FACE_NORMAL[s][0], cast(float) FACE_NORMAL[s][1], cast(float) FACE_NORMAL[s][2]];
}

unittest {
    // Every face borders exactly 5 others (pentagon), and has exactly 1 opposite.
    foreach (a; 0 .. SIDES) {
        int count = 0;
        foreach (b; 0 .. SIDES) {
            if (ADJACENT[a][b]) {
                count++;
            }
        }
        assert(count == 5, "each dodecahedron face must border 5 others");
        assert(OPPOSITE[a] >= 0);
        assert(OPPOSITE[a] != a);
        assert(!ADJACENT[a][OPPOSITE[a]]);
    }
}

unittest {
    import std.math : abs;
    import common.math : hyperbolicDistance;

    // Crossing a side then the same side again is the identity (involution).
    MVector o = MVector.origin();
    foreach (s; 0 .. SIDES) {
        MVector moved = (sideTransform(s) * o).normalized();
        assert(hyperbolicDistance(o, moved) > 0.1); // actually moves
        MVector back = (sideTransform(s) * sideTransform(s) * o).normalized();
        assert(hyperbolicDistance(o, back) < 1e-4);
    }
}

unittest {
    import std.math : abs;
    import common.math : hyperbolicDistance;

    // 4 dodecahedra close around an edge: composing reflections in two adjacent
    // faces is a 90-degree rotation, so doing it 4 times returns to the origin.
    MVector o = MVector.origin();
    foreach (a; 0 .. SIDES) {
        foreach (b; 0 .. SIDES) {
            if (!ADJACENT[a][b]) {
                continue;
            }
            Matrix4 step = sideTransform(a) * sideTransform(b);
            Matrix4 four = step * step * step * step;
            MVector p = (four * o).normalized();
            assert(hyperbolicDistance(o, p) < 1e-3,
                "4-around-an-edge must close to identity");
            break;
        }
    }
}
