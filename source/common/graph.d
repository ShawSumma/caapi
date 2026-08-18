module common.graph;

import common.array : Array, allocSlice, freeSlice;
import common.hash_map : HashMap;
import common.murmur : MurmurHash3x64;
import common.dodeca : Side, sideAdjacentTo, sideIsFacing, sideReflection;
import common.math : MIsometry, MPoint;
import common.node : Node, ChunkLayout;
import common.worldgen : NodeState;

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

// Sentinel for "no node" in slot-based links.
enum uint NO_SLOT = uint.max;

// Nodes live in fixed-size slabs indexed by slot; neighbor links are slot
// indices, so graph walks are array chasing with no hashing. The `slots` map
// is only consulted when entering the graph by NodeId. Growth never moves
// existing nodes (a flat array at ~1KB/node memcpys tens of MB on doubling —
// a visible frame hitch), so slots and node pointers are both stable.
enum uint SLAB_SHIFT = 12;
enum uint SLAB_SIZE = 1u << SLAB_SHIFT;
enum uint SLAB_MASK = SLAB_SIZE - 1;

struct Graph {
    Array!(NodeContainer[]) slabs;
    uint nodeCount;
    HashMap!(NodeId, uint) slots;
    ChunkLayout chunkLayout;

    ref inout(NodeContainer) container(uint slot) inout {
        return slabs[slot >> SLAB_SHIFT][slot & SLAB_MASK];
    }

    static Graph create(ubyte dimension) {
        Graph g;
        g.chunkLayout = ChunkLayout(dimension);
        g.addNode(NodeId.ROOT, NodeContainer.create(NodeId.ROOT, Side.init, false, 0));
        return g;
    }

    void release() {
        foreach (i; 0 .. slabs.length()) {
            NodeContainer[] slab = slabs[i];
            freeSlice(slab);
        }
        slabs.release();
        slots.release();
    }

    uint addNode(NodeId id, NodeContainer nc) {
        uint slot = nodeCount;
        if ((slot >> SLAB_SHIFT) == slabs.length()) {
            slabs.push(allocSlice!NodeContainer(SLAB_SIZE));
        }
        container(slot) = nc;
        nodeCount = nodeCount + 1;
        slots.insert(id, slot);
        return slot;
    }

    ref const(ChunkLayout) layout() const return {
        return chunkLayout;
    }

    uint len() const {
        return nodeCount;
    }

    uint slotCount() const {
        return nodeCount;
    }

    uint slotOf(NodeId id) const {
        size_t found = slots.findSlot(id);
        if (found == slots.capacity) {
            return NO_SLOT;
        }
        return slots.values[found];
    }

    NodeId idAt(uint slot) const {
        return container(slot).id;
    }

    ref inout(Node) nodeAt(uint slot) inout {
        return container(slot).value;
    }

    uint neighborSlot(uint slot, Side which) const {
        return container(slot).neighbors[which];
    }

    bool contains(NodeId node) const {
        return slotOf(node) != NO_SLOT;
    }

    NodeId neighbor(NodeId node, Side which) const {
        uint s = slotOf(node);
        if (s == NO_SLOT) {
            return NodeId.init;
        }
        uint n = container(s).neighbors[which];
        if (n == NO_SLOT) {
            return NodeId.init;
        }
        return container(n).id;
    }

    // The one parent a node was first reached through. Depth strictly drops
    // across it, so following it always terminates at the root.
    bool primaryParent(uint slot, ref Side side, ref uint parentSlot) const {
        if (!container(slot).hasPrimaryParent) {
            return false;
        }
        side = container(slot).primaryParentSide;
        parentSlot = container(slot).neighbors[side];
        return parentSlot != NO_SLOT;
    }

    uint depth(NodeId node) const {
        return container(slotOf(node)).depth;
    }

    ref inout(Node) opIndex(NodeId id) inout {
        return container(slotOf(id)).value;
    }

    // Single-lookup accessor for hot loops; null if the node doesn't exist.
    inout(Node)* tryGet(NodeId id) inout {
        uint s = slotOf(id);
        if (s == NO_SLOT) {
            return null;
        }
        return &container(s).value;
    }

    NodeId ensureNeighbor(NodeId node, Side side) {
        uint s = slotOf(node);
        if (s == NO_SLOT) {
            return NodeId.init;
        }
        return container(ensureNeighborSlot(s, side)).id;
    }

