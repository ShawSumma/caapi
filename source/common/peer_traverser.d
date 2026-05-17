module common.peer_traverser;

import common.dodeca;
import common.graph;

/// A peer node is a node that can be reached from a base node by going up to its parents
/// and then back down to children.
struct PeerNode {
    NodeId nodeId;
    Side[] parentPath;
    Side[] childPath;

    NodeId node() const { return nodeId; }
}

/// Returns all peer nodes for the given base node, expanding the graph if necessary.
PeerNode[] ensurePeerNodes(ref Graph graph, NodeId baseNode) {
    PeerNode[] nodes;

    // Depth 1: go up one parent, come down one child
    foreach (parentSideIdx; 0 .. SIDE_COUNT) {
        auto parentSide = cast(Side) parentSideIdx;
        auto parentNode = graph.neighbor(baseNode, parentSide);
        if (parentNode == NodeId.init) continue;
        if (graph.depth(parentNode) >= graph.depth(baseNode)) continue;

        foreach (childSideIdx; 0 .. SIDE_COUNT) {
            auto childSide = cast(Side) childSideIdx;
            if (childSide == parentSide) continue;
            if (!sideAdjacentTo(childSide, parentSide)) continue;

            auto peerNode = graph.ensureNeighbor(parentNode, childSide);
            if (peerNode == NodeId.init) continue;
            if (peerNode == baseNode) continue;

            nodes ~= PeerNode(peerNode, [parentSide], [childSide]);
        }
    }

    // Depth 2 paths: go up two parents, come down two children
    foreach (ps0; 0 .. SIDE_COUNT) {
        auto parentSide0 = cast(Side) ps0;
        auto parentNode0 = graph.neighbor(baseNode, parentSide0);
        if (parentNode0 == NodeId.init) continue;
        if (graph.depth(parentNode0) >= graph.depth(baseNode)) continue;

        foreach (ps1; 0 .. SIDE_COUNT) {
            auto parentSide1 = cast(Side) ps1;
            auto parentNode1 = graph.neighbor(parentNode0, parentSide1);
            if (parentNode1 == NodeId.init) continue;
            if (graph.depth(parentNode1) >= graph.depth(parentNode0)) continue;

            foreach (cs0; 0 .. SIDE_COUNT) {
                auto childSide0 = cast(Side) cs0;
                auto child0 = graph.ensureNeighbor(parentNode1, childSide0);
                if (child0 == NodeId.init) continue;

                foreach (cs1; 0 .. SIDE_COUNT) {
                    auto childSide1 = cast(Side) cs1;
                    auto peerNode = graph.ensureNeighbor(child0, childSide1);
                    if (peerNode == NodeId.init) continue;
                    if (peerNode == baseNode) continue;

                    // Skip if we can reach it via a shorter path
                    if (graph.depth(peerNode) <= graph.depth(baseNode) + 1) {
                        continue;
                    }

                    nodes ~= PeerNode(peerNode, [parentSide0, parentSide1], [childSide0, childSide1]);
                }
            }
        }
    }

    return nodes;
}
