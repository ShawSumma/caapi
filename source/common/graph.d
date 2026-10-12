module common.graph;

import core.bitop : bsf;
import common.array : Array;
import common.dodeca : SIDE_COUNT, Side, VERTEX_COUNT, isAdjacentTo, isFacing, reflection;
import common.hashmap : HashMap;
import common.margins : MarginTables;
import common.math : MIsometry, MPoint;
import common.murmur : murmurHash3;
import common.parallel : Executor;
import common.node : Chunk, ChunkLayout, ChunkSlot;
import common.position : Position;
import common.slab : SLAB_SHIFT, Slab;
import common.worldgen.blueprint : Blueprint;
import common.worldgen.building : Building, BuildingPlan;
import common.view : GraphView;
import common.worldgen.generation : NodeState, Worldgen;
import common.worldgen.sky : Skies, WorldRef;
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
enum uint FREE_RUN_LENGTHS = 16;
enum uint NO_CHUNKS = 0;

immutable Chunk FRESH_CHUNK = Chunk.init;

enum NodeContent : ubyte {
    unknown,
    empty,
    holding,
}

struct Node {
    Building building;
    NodeId id;
    NodeState state;
    uint[SIDE_COUNT] neighbors;
    uint depth;
    uint touchStart;
    uint touchLength;
    uint worldStart;
    uint worldCount;
    uint chunkBlock;
    ushort parentSides;
    ushort liveChildren;
    ushort references;
    NodeContent content;
    bool hasState;
    bool hasWorlds;
    bool hasStructure;
    bool isCovered;
    bool isInStructure;
    bool hasBuilding;
    bool isBuildingQueued;
    bool isRecent;
}

struct Grower {
    void function(void* context, ref Graph graph, int through) grow;
    void function(void* context, ref Graph graph, uint slot) cover;
    void function(void* context, ref Graph graph, const(uint)[] candidates, Executor executor) prepare;
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
    HashMap!(NodeId, uint) pendingHeads;
    HashMap!(NodeId, uint) tiledFaces;
    Array!ChunkSlot changedChunks;
    Slab!LineTouch touches;
    Slab!PendingTouch pendingTouches;
    Slab!WorldRef worldRefs;
    Array!LineTouch touchScratch;
    Array!uint freeSlots;
    Array!uint freeBlocks;
    Array!ChunkSlot restores;
    GraphView view;
    Array!uint[FREE_RUN_LENGTHS] freeWorldRuns;
    Array!uint[FREE_RUN_LENGTHS] freeTouchRuns;
    Blueprint blueprint;
    Skies skies;
    Grower grower;
    size_t changedHead;
    Worldgen worldgen;
    ChunkLayout layout;
    MarginTables margins;
    uint nodeCount;
    uint liveCount;
    uint blockCount;
    uint anchorSlot;
    uint touchCount;
    uint pendingCount;
    uint worldRefCount;
    int grownThrough = -1;

    static Graph make(ubyte dimension, Worldgen chosen) {
        Graph graph;
        graph.layout = ChunkLayout.make(dimension);
        graph.margins = MarginTables.make(dimension);
        graph.worldgen = chosen;
        graph.blueprint = Blueprint.make(dimension);
        graph.addNode(ROOT_NODE, 0);
        graph.anchorSlot = graph.slotOf(ROOT_NODE);
        if (chosen.hasStructure()) {
            graph.anchorSlot = graph.anchorSlotOf();
        }
        graph.reference(graph.slotOf(ROOT_NODE));
        graph.reference(graph.anchorSlot);
        return graph;
    }

    void markChanged(ChunkSlot chunk) {
        Chunk* target = chunkFor(chunk);
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
        if (hasChunks(result.slot)) {
            chunkFor(result).isQueued = false;
        }
        if (changedHead == changedChunks.length) {
            changedChunks.clear();
            changedHead = 0;
        }
        return result;
    }

    inout(Node)* nodeAt(uint slot) inout {
        return nodes.at(slot);
    }

    bool hasChunks(uint slot) const {
        return nodeAt(slot).chunkBlock != NO_CHUNKS;
    }

