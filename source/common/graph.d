module common.graph;

import core.atomic : atomicLoad, atomicStore, MemoryOrder;
import std.math : lround;
import common.math : Matrix4, MVector, hyperbolicDistance, inverseIsometry;
import common.geometry : FACES, FACE_AXIS_SIGN, faceTransform;

enum State : ubyte {
    Empty,      // not generated yet
    Generating, // claimed by the worldgen thread
    Ready,      // voxels valid
}

/// A cube of voxels and links to the cubes across its 6 faces.
///
/// Cubes are created and linked only by the worldgen thread. A neighbor pointer
/// goes from null to a fully-built cube once and never changes, so an
/// atomic-release store on write and atomic-acquire load on read let the render
/// thread follow links with no lock: it sees either null or a finished cube.
struct Cube {
    ushort[] voxels;                 // null until Ready; immutable once published
    shared(Cube)*[FACES] neighbors;  // null = not linked
    Matrix4 transform;               // places this cube relative to the root cube
    uint depth;                      // graph distance from root
    shared State state = State.Empty;
    shared uint generation = 0;

    Cube* neighbor(int face) {
        return cast(Cube*) atomicLoad!(MemoryOrder.acq)(neighbors[face]);
    }

    void link(int face, Cube* n) {
        atomicStore!(MemoryOrder.rel)(neighbors[face], cast(shared(Cube)*) n);
    }

    State loadState() const {
        return atomicLoad!(MemoryOrder.acq)(state);
    }

    void setState(State s) {
        atomicStore!(MemoryOrder.rel)(state, s);
    }

    uint loadGeneration() const {
        return atomicLoad!(MemoryOrder.acq)(generation);
    }
}

/// The cube graph. The worldgen thread grows it outward from the root by walking
/// face links and allocating neighbors on demand; a cube is identified by its
/// position in hyperbolic space and reached by dereferencing neighbor pointers.
///
/// The honeycomb has cycles (e.g. 5 cubes close around each edge in {4,3,5}), so
/// a face can lead to a cube already created via a different path. We must
/// recognise that and link to the existing cube, or the graph would be an
/// infinite tree. Cubes are deduplicated by their center position via a spatial
/// hash; two cubes whose centers coincide (to tolerance) are the same cube.
struct Graph {
    Cube* root;
    private Cube*[long] byCell;   // quantized-center -> cube

    static Graph* create() {
        Graph* g = new Graph;
        g.root = new Cube;
        g.root.transform = Matrix4.identity();
        g.root.depth = 0;
        g.byCell[cellKey(g.center(g.root))] = g.root;
        return g;
    }

    /// Return the neighbor across `face`, creating and linking it if absent.
    /// Worldgen thread only (it allocates and mutates topology). Deduplicates by
    /// position so cycles in the honeycomb close instead of spawning duplicates.
    Cube* ensureNeighbor(Cube* c, int face) {
        Cube* existing = c.neighbor(face);
        if (existing !is null) {
            return existing;
        }

        Matrix4 t = c.transform * faceTransform(face);
        MVector ctr = (t * MVector.origin()).normalized();
        long key = cellKey(ctr);

        Cube* found = byCell.get(key, null);
        if (found is null) {
            // Genuinely new cube.
            found = new Cube;
            found.transform = t;
            found.depth = c.depth + 1;
            byCell[key] = found;
        }
        // A face reflection is its own inverse, so crossing the SAME face from
        // the neighbor returns to c — the back-link is `face`, not the opposite.
        found.link(face, c);
        c.link(face, found);
        return found;
    }

    /// Center of a cube in root-relative Minkowski coordinates.
    MVector center(Cube* c) {
        return (c.transform * MVector.origin()).normalized();
    }

    /// The cube containing `worldPos`, found by repeatedly crossing whichever face
    /// the point lies beyond in the current cube's local frame. This is exact —
    /// unlike greedy nearest-center descent, it never stalls in a local minimum,
    /// which matters because hyperbolic geodesics diverge and "closest center" is
    /// not monotone toward the target. Creates cubes along the way.
    Cube* findCube(Cube* start, MVector worldPos) {
        Cube* cur = start;
        int guard = 0;
        while (guard++ < 256) {
            MVector local = (inverseIsometry(cur.transform) * worldPos).normalized();
            int crossFace = faceBeyond(local);
            if (crossFace < 0) {
                return cur;
            }
            cur = ensureNeighbor(cur, crossFace);
        }
        return cur;
    }
}

