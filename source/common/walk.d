module common.walk;

import common.geometry : SIDES, sideTransform;
import common.graph : Node;
import common.math : Matrix4;

/// A node paired with its local frame relative to the walk's start node. The
/// frame is computed transiently by composing side reflections along the BFS
/// edges, bounded to N shells, so it never accumulates past the horizon and
/// never overflows. Frames are NOT stored on nodes — identity stays topological.
struct Placed {
    Node* node;
    Matrix4 frame;
}

/// BFS `shells` deep from `start`, returning each reachable node with its local
/// frame. Pure read-only walk over already-linked nodes (the worldgen thread
/// creates them; callers here only read).
Placed[] walk(Node* start, int shells) {
    Placed[] order = [Placed(start, Matrix4.identity())];
    int[Node*] depth;
    depth[start] = 0;

    for (size_t i = 0; i < order.length; i++) {
        int d = depth[order[i].node];
        if (d >= shells) {
            continue;
        }
        Node* node = order[i].node;
        Matrix4 frame = order[i].frame;
        foreach (side; 0 .. SIDES) {
            Node* n = node.neighbor(side);
            if (n is null || (n in depth) !is null) {
                continue;
            }
            depth[n] = d + 1;
            order ~= Placed(n, frame * sideTransform(side));
        }
    }
    return order;
}
