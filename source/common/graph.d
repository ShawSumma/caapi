module common.graph;

import common.dodeca;
import common.math;
import common.node;
import common.chunks;
import std.digest.murmurhash : MurmurHash3;

/// Unique 128-bit identifier for a dodecahedral node in the graph.
struct NodeId {
    ulong[2] value;

    static immutable NodeId ROOT = NodeId([0, 0]);

    bool opEquals(const NodeId other) const {
        return value == other.value;
    }

    size_t toHash() const nothrow @safe {
        return cast(size_t)(value[0] ^ value[1]);
    }
}

/// Graph of the right dodecahedral tiling of H^3
struct Graph {
    private NodeContainer[NodeId] nodes;
    private ChunkLayout layout_;

    static Graph create(ubyte dimension) {
        Graph g;
        g.layout_ = ChunkLayout(dimension);
        g.nodes[NodeId.ROOT] = NodeContainer.create(Side.init, false, 0);
        return g;
    }

    ref const(ChunkLayout) layout() const return {
        return layout_;
    }

    uint len() const {
        return cast(uint) nodes.length;
    }

    bool contains(NodeId node) const {
        return (node in nodes) !is null;
    }

    NodeId neighbor(NodeId node, Side which) const {
        auto nc = node in nodes;
        if (nc is null) return NodeId.init;
        auto n = (*nc).neighbors[which];
        return n.valid ? n.id : NodeId.init;
    }

    uint depth(NodeId node) const {
        return nodes[node].depth;
    }

    ref inout(Node) opIndex(NodeId id) inout {
        return nodes[id].value;
    }

    /// Ensures that the neighbor node exists
    NodeId ensureNeighbor(NodeId node, Side side) {
        auto nc = node in nodes;
        if (nc is null) return NodeId.init;
        auto n = (*nc).neighbors[side];
        if (n.valid) return n.id;
        return insertChild(node, side);
    }

    bool isParentSide(NodeId node, Side side) const {
        auto nc = node in nodes;
        if (nc is null) return false;
        auto n = (*nc).neighbors[side];
        if (!n.valid) return false;
        auto neighborNC = n.id in nodes;
        if (neighborNC is null) return false;
        return (*neighborNC).depth < (*nc).depth;
    }

    NodeId insertChild(NodeId node, Side side) {
        // Collect all parents of the subject, ensuring they exist.
        // Matches Rust's populate_parents_of_subject.
        // Each parent is (side shared with subject, parent NodeId).
        // Sorted by side enum order since we iterate in order.
        struct ParentEntry {
            Side side;
            NodeId id;
        }
        ParentEntry[3] parents;
        int parentCount = 0;

        foreach (cs; 0 .. SIDE_COUNT) {
            auto candidateSide = cast(Side) cs;
            if (candidateSide == side) {
                parents[parentCount++] = ParentEntry(side, node);
            } else if (sideAdjacentTo(candidateSide, side)
                       && isParentSide(node, candidateSide))
            {
                auto parentOfNode = neighbor(node, candidateSide);
                auto parentOfSubject = ensureNeighbor(parentOfNode, side);
                parents[parentCount++] = ParentEntry(candidateSide, parentOfSubject);
            }
        }

        // First parent in enum order is the canonical primary parent.
        auto primarySide = parents[0].side;
        auto primaryParent = parents[0].id;

        MurmurHash3!128 hasher;
        hasher.put(cast(ubyte[])(primaryParent.value[]));
        hasher.put(cast(ubyte) primarySide);
        auto hash = hasher.finish();
        NodeId id;
        (cast(ubyte[])id.value[])[] = hash[0 .. 16];

        uint d = nodes[node].depth + 1;
        nodes[id] = NodeContainer.create(primarySide, true, d);

        foreach (i; 0 .. parentCount) {
            linkNeighbors(id, parents[i].id, parents[i].side);
        }

        return id;
    }

    private void linkNeighbors(NodeId a, NodeId b, Side side) {
        if (auto nc = a in nodes) {
            (*nc).neighbors[side] = OptionalNodeId(b, true);
        }
        if (auto nc = b in nodes) {
            (*nc).neighbors[side] = OptionalNodeId(a, true);
        }
    }

    struct ParentResult { Side side; NodeId id; }

    /// Returns up to 3 parent (side, nodeId) pairs — neighbors with lower depth.
    ParentResult[3] parents(NodeId node, out int count) const {
        ParentResult[3] results;
        count = 0;
        auto nc = node in nodes;
        if (nc is null) {
            return results;
        }
        uint nodeDepth = (*nc).depth;
        foreach (sideIdx; 0 .. SIDE_COUNT) {
            auto side = cast(Side) sideIdx;
            auto n = (*nc).neighbors[side];
            if (!n.valid) {
                continue;
            }
            auto neighborNC = n.id in nodes;
            if (neighborNC is null) {
                continue;
            }
            if ((*neighborNC).depth < nodeDepth) {
                results[count++] = ParentResult(side, n.id);
                if (count >= 3) {
                    break;
                }
            }
        }
        return results;
    }

    /// The node ID is already its hash (matches Rust graph.hash_of).
    ulong hashOf(NodeId node) const {
        return node.value[0] ^ node.value[1];
    }

    /// Lazily compute and return the NodeState for a node.
    void ensureNodeState(NodeId nodeId) {
        import common.worldgen.mod_ : NodeState;
        auto nc = nodeId in nodes;
        if (nc is null) {
            return;
        }
        if ((*nc).value.state !is null) {
            return;
        }
        // Ensure parents have state first
        int pcount;
        auto ps = parents(nodeId, pcount);
        foreach (i; 0 .. pcount) {
            ensureNodeState(ps[i].id);
        }
        (*nc).value.state = cast(void*) NodeState.create(this, nodeId);
    }

    /// Return the NodeState (must have been ensured first).
    auto nodeState(NodeId nodeId) const {
        import common.worldgen.mod_ : NodeState;
        return cast(const(NodeState)*) nodes[nodeId].value.state;
    }

    /// Normalize a transform to find the closest node
    NodeId normalizeTransform(NodeId reference, ref MIsometry!float transform) const {
        auto location = transform * MPoint!float.origin();
        bool moved = true;
        while (moved) {
            moved = false;
            foreach (sideIdx; 0 .. SIDE_COUNT) {
                auto side = cast(Side) sideIdx;
                if (!sideIsFacing(side, location)) {
                    continue;
                }
                auto n = neighbor(reference, side);
                if (n == NodeId.init) {
                    continue;
                }
                reference = n;
                auto refl = sideReflection(side);
                location = refl * location;
                transform = refl * transform;
                moved = true;
                break;
            }
        }
        return reference;
    }
}

private struct OptionalNodeId {
    NodeId id;
    bool valid;
}

private struct NodeContainer {
    Node value;
    Side primaryParentSide;
    bool hasPrimaryParent;
    uint depth;
    OptionalNodeId[SIDE_COUNT] neighbors;

    static NodeContainer create(Side primaryParentSide, bool hasPrimary, uint depth) {
        NodeContainer nc;
        nc.primaryParentSide = primaryParentSide;
        nc.hasPrimaryParent = hasPrimary;
        nc.depth = depth;
        return nc;
    }
}
