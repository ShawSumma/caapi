module common.graph;

import std.digest.murmurhash : MurmurHash3;
import common.dodeca : Side, sideAdjacentTo, sideIsFacing, sideReflection;
import common.math : MIsometry, MPoint;
import common.node : Node, ChunkLayout;
import common.worldgen.mod_ : NodeState;

struct NodeId {
    ulong[2] value;

    static immutable NodeId ROOT = NodeId([1, 1]);

    bool opEquals(const NodeId other) const {
        return value == other.value;
    }

    size_t toHash() const nothrow @safe {
        return cast(size_t)(value[0] + value[1] * 0x9E3779B97F4A7C15);
    }
}

struct Graph {
    NodeContainer[NodeId] nodes;
    ChunkLayout layout_;

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
        const(NodeContainer)* nc = node in nodes;
        if (nc is null) {
            return NodeId.init;
        }
        OptionalNodeId n = (*nc).neighbors[which];
        if (n.valid) {
            return n.id;
        }
        return NodeId.init;
    }

    uint depth(NodeId node) const {
        return nodes[node].depth;
    }

    ref inout(Node) opIndex(NodeId id) inout {
        return nodes[id].value;
    }

    NodeId ensureNeighbor(NodeId node, Side side) {
        NodeContainer* nc = node in nodes;
        if (nc is null) {
            return NodeId.init;
        }
        OptionalNodeId n = (*nc).neighbors[side];
        if (n.valid) {
            return n.id;
        }
        return insertChild(node, side);
    }

    bool isParentSide(NodeId node, Side side) const {
        const(NodeContainer)* nc = node in nodes;
        if (nc is null) {
            return false;
        }
        OptionalNodeId n = (*nc).neighbors[side];
        if (!n.valid) {
            return false;
        }
        const(NodeContainer)* neighborNC = n.id in nodes;
        if (neighborNC is null) {
            return false;
        }
        return (*neighborNC).depth < (*nc).depth;
    }

    NodeId insertChild(NodeId node, Side side) {
        struct ParentEntry {
            Side side;
            NodeId id;
        }
        ParentEntry[3] parents;
        int parentCount = 0;

        foreach (cs; 0 .. cast(int)(Side.max + 1)) {
            Side candidateSide = cast(Side) cs;
            if (candidateSide == side) {
                parents[parentCount++] = ParentEntry(side, node);
            }
            else if (sideAdjacentTo(candidateSide, side)
                       && isParentSide(node, candidateSide))
            {
                NodeId parentOfNode = neighbor(node, candidateSide);
                NodeId parentOfSubject = ensureNeighbor(parentOfNode, side);
                parents[parentCount++] = ParentEntry(candidateSide, parentOfSubject);
            }
        }

        Side primarySide = parents[0].side;
        NodeId primaryParent = parents[0].id;

        MurmurHash3!128 hasher;
        hasher.put(cast(ubyte[])(primaryParent.value[]));
        hasher.put(cast(ubyte) primarySide);
        ubyte[16] hash = hasher.finish();
        NodeId id;
        (cast(ubyte[])id.value[])[] = hash[0 .. 16];

        uint d = nodes[node].depth + 1;
        nodes[id] = NodeContainer.create(primarySide, true, d);

        foreach (i; 0 .. parentCount) {
            linkNeighbors(id, parents[i].id, parents[i].side);
        }

        return id;
    }

    void linkNeighbors(NodeId a, NodeId b, Side side) {
        NodeContainer* nca = a in nodes;
        if (nca !is null) {
            (*nca).neighbors[side] = OptionalNodeId(b, true);
        }
        NodeContainer* ncb = b in nodes;
        if (ncb !is null) {
            (*ncb).neighbors[side] = OptionalNodeId(a, true);
        }
    }

    struct ParentResult {
        Side side;
        NodeId id;
    }

    ParentResult[3] parents(NodeId node, out int count) const {
        ParentResult[3] results;
        count = 0;
        const(NodeContainer)* nc = node in nodes;
        if (nc is null) {
            return results;
        }
        uint nodeDepth = (*nc).depth;
        foreach (sideIdx; 0 .. cast(int)(Side.max + 1)) {
            Side side = cast(Side) sideIdx;
            OptionalNodeId n = (*nc).neighbors[side];
            if (!n.valid) {
                continue;
            }
            const(NodeContainer)* neighborNC = n.id in nodes;
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

    ulong hashOf(NodeId node) const {
        return node.value[0] ^ node.value[1];
    }

    void ensureNodeState(NodeId nodeId) {
        NodeContainer* nc = nodeId in nodes;
        if (nc is null) {
            return;
        }
        if ((*nc).value.state !is null) {
            return;
        }
        int pcount;
        ParentResult[3] ps = parents(nodeId, pcount);
        foreach (i; 0 .. pcount) {
            ensureNodeState(ps[i].id);
        }
        (*nc).value.state = cast(void*) NodeState.create(this, nodeId);
    }

    const(NodeState)* nodeState(NodeId nodeId) const {
        return cast(const(NodeState)*) nodes[nodeId].value.state;
    }

    NodeId normalizeTransform(NodeId reference, ref MIsometry!float transform) const {
        MPoint!float location = transform * MPoint!float.origin();
        bool moved = true;
        while (moved) {
            moved = false;
            foreach (sideIdx; 0 .. cast(int)(Side.max + 1)) {
                Side side = cast(Side) sideIdx;
                if (!sideIsFacing(side, location)) {
                    continue;
                }
                NodeId n = neighbor(reference, side);
                if (n == NodeId.init) {
                    continue;
                }
                reference = n;
                MIsometry!float refl = sideReflection(side);
                location = refl * location;
                transform = refl * transform;
                moved = true;
                break;
            }
        }
        return reference;
    }
}

struct OptionalNodeId {
    NodeId id;
    bool valid;
}

struct NodeContainer {
    Node value;
    Side primaryParentSide;
    bool hasPrimaryParent;
    uint depth;
    OptionalNodeId[Side.max + 1] neighbors;

    static NodeContainer create(Side primaryParentSide, bool hasPrimary, uint depth) {
        NodeContainer nc;
        nc.primaryParentSide = primaryParentSide;
        nc.hasPrimaryParent = hasPrimary;
        nc.depth = depth;
        return nc;
    }
}