    const(Chunk)* chunkAt(ChunkSlot chunk) const {
        uint block = nodeAt(chunk.slot).chunkBlock;
        if (block == NO_CHUNKS) {
            return &FRESH_CHUNK;
        } else {
            return chunks.at(cast(size_t)(block - 1) * VERTEX_COUNT + chunk.vertex);
        }
    }

    // For threads that each write their own chunks: never allocates, so the graph itself is left as it was.
    Chunk* heldChunk(ChunkSlot chunk) const {
        assert(hasChunks(chunk.slot));
        return cast(Chunk*) chunks.at(cast(size_t)(nodeAt(chunk.slot).chunkBlock - 1) * VERTEX_COUNT + chunk.vertex);
    }

    Chunk* chunkFor(ChunkSlot chunk) {
        Node* node = nodeAt(chunk.slot);
        if (node.chunkBlock == NO_CHUNKS) {
            if (freeBlocks.length > 0) {
                node.chunkBlock = freeBlocks.ptr[freeBlocks.length - 1];
                freeBlocks.length -= 1;
            } else {
                blockCount += 1;
                chunks.ensure(cast(size_t) blockCount * VERTEX_COUNT);
                node.chunkBlock = blockCount;
            }
        }
        return chunks.at(cast(size_t)(node.chunkBlock - 1) * VERTEX_COUNT + chunk.vertex);
    }

    void releaseChunks(uint slot) {
        Node* node = nodeAt(slot);
        foreach (vertex; 0 .. VERTEX_COUNT) {
            Chunk* chunk = chunks.at(cast(size_t)(node.chunkBlock - 1) * VERTEX_COUNT + vertex);
            chunk.voxels.release();
            *chunk = Chunk.init;
        }
        freeBlocks.append(node.chunkBlock);
        node.chunkBlock = NO_CHUNKS;
    }

    uint addNode(NodeId id, uint depth) {
        uint slot = nodeCount;
        if (freeSlots.length > 0) {
            slot = freeSlots.ptr[freeSlots.length - 1];
            freeSlots.length -= 1;
        } else {
            nodes.ensure(slot + 1);
            nodeCount += 1;
        }
        Node* added = nodeAt(slot);
        added.id = id;
        added.depth = depth;
        foreach (side; 0 .. SIDE_COUNT) {
            added.neighbors[side] = NO_SLOT;
        }
        liveCount += 1;
        slots.insert(id, slot);
        return slot;
    }

    bool isLive(uint slot) const {
        return nodeAt(slot).id != NO_NODE;
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

    uint depthOf(uint slot) const {
        return nodeAt(slot).depth;
    }

    ushort parentSidesOf(uint slot) const {
        return nodeAt(slot).parentSides;
    }

    bool hasStructureAt(uint slot) const {
        return nodeAt(slot).hasStructure;
    }

    NodeState stateAt(uint slot) {
        return *ensureNodeStateAt(slot);
    }

    // The main thread's view of this graph, for reads that must not create nodes; it is forgotten after evictions.
    ref GraphView ownView() return {
        view.graph = &this;
        return view;
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

        NodeId id = childId(idAt(parents[0].slot), parents[0].side);
        uint newSlot = existingOrAdded(id, nodeAt(nodeSlot).depth + 1);
        foreach (i; 0 .. parentCount) {
            Node* parent = nodeAt(parents[i].slot);
            if (parent.neighbors[parents[i].side] != newSlot) {
                parent.liveChildren += 1;
            }
            linkNeighborSlots(newSlot, parents[i].slot, parents[i].side);
            nodeAt(newSlot).parentSides |= sideBit(parents[i].side);
        }
        return newSlot;
    }

    void reference(uint slot) {
        nodeAt(slot).references += 1;
    }

    void unreference(uint slot) {
        nodeAt(slot).references -= 1;
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
        return (nodeAt(slot).parentSides & sideBit(side)) != 0;
    }

    void linkNeighborSlots(uint a, uint b, Side side) {
        nodeAt(a).neighbors[side] = b;
        nodeAt(b).neighbors[side] = a;
    }

    ParentList parents(uint slot) const {
        ParentList result;
        const(Node)* node = nodeAt(slot);
        uint remaining = node.parentSides;
        while (remaining != 0) {
            uint sideIndex = bsf(remaining);
            remaining &= remaining - 1;
            result.links[result.count] = ParentEntry(node.neighbors[sideIndex], cast(Side) sideIndex);
            result.count += 1;
        }
        return result;
    }

    Array!Side sidesToRoot(uint start) const {
        Array!Side sides;
        uint slot = start;
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
            if (grower.cover !is null && !nodeAt(slot).isCovered) {
                grower.cover(grower.context, this, slot);
            }
            this.finalizeStructure(slot);
            nodeAt(slot).hasStructure = true;
        }
        return nodeAt(slot).isInStructure;
    }

