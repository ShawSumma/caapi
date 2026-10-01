module common.graph;

import core.stdc.string : memcpy;
import common.dodeca : SIDE_COUNT, Side, VERTEX_COUNT, sideAdjacentTo, sideIsFacing, sideReflection;
import common.hash_map : HashMap;
import common.math : MIsometry, MPoint;
import common.murmur : murmurHash3;
import common.node : ChunkLayout, Node;
import common.slab : Slab;
import common.worldgen.generation : NodeState, createNodeState;

enum ulong NODE_HASH_MULTIPLIER = 0x9E3779B97F4A7C15;

struct NodeId {
    ulong[2] value;

    bool opEquals(const NodeId other) const {
        return value[0] == other.value[0] && value[1] == other.value[1];
    }

    size_t toHash() const {
        return cast(size_t)(value[0] + value[1] * NODE_HASH_MULTIPLIER);
    }
}

enum NodeId ROOT_NODE = NodeId([1, 1]);
enum NodeId NO_NODE = NodeId.init;
enum uint NO_SLOT = uint.max;
enum uint MAX_PARENTS = 3;

struct NodeContainer {
    Node value;
    NodeId id;
    uint[SIDE_COUNT] neighbors;
    uint depth;
}

struct ParentLink {
    NodeId id;
    Side side;
}

struct ParentList {
    ParentLink[MAX_PARENTS] links;
    uint count;
}

struct ParentEntry {
    uint slot;
    Side side;
}

ulong nodeSpice(NodeId node) {
    return node.value[0] ^ node.value[1];
}

Graph createGraph(ubyte dimension) {
    Graph graph;
    graph.layout = ChunkLayout(dimension);
    graph.addNode(ROOT_NODE, 0);
    return graph;
}

struct Graph {
    Slab!NodeContainer nodes;
    HashMap!(NodeId, uint) slots;
    ChunkLayout layout;
    uint nodeCount;

    inout(NodeContainer)* container(uint slot) inout {
        return nodes.at(slot);
    }

    uint addNode(NodeId id, uint depth) {
        uint slot = nodeCount;
        nodes.ensure(slot + 1);
        NodeContainer* added = container(slot);
        added.id = id;
        added.depth = depth;
        foreach (side; 0 .. SIDE_COUNT) {
            added.neighbors[side] = NO_SLOT;
        }
        nodeCount += 1;
        slots.insert(id, slot);
        return slot;
    }

    uint slotOf(NodeId id) const {
        const(uint)* found = slots.find(id);
        uint result = NO_SLOT;
        if (found !is null) {
            result = *found;
        }
        return result;
    }

    NodeId idAt(uint slot) const {
        return container(slot).id;
    }

    inout(Node)* nodeAt(uint slot) inout {
        return &container(slot).value;
    }

    Node* nodeOf(NodeId id) {
        uint slot = slotOf(id);
        Node* result = null;
        if (slot != NO_SLOT) {
            result = nodeAt(slot);
        }
        return result;
    }

    uint neighborSlot(uint slot, Side which) const {
        return container(slot).neighbors[which];
    }

    NodeId neighbor(NodeId node, Side which) const {
        uint slot = slotOf(node);
        NodeId result = NO_NODE;
        if (slot != NO_SLOT) {
            uint neighborIndex = container(slot).neighbors[which];
            if (neighborIndex != NO_SLOT) {
                result = container(neighborIndex).id;
            }
        }
        return result;
    }

    NodeId ensureNeighbor(NodeId node, Side side) {
        uint slot = slotOf(node);
        NodeId result = NO_NODE;
        if (slot != NO_SLOT) {
            result = container(ensureNeighborSlot(slot, side)).id;
        }
        return result;
    }

    uint ensureNeighborSlot(uint slot, Side side) {
        uint result = container(slot).neighbors[side];
        if (result == NO_SLOT) {
            result = insertChildSlot(slot, side);
        }
        return result;
    }

