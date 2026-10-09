module common.graph;

import common.array : Array;
import common.dodeca : SIDE_COUNT, Side, VERTEX_COUNT, isAdjacentTo, isFacing, reflection;
import common.hashmap : HashMap;
import common.math : MIsometry, MPoint;
import common.murmur : murmurHash3;
import common.node : Chunk, ChunkLayout, ChunkSlot;
import common.position : Position;
import common.slab : SLAB_SHIFT, Slab;
import common.worldgen.blueprint : Blueprint;
import common.worldgen.building : Building, BuildingPlan;
import common.worldgen.generation : NodeState, Worldgen;
import common.worldgen.sky : Skies;
import common.worldgen.structure : LineTouch, PAINT_REACH, PendingTouch, anchorSlotOf, finalizeStructure;

enum ulong NODE_HASH_MULTIPLIER = 0x9E3779B97F4A7C15;
enum size_t NODE_ID_BYTES = 16;

struct NodeId {
    ulong[2] value;

    bool opEquals(const NodeId other) const {
        return value[0] == other.value[0] && value[1] == other.value[1];
    }

    size_t toHash() const {
        return cast(size_t)(value[0] + value[1] * NODE_HASH_MULTIPLIER);
    }

    ulong spice() const {
        return value[0] ^ value[1];
    }
}

enum NodeId ROOT_NODE = NodeId([1, 1]);
enum NodeId NO_NODE = NodeId.init;
enum uint NO_SLOT = uint.max;
enum uint MAX_PARENTS = 3;

struct Node {
    Building building;
    NodeId id;
    NodeState state;
    uint[SIDE_COUNT] neighbors;
    uint depth;
    uint touchStart;
    uint touchLength;
    uint pendingHead;
    bool hasState;
    bool hasStructure;
    bool isInStructure;
    bool isTiled;
    bool hasBuilding;
    bool isBuildingQueued;
}

struct Grower {
    void function(void* context, ref Graph graph, int through) grow;
    void function(void* context, ref Graph graph, uint slot) cover;
    void function(void* context) release;
    void* context;
}

struct ParentEntry {
    uint slot;
    Side side;
}

struct ParentList {
    ParentEntry[MAX_PARENTS] links;
    uint count;
}

struct FacingSide {
    Side side;
    bool isFound;

    static FacingSide fromIndex(uint side) {
        if (side == SIDE_COUNT) {
            return FacingSide(Side.init, false);
        } else {
            return FacingSide(cast(Side) side, true);
        }
    }

    static FacingSide fromLocal(MIsometry!float local) {
        MPoint!float location = local * MPoint!float.origin();
        uint side = 0;
        while (side < SIDE_COUNT && !(cast(Side) side).isFacing(location)) {
            side += 1;
        }
        return FacingSide.fromIndex(side);
    }
}

struct SlotPosition {
    MIsometry!float local;
    uint slot;
}

struct Graph {
    Slab!Node nodes;
    Slab!Chunk chunks;
    HashMap!(NodeId, uint) slots;
    Array!ChunkSlot changedChunks;
    Slab!LineTouch touches;
    Slab!PendingTouch pendingTouches;
    Array!LineTouch touchScratch;
    Blueprint blueprint;
    Skies skies;
    Grower grower;
    size_t changedHead;
    Worldgen worldgen;
    ChunkLayout layout;
    uint nodeCount;
    uint anchorSlot;
    uint touchCount;
    uint pendingCount;
    int grownThrough = -1;

    static Graph make(ubyte dimension, Worldgen chosen) {
        Graph graph;
        graph.layout = ChunkLayout.make(dimension);
        graph.worldgen = chosen;
        graph.blueprint = Blueprint.make(dimension);
        graph.addNode(ROOT_NODE, 0);
        graph.anchorSlot = graph.slotOf(ROOT_NODE);
        if (chosen.hasStructure()) {
            graph.anchorSlot = graph.anchorSlotOf();
        }
        return graph;
    }

    void markChanged(ChunkSlot chunk) {
        Chunk* target = chunkAt(chunk);
        if (!target.isQueued && !target.voxels.isSolid()) {
            target.isQueued = true;
            changedChunks.append(chunk);
        }
    }

    bool hasChanges() const {
        return changedHead < changedChunks.length;
    }

    ChunkSlot takeChanged() {
        ChunkSlot result = changedChunks.ptr[changedHead];
        changedHead += 1;
        chunkAt(result).isQueued = false;
        if (changedHead == changedChunks.length) {
            changedChunks.clear();
            changedHead = 0;
        }
        return result;
    }