    // Paints on every thread the structure that these nodes' checks are about to need, so those checks only finish it.
    void prepareStructures(const(uint)[] candidates, Executor executor) {
        if (grower.prepare !is null && candidates.length > 0) {
            grower.prepare(grower.context, this, candidates, executor);
        }
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
        return reserveRun(touches, touchCount, freeTouchRuns, length);
    }

    void releaseTouches(uint start, uint length) {
        releaseRun(freeTouchRuns, start, length);
    }

    uint reserveWorlds(uint length) {
        return reserveRun(worldRefs, worldRefCount, freeWorldRuns, length);
    }

    void releaseWorlds(uint start, uint length) {
        releaseRun(freeWorldRuns, start, length);
    }

    void restoreBrushes(uint slot) {
        if (grower.cover !is null) {
            grower.cover(grower.context, this, slot);
        }
    }

    const(Building)* ensureBuildingAt(uint slot) {
        if (!nodeAt(slot).hasBuilding) {
            ensureStructureAt(slot);
            restoreBrushes(slot);
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
        foreach (index; 0 .. cast(size_t) blockCount * VERTEX_COUNT) {
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
        pendingHeads.release();
        tiledFaces.release();
        changedChunks.release();
        touches.release();
        pendingTouches.release();
        worldRefs.release();
        touchScratch.release();
        freeSlots.release();
        freeBlocks.release();
        restores.release();
        view.release();
        foreach (ref runs; freeWorldRuns) {
            runs.release();
        }
        foreach (ref runs; freeTouchRuns) {
            runs.release();
        }
        blueprint.release();
        skies.release();
        margins.release();
        nodeCount = 0;
        liveCount = 0;
        blockCount = 0;
        touchCount = 0;
        pendingCount = 0;
        worldRefCount = 0;
    }
}

uint reserveRun(T)(ref Slab!T slab, ref uint count, ref Array!uint[FREE_RUN_LENGTHS] free, uint length) {
    if (length < FREE_RUN_LENGTHS && free[length].length > 0) {
        uint start = free[length].ptr[free[length].length - 1];
        free[length].length -= 1;
        return start;
    } else {
        uint start = slabRun(count, length);
        slab.ensure(start + length);
        count = start + length;
        return start;
    }
}

void releaseRun(ref Array!uint[FREE_RUN_LENGTHS] free, uint start, uint length) {
    if (length > 0 && length < FREE_RUN_LENGTHS) {
        free[length].append(start);
    }
}

ushort sideBit(Side side) {
    return cast(ushort)(1u << side);
}

NodeId childId(NodeId primaryParent, Side side) {
    ubyte[NODE_ID_BYTES + 1] hashInput;
    hashInput[0 .. NODE_ID_BYTES] = (cast(const(ubyte)*) primaryParent.value.ptr)[0 .. NODE_ID_BYTES];
    hashInput[NODE_ID_BYTES] = side;
    return NodeId(murmurHash3(hashInput[]));
}

uint slabRun(uint count, uint length) {
    if (length > 0 && count >> SLAB_SHIFT != (count + length - 1) >> SLAB_SHIFT) {
        return ((count >> SLAB_SHIFT) + 1) << SLAB_SHIFT;
    } else {
        return count;
    }
}
