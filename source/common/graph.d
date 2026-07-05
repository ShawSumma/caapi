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

/// Sentinel for "no node" in slot-based links.
enum uint NO_SLOT = uint.max;

// Nodes live in one contiguous slab indexed by slot; neighbor links are slot
// indices, so graph walks are array chasing with no hashing. The `slots` map
// is only consulted when entering the graph by NodeId. Slots are append-only
// and never move, but appending may reallocate the slab: never hold a
// Node/NodeContainer pointer across a call that can insert nodes — re-derive
// it from the slot instead.
struct Graph {
    NodeContainer[] containers;
    uint[NodeId] slots;
    ChunkLayout layout_;

    static Graph create(ubyte dimension) {
        Graph g;
        g.layout_ = ChunkLayout(dimension);
        g.containers.reserve(4096);
        g.addNode(NodeId.ROOT, NodeContainer.create(NodeId.ROOT, Side.init, false, 0));
        return g;
    }

    private uint addNode(NodeId id, NodeContainer nc) {
        uint slot = cast(uint) containers.length;
        containers ~= nc;
        slots[id] = slot;
        return slot;
    }

    ref const(ChunkLayout) layout() const return {
        return layout_;
    }

    uint len() const {
        return cast(uint) containers.length;
    }

    uint slotCount() const {
        return cast(uint) containers.length;
    }

    uint slotOf(NodeId id) const {
        const(uint)* s = id in slots;
        return s is null ? NO_SLOT : *s;
    }

    NodeId idAt(uint slot) const {
        return containers[slot].id;
    }

    ref inout(Node) nodeAt(uint slot) inout {
        return containers[slot].value;
    }

    uint neighborSlot(uint slot, Side which) const {
        return containers[slot].neighbors[which];
    }

    bool contains(NodeId node) const {
        return (node in slots) !is null;
    }

    NodeId neighbor(NodeId node, Side which) const {
        uint s = slotOf(node);
        if (s == NO_SLOT) {
            return NodeId.init;
        }
        uint n = containers[s].neighbors[which];
        return n == NO_SLOT ? NodeId.init : containers[n].id;
    }

    uint depth(NodeId node) const {
        return containers[slots[node]].depth;
    }

    ref inout(Node) opIndex(NodeId id) inout {
        return containers[slots[id]].value;
    }

    /// Single-lookup accessor for hot loops; null if the node doesn't exist.
    inout(Node)* tryGet(NodeId id) inout {
        inout(uint)* s = id in slots;
        return s is null ? null : &containers[*s].value;
    }

    NodeId ensureNeighbor(NodeId node, Side side) {
        uint s = slotOf(node);
        if (s == NO_SLOT) {
            return NodeId.init;
        }
        return containers[ensureNeighborSlot(s, side)].id;
    }

    uint ensureNeighborSlot(uint slot, Side side) {
        uint n = containers[slot].neighbors[side];
        if (n != NO_SLOT) {
            return n;
        }
        return insertChildSlot(slot, side);
    }

    NodeId insertChild(NodeId node, Side side) {
        uint s = slotOf(node);
        if (s == NO_SLOT) {
            return NodeId.init;
        }
        return containers[insertChildSlot(s, side)].id;
    }

    private uint insertChildSlot(uint nodeSlot, Side side) {
        struct ParentEntry {
            Side side;
            uint slot;
        }
        ParentEntry[3] parents;
        int parentCount = 0;

        foreach (cs; 0 .. cast(int)(Side.max + 1)) {
            Side candidateSide = cast(Side) cs;
            if (candidateSide == side) {
                parents[parentCount++] = ParentEntry(side, nodeSlot);
            }
            else if (sideAdjacentTo(candidateSide, side)
                       && isParentSideSlot(nodeSlot, candidateSide))
            {
                uint parentOfNode = containers[nodeSlot].neighbors[candidateSide];
                uint parentOfSubject = ensureNeighborSlot(parentOfNode, side);
                parents[parentCount++] = ParentEntry(candidateSide, parentOfSubject);
            }
        }

        Side primarySide = parents[0].side;
        NodeId primaryParent = containers[parents[0].slot].id;

        MurmurHash3!128 hasher;
        hasher.put(cast(ubyte[])(primaryParent.value[]));
        hasher.put(cast(ubyte) primarySide);
        ubyte[16] hash = hasher.finish();
        NodeId id;
        (cast(ubyte[])id.value[])[] = hash[0 .. 16];

        // The id is derived from (primary parent, side), so a node reached
        // through another path may already exist; link instead of clobbering.
        uint newSlot = slotOf(id);
        if (newSlot == NO_SLOT) {
            uint d = containers[nodeSlot].depth + 1;
            newSlot = addNode(id, NodeContainer.create(id, primarySide, true, d));
        }

        foreach (i; 0 .. parentCount) {
            linkNeighborSlots(newSlot, parents[i].slot, parents[i].side);
        }

        return newSlot;
    }

    private bool isParentSideSlot(uint slot, Side side) const {
        uint n = containers[slot].neighbors[side];
        if (n == NO_SLOT) {
            return false;
        }
        return containers[n].depth < containers[slot].depth;
    }

    private void linkNeighborSlots(uint a, uint b, Side side) {
        containers[a].neighbors[side] = b;
        containers[b].neighbors[side] = a;
    }

    struct ParentResult {
        Side side;
        NodeId id;
    }

    ParentResult[3] parents(NodeId node, out int count) const {
        ParentResult[3] results;
        count = 0;
        uint s = slotOf(node);
        if (s == NO_SLOT) {
            return results;
        }
        uint nodeDepth = containers[s].depth;
        foreach (sideIdx; 0 .. cast(int)(Side.max + 1)) {
            Side side = cast(Side) sideIdx;
            uint n = containers[s].neighbors[side];
            if (n == NO_SLOT) {
                continue;
            }
            if (containers[n].depth < nodeDepth) {
                results[count++] = ParentResult(side, containers[n].id);
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
        uint s = slotOf(nodeId);
        if (s == NO_SLOT) {
            return;
        }
        if (containers[s].value.state !is null) {
            return;
        }
        int pcount;
        ParentResult[3] ps = parents(nodeId, pcount);
        foreach (i; 0 .. pcount) {
            ensureNodeState(ps[i].id);
        }
        containers[s].value.state = cast(void*) NodeState.create(this, nodeId);
    }

    const(NodeState)* nodeState(NodeId nodeId) const {
        return cast(const(NodeState)*) containers[slots[nodeId]].value.state;
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

struct NodeContainer {
    Node value;
    NodeId id;
    Side primaryParentSide;
    bool hasPrimaryParent;
    uint depth;
    uint[Side.max + 1] neighbors = NO_SLOT;

    static NodeContainer create(NodeId id, Side primaryParentSide, bool hasPrimary, uint depth) {
        NodeContainer nc;
        nc.id = id;
        nc.primaryParentSide = primaryParentSide;
        nc.hasPrimaryParent = hasPrimary;
        nc.depth = depth;
        return nc;
    }
}
