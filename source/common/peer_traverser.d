module common.peer_traverser;

import common.dodeca : Side, sideAdjacentTo;
import common.graph : Graph, NodeId;

struct PeerNode {
    NodeId nodeId;
    Side[] parentPath;
    Side[] childPath;

    NodeId node() const {
        return nodeId;
    }
}

PeerNode[] ensurePeerNodes(ref Graph graph, NodeId baseNode) {
    PeerNode[] nodes;

    foreach (parentSideIdx; 0 .. 12) {
        Side parentSide = cast(Side) parentSideIdx;
        NodeId parentNode = graph.neighbor(baseNode, parentSide);
        if (parentNode == NodeId.init) {
            continue;
        }
        if (graph.depth(parentNode) >= graph.depth(baseNode)) {
            continue;
        }

        foreach (childSideIdx; 0 .. 12) {
            Side childSide = cast(Side) childSideIdx;
            if (childSide == parentSide) {
                continue;
            }
            if (!sideAdjacentTo(childSide, parentSide)) {
                continue;
            }

            NodeId peerNode = graph.ensureNeighbor(parentNode, childSide);
            if (peerNode == NodeId.init) {
                continue;
            }
            if (peerNode == baseNode) {
                continue;
            }

            nodes ~= PeerNode(peerNode, [parentSide], [childSide]);
        }
    }

    foreach (ps0; 0 .. 12) {
        Side parentSide0 = cast(Side) ps0;
        NodeId parentNode0 = graph.neighbor(baseNode, parentSide0);
        if (parentNode0 == NodeId.init) {
            continue;
        }
        if (graph.depth(parentNode0) >= graph.depth(baseNode)) {
            continue;
        }

        foreach (ps1; 0 .. 12) {
            Side parentSide1 = cast(Side) ps1;
            NodeId parentNode1 = graph.neighbor(parentNode0, parentSide1);
            if (parentNode1 == NodeId.init) {
                continue;
            }
            if (graph.depth(parentNode1) >= graph.depth(parentNode0)) {
                continue;
            }

            foreach (cs0; 0 .. 12) {
                Side childSide0 = cast(Side) cs0;
                NodeId child0 = graph.ensureNeighbor(parentNode1, childSide0);
                if (child0 == NodeId.init) {
                    continue;
                }

                foreach (cs1; 0 .. 12) {
                    Side childSide1 = cast(Side) cs1;
                    NodeId peerNode = graph.ensureNeighbor(child0, childSide1);
                    if (peerNode == NodeId.init) {
                        continue;
                    }
                    if (peerNode == baseNode) {
                        continue;
                    }

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