    inout(Node)* nodeAt(uint slot) inout {
        return nodes.at(slot);
    }

    inout(Chunk)* chunkAt(ChunkSlot chunk) inout {
        return chunks.at(cast(size_t) chunk.slot * VERTEX_COUNT + chunk.vertex);
    }

    uint addNode(NodeId id, uint depth) {
        uint slot = nodeCount;
        nodes.ensure(slot + 1);
        chunks.ensure(cast(size_t)(slot + 1) * VERTEX_COUNT);
        Node* added = nodeAt(slot);
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
        if (found is null) {
            return NO_SLOT;
        } else {
            return *found;
        }
    }

    NodeId idAt(uint slot) const {
        return nodeAt(slot).id;
    }

    uint neighborSlot(uint slot, Side which) const {
        return nodeAt(slot).neighbors[which];
    }

    NodeId neighbor(NodeId node, Side which) const {
        uint neighborIndex = neighborSlot(slotOf(node), which);
        if (neighborIndex == NO_SLOT) {
            return NO_NODE;
        } else {
            return idAt(neighborIndex);
        }
    }

    uint ensureNeighborSlot(uint slot, Side side) {
        uint existing = nodeAt(slot).neighbors[side];
        if (existing == NO_SLOT) {
            return insertChildSlot(slot, side);
        } else {
            return existing;
        }
    }

    uint insertChildSlot(uint nodeSlot, Side side) {
        ParentEntry[MAX_PARENTS] parents;
        uint parentCount = 0;
        foreach (candidateIndex; 0 .. SIDE_COUNT) {
            Side candidateSide = cast(Side) candidateIndex;
            if (candidateSide == side) {
                parents[parentCount] = ParentEntry(nodeSlot, side);
                parentCount += 1;
            } else if (candidateSide.isAdjacentTo(side) && isParentSide(nodeSlot, candidateSide)) {
                uint parentOfNode = nodeAt(nodeSlot).neighbors[candidateSide];
                uint parentOfSubject = ensureNeighborSlot(parentOfNode, side);
                parents[parentCount] = ParentEntry(parentOfSubject, candidateSide);
                parentCount += 1;
            }
        }

        NodeId primaryParent = idAt(parents[0].slot);
        ubyte[NODE_ID_BYTES + 1] hashInput;
        hashInput[0 .. NODE_ID_BYTES] = (cast(const(ubyte)*) primaryParent.value.ptr)[0 .. NODE_ID_BYTES];
        hashInput[NODE_ID_BYTES] = parents[0].side;
        NodeId id = NodeId(murmurHash3(hashInput[]));

        uint newSlot = existingOrAdded(id, nodeAt(nodeSlot).depth + 1);
        foreach (i; 0 .. parentCount) {
            linkNeighborSlots(newSlot, parents[i].slot, parents[i].side);
        }
        return newSlot;
    }

    uint existingOrAdded(NodeId id, uint depth) {
        uint existing = slotOf(id);
        if (existing == NO_SLOT) {
            return addNode(id, depth);
        } else {
            return existing;
        }
    }

    bool isParentSide(uint slot, Side side) const {
        uint neighborIndex = nodeAt(slot).neighbors[side];
        return neighborIndex != NO_SLOT && nodeAt(neighborIndex).depth < nodeAt(slot).depth;
    }

    void linkNeighborSlots(uint a, uint b, Side side) {
        nodeAt(a).neighbors[side] = b;
        nodeAt(b).neighbors[side] = a;
    }

    ParentList parents(uint slot) const {
        ParentList result;
        uint nodeDepth = nodeAt(slot).depth;
        foreach (sideIndex; 0 .. SIDE_COUNT) {
            uint neighborIndex = nodeAt(slot).neighbors[sideIndex];
            if (neighborIndex != NO_SLOT && result.count < MAX_PARENTS && nodeAt(neighborIndex).depth < nodeDepth) {
                result.links[result.count] = ParentEntry(neighborIndex, cast(Side) sideIndex);
                result.count += 1;
            }
        }
        return result;
    }

    Array!Side sidesToRoot(NodeId node) const {
        Array!Side sides;
        uint slot = slotOf(node);
        while (nodeAt(slot).depth > 0) {
            ParentEntry parent = parents(slot).links[0];
            sides.append(parent.side);
            slot = parent.slot;
        }
        return sides;
    }

    NodeId ensureFromRoot(const(Side)[] sidesToRoot) {
        uint slot = slotOf(ROOT_NODE);
        foreach_reverse (side; sidesToRoot) {
            slot = ensureNeighborSlot(slot, side);
        }
        return idAt(slot);
    }