/// Which face (if any) a local-frame point lies beyond. Returns the face whose
/// plane the point most exceeds, or -1 if the point is inside the cube. The face
/// boundary sits at Klein coordinate tanh(t) = SINH_T/COSH_T along its axis.
private int faceBeyond(MVector local) {
    enum float BOUND = 0.48587f; // tanh(in-radius t = 0.530638)
    int best = -1;
    float worst = BOUND;
    foreach (face; 0 .. FACES) {
        int axis = FACE_AXIS_SIGN[face][0];
        int sign = FACE_AXIS_SIGN[face][1];
        float klein = local.data[axis] / local.data[3];
        float signed = sign * klein;
        if (signed > worst) {
            worst = signed;
            best = face;
        }
    }
    return best;
}

/// Quantize a hyperboloid point to an integer cell key for dedup. Cube centers
/// are well separated (~one face distance apart), so coarse quantization of the
/// space coordinates uniquely identifies a cube without float-equality issues.
private long cellKey(MVector p) {
    enum float Q = 0.25f; // < half the min center separation
    long ix = lround(p.data[0] / Q);
    long iy = lround(p.data[1] / Q);
    long iz = lround(p.data[2] / Q);
    return (ix & 0x1FFFFF) | ((iy & 0x1FFFFF) << 21) | ((iz & 0x1FFFFF) << 42);
}

unittest {
    // Face crossing is a reflection (its own inverse), so crossing the same face
    // from the neighbor returns home.
    Graph* g = Graph.create();
    foreach (face; 0 .. FACES) {
        Cube* n = g.ensureNeighbor(g.root, face);
        assert(n !is null);
        assert(n !is g.root);
        assert(n.neighbor(face) is g.root);
    }
}

unittest {
    // {4,3,5}: exactly 5 cubes close around an edge. Reflecting alternately in two
    // adjacent faces is a rotation by 2*pi/5 about the edge, so 5 crossings return
    // to the root, and dedup keeps it a single cube (no infinite tree).
    Graph* g = Graph.create();
    Cube* cur = g.root;
    int returnedAt = -1;
    foreach (step; 0 .. 5) {
        cur = g.ensureNeighbor(cur, (step % 2 == 0) ? 1 : 3);
        if (cur is g.root) {
            returnedAt = step;
        }
    }
    assert(returnedAt == 4);
}

unittest {
    import common.math : Matrix4, translation, rotation;

    // findCube must track a moving camera without stalling — the bug that greedy
    // nearest-center descent hit because diverging geodesics break monotonicity.
    // Drive a camera in a straight line and assert its cube always contains it.
    Graph* g = Graph.create();
    Cube* anchor = g.root;
    Matrix4 cam = Matrix4.identity();
    foreach (step; 0 .. 60) {
        cam = cam * translation([0.08f, 0.0f, 0.0f]);
        MVector camPos = (cam * MVector.origin()).normalized();
        anchor = g.findCube(anchor, camPos);

        MVector local = (inverseIsometry(anchor.transform) * camPos).normalized();
        assert(faceBeyond(local) < 0);
    }
}

unittest {
    import common.math : Matrix4, translation, rotation;

    // The same, but with the pitched camera and local strafing the app actually
    // uses: camera looks down (-90 deg pitch) and is translated along its local x
    // each frame. The cube must still contain the camera (no lag).
    Graph* g = Graph.create();
    Cube* anchor = g.root;
    Matrix4 cam = translation([0.0f, 0.8f, 0.0f]) * rotation(1, 2, -1.5707963f);
    foreach (step; 0 .. 80) {
        cam = cam * translation([0.05f, 0.0f, 0.0f]);
        MVector camPos = (cam * MVector.origin()).normalized();
        anchor = g.findCube(anchor, camPos);

        MVector local = (inverseIsometry(anchor.transform) * camPos).normalized();
        assert(faceBeyond(local) < 0);
    }
}
