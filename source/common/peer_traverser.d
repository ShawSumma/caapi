module common.peer_traverser;

import common.array : Array;
import common.dodeca : Side, sideAdjacentTo;
import common.graph : Graph, NodeId;

// A peer is reached by walking up `pathLength` parent sides and back down the
// same number of child sides, so both paths are always that one length and
// never exceed two.
struct PeerNode {
    NodeId nodeId;
    Side[2] parentSides;
    Side[2] childSides;
    ubyte pathLength;

    static PeerNode viaOne(NodeId node, Side parentSide, Side childSide) {
        PeerNode peer;
        peer.nodeId = node;
        peer.parentSides[0] = parentSide;
        peer.childSides[0] = childSide;
        peer.pathLength = 1;
        return peer;
    }

    static PeerNode viaTwo(
        NodeId node,
        Side parentSide0,
        Side parentSide1,
        Side childSide0,
        Side childSide1,
    ) {
        PeerNode peer;
        peer.nodeId = node;
        peer.parentSides[0] = parentSide0;
        peer.parentSides[1] = parentSide1;
        peer.childSides[0] = childSide0;
        peer.childSides[1] = childSide1;
        peer.pathLength = 2;
        return peer;
    }

    NodeId node() const {
        return nodeId;
    }

    const(Side)[] parents() const return {
        return parentSides[0 .. pathLength];
    }

    const(Side)[] children() const return {
        return childSides[0 .. pathLength];
    }
}

Array!PeerNode ensurePeerNodes(ref Graph graph, NodeId baseNode) {
    Array!PeerNode nodes;

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

            nodes.push(PeerNode.viaOne(peerNode, parentSide, childSide));
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

                    nodes.push(PeerNode.viaTwo(
                        peerNode,
                        parentSide0,
                        parentSide1,
                        childSide0,
                        childSide1,
                    ));
                }
            }
        }
    }

    return nodes;
}