    const(NodeState)* ensureNodeStateAt(uint slot) {
        if (!nodeAt(slot).hasState) {
            ParentList parentList = parents(slot);
            foreach (i; 0 .. parentList.count) {
                ensureNodeStateAt(parentList.links[i].slot);
            }
            nodeAt(slot).state = NodeState.fromParents(this, slot);
            nodeAt(slot).hasState = true;
        }
        return &nodeAt(slot).state;
    }

    bool ensureStructureAt(uint slot) {
        if (!nodeAt(slot).hasStructure) {
            ParentList parentList = parents(slot);
            foreach (link; parentList.links[0 .. parentList.count]) {
                ensureStructureAt(link.slot);
            }
            growBefore(nodeAt(slot).depth);
            if (grower.cover !is null) {
                grower.cover(grower.context, this, slot);
            }
            this.finalizeStructure(slot);
            nodeAt(slot).hasStructure = true;
        }
        return nodeAt(slot).isInStructure;
    }

    void growBefore(uint depth) {
        int through = cast(int) depth + PAINT_REACH;
        if (grower.grow !is null && through > grownThrough) {
            grownThrough = through;
            grower.grow(grower.context, this, through);
        }
    }

    const(LineTouch)[] touchesAt(uint slot) const {
        const(Node)* node = nodeAt(slot);
        if (node.touchLength == 0) {
            return null;
        } else {
            return touches.at(node.touchStart)[0 .. node.touchLength];
        }
    }

    uint reserveTouches(uint length) {
        uint start = touchCount;
        if (length > 0 && start >> SLAB_SHIFT != (start + length - 1) >> SLAB_SHIFT) {
            start = ((start >> SLAB_SHIFT) + 1) << SLAB_SHIFT;
        }
        touches.ensure(start + length);
        touchCount = start + length;
        return start;
    }

    const(Building)* ensureBuildingAt(uint slot) {
        if (!nodeAt(slot).hasBuilding) {
            ensureStructureAt(slot);
            BuildingPlan plan = BuildingPlan.make(this, slot);
            nodeAt(slot).building = Building.make(plan);
            plan.release();
            nodeAt(slot).hasBuilding = true;
        }
        return &nodeAt(slot).building;
    }

    void ensureNodeState(NodeId nodeId) {
        ensureNodeStateAt(slotOf(nodeId));
    }

    const(NodeState)* nodeState(NodeId nodeId) const {
        return &nodeAt(slotOf(nodeId)).state;
    }

    float[3] upAt(Position position) const {
        return nodeState(position.node).surface.upAt(position.local);
    }

    bool isLinkedFacing(SlotPosition position, MPoint!float location, Side side) const {
        return side.isFacing(location) && neighborSlot(position.slot, side) != NO_SLOT;
    }

    FacingSide facingLinkedSide(SlotPosition position) const {
        MPoint!float location = position.local * MPoint!float.origin();
        uint side = 0;
        while (side < SIDE_COUNT && !isLinkedFacing(position, location, cast(Side) side)) {
            side += 1;
        }
        return FacingSide.fromIndex(side);
    }

    Position normalized(Position start) const {
        SlotPosition current = SlotPosition(start.local, slotOf(start.node));
        FacingSide facing = facingLinkedSide(current);
        while (facing.isFound) {
            current = SlotPosition(facing.side.reflection * current.local, neighborSlot(current.slot, facing.side));
            facing = facingLinkedSide(current);
        }
        return Position(idAt(current.slot), current.local);
    }

    Position ensureNormalized(Position start) {
        SlotPosition current = SlotPosition(start.local, slotOf(start.node));
        FacingSide facing = FacingSide.fromLocal(current.local);
        while (facing.isFound) {
            current = SlotPosition(facing.side.reflection * current.local, ensureNeighborSlot(current.slot, facing.side));
            facing = FacingSide.fromLocal(current.local);
        }
        return Position(idAt(current.slot), current.local);
    }

    void release() {
        if (grower.release !is null) {
            grower.release(grower.context);
        }
        grower = Grower.init;
        foreach (index; 0 .. cast(size_t) nodeCount * VERTEX_COUNT) {
            chunks.at(index).voxels.release();
        }
        foreach (slot; 0 .. nodeCount) {
            if (nodeAt(slot).hasBuilding) {
                nodeAt(slot).building.release();
            }
        }
        nodes.release();
        chunks.release();
        slots.release();
        changedChunks.release();
        touches.release();
        pendingTouches.release();
        touchScratch.release();
        blueprint.release();
        skies.release();
        nodeCount = 0;
        touchCount = 0;
        pendingCount = 0;
    }
}