    uint insertChildSlot(uint nodeSlot, Side side) {
        ParentEntry[MAX_PARENTS] parents;
        uint parentCount = 0;
        foreach (candidateIndex; 0 .. SIDE_COUNT) {
            Side candidateSide = cast(Side) candidateIndex;
            if (candidateSide == side) {
                parents[parentCount] = ParentEntry(nodeSlot, side);
                parentCount += 1;
            } else if (sideAdjacentTo(candidateSide, side) && isParentSideSlot(nodeSlot, candidateSide)) {
                uint parentOfNode = container(nodeSlot).neighbors[candidateSide];
                uint parentOfSubject = ensureNeighborSlot(parentOfNode, side);
                parents[parentCount] = ParentEntry(parentOfSubject, candidateSide);
                parentCount += 1;
            }
        }

        NodeId primaryParent = container(parents[0].slot).id;
        ubyte[17] hashInput;
        memcpy(hashInput.ptr, primaryParent.value.ptr, 16);
        hashInput[16] = parents[0].side;
        NodeId id = NodeId(murmurHash3(hashInput[]));

        uint newSlot = slotOf(id);
        if (newSlot == NO_SLOT) {
            newSlot = addNode(id, container(nodeSlot).depth + 1);
        }
        foreach (i; 0 .. parentCount) {
            linkNeighborSlots(newSlot, parents[i].slot, parents[i].side);
        }
        return newSlot;
    }

    bool isParentSideSlot(uint slot, Side side) const {
        uint neighborIndex = container(slot).neighbors[side];
        bool result = false;
        if (neighborIndex != NO_SLOT) {
            result = container(neighborIndex).depth < container(slot).depth;
        }
        return result;
    }

    void linkNeighborSlots(uint a, uint b, Side side) {
        container(a).neighbors[side] = b;
        container(b).neighbors[side] = a;
    }

    ParentList parents(NodeId node) const {
        ParentList result;
        uint slot = slotOf(node);
        if (slot != NO_SLOT) {
            uint nodeDepth = container(slot).depth;
            foreach (sideIndex; 0 .. SIDE_COUNT) {
                uint neighborIndex = container(slot).neighbors[sideIndex];
                if (neighborIndex != NO_SLOT && result.count < MAX_PARENTS && container(neighborIndex).depth < nodeDepth) {
                    result.links[result.count] = ParentLink(container(neighborIndex).id, cast(Side) sideIndex);
                    result.count += 1;
                }
            }
        }
        return result;
    }

    void ensureNodeState(NodeId nodeId) {
        uint slot = slotOf(nodeId);
        if (slot != NO_SLOT && !container(slot).value.hasState) {
            ParentList parentList = parents(nodeId);
            foreach (i; 0 .. parentList.count) {
                ensureNodeState(parentList.links[i].id);
            }
            NodeState state = createNodeState(&this, nodeId);
            container(slot).value.state = state;
            container(slot).value.hasState = true;
        }
    }

    const(NodeState)* nodeState(NodeId nodeId) const {
        uint slot = slotOf(nodeId);
        const(NodeState)* result = null;
        if (slot != NO_SLOT && container(slot).value.hasState) {
            result = &container(slot).value.state;
        }
        return result;
    }

    NodeId normalizeTransform(NodeId start, MIsometry!float* transform) const {
        NodeId reference = start;
        MPoint!float location = (*transform) * MPoint!float.origin();
        bool moved = true;
        while (moved) {
            moved = false;
            foreach (sideIndex; 0 .. SIDE_COUNT) {
                Side side = cast(Side) sideIndex;
                if (!moved && sideIsFacing(side, location)) {
                    NodeId next = neighbor(reference, side);
                    if (next != NO_NODE) {
                        reference = next;
                        MIsometry!float reflection = sideReflection(side);
                        location = reflection * location;
                        *transform = reflection * (*transform);
                        moved = true;
                    }
                }
            }
        }
        return reference;
    }

    NodeId ensureNormalizedTransform(NodeId start, MIsometry!float* transform) {
        uint slot = slotOf(start);
        MPoint!float location = (*transform) * MPoint!float.origin();
        bool moved = true;
        while (moved) {
            moved = false;
            foreach (sideIndex; 0 .. SIDE_COUNT) {
                Side side = cast(Side) sideIndex;
                if (!moved && sideIsFacing(side, location)) {
                    slot = ensureNeighborSlot(slot, side);
                    MIsometry!float reflection = sideReflection(side);
                    location = reflection * location;
                    *transform = reflection * (*transform);
                    moved = true;
                }
            }
        }
        return idAt(slot);
    }

    void release() {
        foreach (slot; 0 .. nodeCount) {
            foreach (vertex; 0 .. VERTEX_COUNT) {
                container(slot).value.chunks[vertex].voxels.release();
            }
        }
        nodes.release();
        slots.release();
        nodeCount = 0;
    }
}