    uint ensureNeighborSlot(uint slot, Side side) {
        uint n = container(slot).neighbors[side];
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
        return container(insertChildSlot(s, side)).id;
    }

    uint insertChildSlot(uint nodeSlot, Side side) {
        struct ParentEntry {
            Side side;
            uint slot;
        }
        ParentEntry[3] parents;
        int parentCount = 0;

        foreach (cs; 0 .. cast(int)(Side.max + 1)) {
            Side candidateSide = cast(Side) cs;
            if (candidateSide == side) {
                parents[parentCount] = ParentEntry(side, nodeSlot);
                parentCount = parentCount + 1;
            } else if (sideAdjacentTo(candidateSide, side)
                    && isParentSideSlot(nodeSlot, candidateSide)) {
                uint parentOfNode = container(nodeSlot).neighbors[candidateSide];
                uint parentOfSubject = ensureNeighborSlot(parentOfNode, side);
                parents[parentCount] = ParentEntry(candidateSide, parentOfSubject);
                parentCount = parentCount + 1;
            }
        }

        Side primarySide = parents[0].side;
        NodeId primaryParent = container(parents[0].slot).id;

        MurmurHash3x64 hasher;
        hasher.put(cast(ubyte[])(primaryParent.value[]));
        hasher.putByte(cast(ubyte) primarySide);
        ubyte[16] hash = hasher.finish();
        NodeId id;
        (cast(ubyte[])id.value[])[] = hash[0 .. 16];

        // The id is derived from (primary parent, side), so a node reached
        // through another path may already exist; link instead of clobbering.
        uint newSlot = slotOf(id);
        if (newSlot == NO_SLOT) {
            uint d = container(nodeSlot).depth + 1;
            newSlot = addNode(id, NodeContainer.create(id, primarySide, true, d));
        }

        foreach (i; 0 .. parentCount) {
            linkNeighborSlots(newSlot, parents[i].slot, parents[i].side);
        }

        return newSlot;
    }

    bool isParentSideSlot(uint slot, Side side) const {
        uint n = container(slot).neighbors[side];
        if (n == NO_SLOT) {
            return false;
        }
        return container(n).depth < container(slot).depth;
    }

    void linkNeighborSlots(uint a, uint b, Side side) {
        container(a).neighbors[side] = b;
        container(b).neighbors[side] = a;
    }

    struct ParentResult {
        Side side;
        NodeId id;
    }

    // A node has at most three parents, so the count travels with the array
    // rather than through an output parameter.
    struct ParentList {
        ParentResult[3] items;
        int count;
    }

    ParentList parents(NodeId node) const {
        ParentList result;
        uint s = slotOf(node);
        if (s == NO_SLOT) {
            return result;
        }
        uint nodeDepth = container(s).depth;
        foreach (sideIdx; 0 .. cast(int)(Side.max + 1)) {
            Side side = cast(Side) sideIdx;
            uint n = container(s).neighbors[side];
            if (n == NO_SLOT) {
                continue;
            }
            if (container(n).depth < nodeDepth) {
                result.items[result.count] = ParentResult(side, container(n).id);
                result.count = result.count + 1;
                if (result.count >= 3) {
                    break;
                }
            }
        }
        return result;
    }

    ulong hashOf(NodeId node) const {
        return node.value[0] ^ node.value[1];
    }

    void ensureNodeState(NodeId nodeId) {
        uint s = slotOf(nodeId);
        if (s == NO_SLOT) {
            return;
        }
        if (container(s).value.state !is null) {
            return;
        }
        ParentList ps = parents(nodeId);
        foreach (i; 0 .. ps.count) {
            ensureNodeState(ps.items[i].id);
        }
        container(s).value.state = cast(void*) NodeState.create(this, nodeId);
    }

    const(NodeState)* nodeState(NodeId nodeId) const {
        return cast(const(NodeState)*) container(slotOf(nodeId)).value.state;
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

    static NodeContainer create(
        NodeId id,
        Side primaryParentSide,
        bool hasPrimary,
        uint depth,
    ) {
        NodeContainer nc;
        nc.id = id;
        nc.primaryParentSide = primaryParentSide;
        nc.hasPrimaryParent = hasPrimary;
        nc.depth = depth;
        return nc;
    }
}
