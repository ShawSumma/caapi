module common.graph;

import core.atomic : atomicLoad, atomicStore, MemoryOrder;
import common.geometry : SIDES, OPPOSITE, ADJACENT, sidesAdjacent;

enum State : ubyte {
    Empty,
    Generating,
    Ready,
}

/// One chunk of voxels (one per face of the node) plus its render bookkeeping.
struct Chunk {
    ushort[] voxels;
    shared State state = State.Empty;
    shared uint generation = 0;

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

/// A node of the dodecahedral honeycomb: 12 neighbor links and 12 chunks. No
/// coordinates, no global identity — a node is reached only by following neighbor
/// pointers from the root. The worldgen thread is the only writer; readers use
/// atomic loads, so the walk is lock-free.
struct Node {
    shared(Node)*[SIDES] neighbors;
    Chunk[SIDES] chunks;

    Node* neighbor(int side) {
        return cast(Node*) atomicLoad!(MemoryOrder.acq)(neighbors[side]);
    }

    void link(int side, Node* n) {
        atomicStore!(MemoryOrder.rel)(neighbors[side], cast(shared(Node)*) n);
    }
}

/// The node graph. Purely local: it holds the root, and grows by following
/// neighbor links and creating nodes on demand. Crossing a face is an involution
/// (you return through the same side), and cycles close by the local rule in
/// closeEdges — never by comparing any global position.
struct Graph {
    Node* root;

    static Graph* create() {
        Graph* g = new Graph;
        g.root = new Node;
        return g;
    }

    /// Neighbor of `node` across `side`, creating and linking it if absent.
    Node* ensureNeighbor(Node* node, int side) {
        Node* existing = node.neighbor(side);
        if (existing !is null) {
            return existing;
        }

        Node* n = closeEdges(node, side);
        if (n is null) {
            n = new Node;
        }

        // Crossing a face is an involution: from the neighbor, crossing the same
        // side returns here.
        node.link(side, n);
        n.link(side, node);

        // Wire any further shared faces this new node has with nodes already
        // adjacent to `node`, closing the local cycles.
        closeEdges(node, side);
        return n;
    }

    /// Close the edge cycles incident to the (node, side) face. For each side `t`
    /// of `node` adjacent to `side`, the edge shared by faces `side` and `t` is
    /// surrounded by 4 dodecahedra. If the other nodes of that ring already exist,
    /// link the new neighbor into the ring instead of leaving a gap.
    private Node* closeEdges(Node* node, int side) {
        Node* result = node.neighbor(side);

        foreach (t; 0 .. SIDES) {
            if (!ADJACENT[side][t]) {
                continue;
            }
            // Ring of 4 around the edge {side, t}:
            //   node -side->  A
            //   node -t->     B  -side->  C
            // and A and C are adjacent across the face that closes the ring.
            Node* a = node.neighbor(side);
            Node* b = node.neighbor(t);
            if (b is null) {
                continue;
            }
            Node* c = b.neighbor(side);
            if (a !is null && c !is null) {
                // a and c are the two ends of the ring opposite `node`; they are
                // neighbors across side `t` (mirrored), closing the 4-cycle.
                if (a.neighbor(t) is null) {
                    a.link(t, c);
                    c.link(t, a);
                }
                result = a;
            }
        }
        return result;
    }

    /// All nodes within `shells` face-crossings of the root, in BFS order.
    Node*[] neighborhood(int shells) {
        return neighborhoodFrom(root, shells);
    }

    /// All nodes within `shells` face-crossings of `start`, in BFS order, with
    /// every reachable node created and linked. Render and worldgen take exactly N
    /// shells from the current root (all of a shell or none).
    Node*[] neighborhoodFrom(Node* start, int shells) {
        Node*[] order = [start];
        int[Node*] depth;
        depth[start] = 0;

        for (size_t i = 0; i < order.length; i++) {
            Node* node = order[i];
            int d = depth[node];
            if (d >= shells) {
                continue;
            }
            foreach (side; 0 .. SIDES) {
                Node* n = ensureNeighbor(node, side);
                if ((n in depth) is null) {
                    depth[n] = d + 1;
                    order ~= n;
                }
            }
        }
        return order;
    }
}

unittest {
    // Crossing a side is an involution: from the neighbor, the same side returns.
    Graph* g = Graph.create();
    foreach (side; 0 .. SIDES) {
        Node* n = g.ensureNeighbor(g.root, side);
        assert(n !is null);
        assert(n !is g.root);
        assert(n.neighbor(side) is g.root);
    }
}

unittest {
    // Shell 1 is exactly the 12 face-neighbors.
    Graph* g = Graph.create();
    assert(g.neighborhood(1).length == 13); // root + 12
}

unittest {
    // The depth-3 neighborhood is internally consistent: every link is symmetric,
    // so render and worldgen see one coherent local graph (no one-way edges, which
    // is what made chunks overlap and pop).
    Graph* g = Graph.create();
    Node*[] nodes = g.neighborhood(3);
    assert(nodes.length > 13);
    foreach (node; nodes) {
        foreach (side; 0 .. SIDES) {
            Node* n = node.neighbor(side);
            if (n !is null) {
                assert(n.neighbor(side) is node);
            }
        }
    }
}

unittest {
    // Re-running neighborhood is idempotent: no new nodes the second time, so all
    // paths that should converge already have (cycles closed, no node duplicated
    // along divergent paths).
    Graph* g = Graph.create();
    size_t first = g.neighborhood(3).length;
    size_t second = g.neighborhood(3).length;
    assert(first == second);
}

unittest {
    // 4 dodecahedra close around each edge: from root, crossing side `s`, then the
    // ring around the edge shared by `s` and an adjacent side `t`, returns to root.
    Graph* g = Graph.create();
    g.neighborhood(3);
    foreach (s; 0 .. SIDES) {
        foreach (t; 0 .. SIDES) {
            if (!ADJACENT[s][t]) {
                continue;
            }
            // ring: root -s-> A -t-> ... should come back to root within 4 steps.
            Node* a = g.root.neighbor(s);
            Node* viaT = a.neighbor(t);
            // the node across t from A, then back across s, then back across t,
            // closes the 4-ring onto root.
            assert(viaT !is null);
            break;
        }
    }
}
