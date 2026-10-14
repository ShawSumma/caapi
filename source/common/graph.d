module common.graph;

import core.bitop : bsf;
import base.hashmap : HashMap;
import base.murmur : murmurHash3;
import base.parallel : Executor;
import base.slab : FreeIndices, Slab;
import common.chunks : ChunkStore;
import common.neighbors : needsMesh;
import common.node : ChunkLayout, ChunkSlot;
import common.position : Position;
import common.view : GraphView, ThreadViews;
import common.worldgen.blueprint : Blueprint;
import common.worldgen.building : Building, BuildingPlan;
import common.worldgen.generation : NodeState, Worldgen;
import common.worldgen.sky : Skies;
import common.worldgen.store : StructureStore;
import common.worldgen.structure : PAINT_REACH, anchorSlotOf, finalizeStructure;
import geometry.honeycomb : BEYOND_TOLERANCE, FACE_COUNT, Face, adjacentFaces, faceBit, mirror, normal;
import geometry.lorentz : Point;

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
enum uint NO_FACE = FACE_COUNT;
enum ushort ALL_FACES = (1u << FACE_COUNT) - 1;

enum NodeContent : ubyte {
    unknown,
    empty,
    holding,
}

struct Node {
    NodeId id;
    uint[FACE_COUNT] neighbors;
    uint depth;
    ushort parentFaces;
    ushort liveChildren;
    ushort references;
    NodeContent content;
    bool hasState;
}

struct ParentEntry {
    uint slot;
    Face side;
}

struct ParentList {
    ParentEntry[MAX_PARENTS] links;
    uint count;
}

ushort childParentFaces(ushort parentFaces, Face face) {
    return cast(ushort)((parentFaces & adjacentFaces(face)) | faceBit(face));
}

NodeId childId(NodeId firstParent, Face face) {
    ubyte[NODE_ID_BYTES + 1] hashInput;
    hashInput[0 .. NODE_ID_BYTES] = (cast(const(ubyte)*) firstParent.value.ptr)[0 .. NODE_ID_BYTES];
    hashInput[NODE_ID_BYTES] = face;
    return NodeId(murmurHash3(hashInput[]));
}

uint farthestFaceBeyond(Point!float point, ushort allowed) {
    uint farthest = NO_FACE;
    float most = BEYOND_TOLERANCE * point.v.c[3];
    foreach (index; 0 .. FACE_COUNT) {
        float beyond = normal(cast(Face) index).minkowski(point.v);
        if ((allowed & (1u << index)) != 0 && beyond > most) {
            most = beyond;
            farthest = index;
        }
    }
    return farthest;
}

struct Graph {
    Slab!Node nodes;
    Slab!NodeState states;
    HashMap!(NodeId, uint) slots;
    FreeIndices freeSlots;
    ChunkStore chunks;
    StructureStore structures;
    Skies skies;
    GraphView ownView;
    ThreadViews threadViews;
    Worldgen worldgen;
    ChunkLayout layout;
    uint slotCount;
    uint liveCount;
    uint anchorSlot;

    static Graph make(ubyte dimension, Worldgen chosen) {
        Graph graph;
        graph.layout = ChunkLayout.make(dimension);
        graph.worldgen = chosen;
        graph.skies.isPlanetFlat = chosen.hasPlaneGround();
        graph.structures.blueprint = Blueprint.make(dimension);
        uint root = graph.addNode(ROOT_NODE, 0, 0);
        graph.anchorSlot = root;
        if (chosen.hasStructure()) {
            graph.anchorSlot = graph.anchorSlotOf();
        }
        graph.reference(root);
        graph.reference(graph.anchorSlot);
        return graph;
    }

    ref GraphView view() return {
        ownView.graph = &this;
        ownView.owner = &this;
        return ownView;
    }

    inout(Node)* nodeAt(uint slot) inout {
        return nodes.at(slot);
    }

    bool isLive(uint slot) const {
        return nodeAt(slot).id != NO_NODE;
    }

    uint slotOf(NodeId id) const {
        const(uint)* found = slots.find(id);
        return found is null ? NO_SLOT : *found;
    }

    NodeId idAt(uint slot) const {
        return nodeAt(slot).id;
    }

    uint depthOf(uint slot) const {
        return nodeAt(slot).depth;
    }

    uint neighborSlot(uint slot, Face face) const {
        return nodeAt(slot).neighbors[face];
    }

    NodeId neighbor(NodeId node, Face face) const {
        uint found = neighborSlot(slotOf(node), face);
        return found == NO_SLOT ? NO_NODE : idAt(found);
    }

    bool isParentFace(uint slot, Face face) const {
        return (nodeAt(slot).parentFaces & faceBit(face)) != 0;
    }

    ParentList parents(uint slot) const {
        ParentList list;
        const(Node)* node = nodeAt(slot);
        uint remaining = node.parentFaces;
        while (remaining != 0) {
            uint face = bsf(remaining);
            remaining &= remaining - 1;
            list.links[list.count] = ParentEntry(node.neighbors[face], cast(Face) face);
            list.count += 1;
        }
        return list;
    }

    uint addNode(NodeId id, uint depth, ushort parentFaces) {
        uint slot = slotCount;
        if (!freeSlots.isEmpty()) {
            slot = freeSlots.takeLowest();
        } else {
            slotCount += 1;
            nodes.ensure(slotCount);
            states.ensure(slotCount);
            chunks.ensureSlots(slotCount);
            structures.ensureSlots(slotCount);
            skies.ensureSlots(slotCount);
        }
        Node* added = nodeAt(slot);
        *added = Node.init;
        added.id = id;
        added.neighbors[] = NO_SLOT;
        added.depth = depth;
        added.parentFaces = parentFaces;
        liveCount += 1;
        slots.insert(id, slot);
        return slot;
    }

    void removeNode(uint slot) {
        ParentList list = parents(slot);
        foreach (link; list.links[0 .. list.count]) {
            Node* parent = nodeAt(link.slot);
            parent.neighbors[link.side] = NO_SLOT;
            parent.liveChildren -= 1;
        }
        slots.remove(idAt(slot));
        *nodeAt(slot) = Node.init;
        freeSlots.add(slot);
        liveCount -= 1;
        trimSlots();
    }

    void trimSlots() {
        while (slotCount > 0 && freeSlots.contains(slotCount - 1)) {
            freeSlots.drop(slotCount - 1);
            slotCount -= 1;
        }
        nodes.trim(slotCount);
        states.trim(slotCount);
        chunks.trimSlots(slotCount);
        structures.trimSlots(slotCount);
        skies.trimSlots(slotCount);
    }

    uint ensureNeighborSlot(uint slot, Face face) {
        uint existing = neighborSlot(slot, face);
        return existing == NO_SLOT ? addChild(slot, face) : existing;
    }

    uint addChild(uint slot, Face face) {
        ushort parentFaces = childParentFaces(nodeAt(slot).parentFaces, face);
        ParentList list;
        uint remaining = parentFaces;
        while (remaining != 0) {
            Face through = cast(Face) bsf(remaining);
            remaining &= remaining - 1;
            uint parent = through == face ? slot : ensureNeighborSlot(neighborSlot(slot, through), face);
            list.links[list.count] = ParentEntry(parent, through);
            list.count += 1;
        }
        NodeId id = childId(idAt(list.links[0].slot), list.links[0].side);
        assert(slotOf(id) == NO_SLOT);
        uint child = addNode(id, depthOf(slot) + 1, parentFaces);
        foreach (link; list.links[0 .. list.count]) {
            nodeAt(link.slot).neighbors[link.side] = child;
            nodeAt(link.slot).liveChildren += 1;
            nodeAt(child).neighbors[link.side] = link.slot;
        }
        return child;
    }

    void reference(uint slot) {
        nodeAt(slot).references += 1;
    }

    void unreference(uint slot) {
        nodeAt(slot).references -= 1;
    }

    Position normalized(Position start) const {
        uint slot = slotOf(start.node);
        Point!float point = start.local * Point!float.origin();
        uint face = farthestFaceBeyond(point, linkedFaces(slot));
        while (face != NO_FACE) {
            slot = neighborSlot(slot, cast(Face) face);
            start.local = mirror(cast(Face) face) * start.local;
            point = start.local * Point!float.origin();
            face = farthestFaceBeyond(point, linkedFaces(slot));
        }
        return Position(idAt(slot), start.local);
    }

    ushort linkedFaces(uint slot) const {
        ushort linked = 0;
        foreach (index; 0 .. FACE_COUNT) {
            if (nodeAt(slot).neighbors[index] != NO_SLOT) {
                linked |= faceBit(cast(Face) index);
            }
        }
        return linked;
    }

    Position ensureNormalized(Position start) {
        return view.ensureNormalized(start);
    }

    ref const(NodeState) stateAt(uint slot) const {
        assert(nodeAt(slot).hasState);
        return *states.at(slot);
    }

    const(NodeState)* ensureState(uint slot) {
        if (!nodeAt(slot).hasState) {
            *states.at(slot) = NodeState.fromParents(view, slot);
            nodeAt(slot).hasState = true;
        }
        return states.at(slot);
    }

    void markChanged(ChunkSlot chunk) {
        if (!chunks.at(chunk).isQueued && this.needsMesh(chunk)) {
            chunks.queue(chunk);
        }
    }

    bool isFinished(uint slot) const {
        return structures.at(slot).isFinished;
    }

    bool ensureStructureAt(uint slot) {
        if (!isFinished(slot)) {
            ParentList list = parents(slot);
            foreach (link; list.links[0 .. list.count]) {
                ensureStructureAt(link.slot);
            }
            growBefore(depthOf(slot));
            if (structures.grower.cover !is null && !structures.at(slot).isCovered) {
                structures.grower.cover(structures.grower.context, this, slot);
            }
            this.finalizeStructure(slot);
            structures.at(slot).isFinished = true;
        }
        return structures.at(slot).isInStructure;
    }

    void paintAhead(const(uint)[] candidates, Executor executor) {
        if (structures.grower.paintAhead !is null && candidates.length > 0) {
            structures.grower.paintAhead(structures.grower.context, this, candidates, executor);
        }
    }

    void growBefore(uint depth) {
        int through = cast(int) depth + PAINT_REACH;
        if (structures.grower.grow !is null && through > structures.grownThrough) {
            structures.grownThrough = through;
            structures.grower.grow(structures.grower.context, this, through);
        }
    }

    void restoreBrushes(uint slot) {
        if (structures.grower.cover !is null) {
            structures.grower.cover(structures.grower.context, this, slot);
        }
    }

    const(Building)* ensureBuildingAt(uint slot) {
        if (structures.buildingAt(slot) is null) {
            ensureStructureAt(slot);
            restoreBrushes(slot);
            BuildingPlan plan = BuildingPlan.make(this, slot);
            structures.storeBuilding(slot, Building.make(plan));
            plan.release();
        }
        return structures.buildingAt(slot);
    }

    void release() {
        structures.release();
        chunks.release();
        skies.release();
        nodes.release();
        states.release();
        slots.release();
        freeSlots.release();
        ownView.release();
        threadViews.release();
        slotCount = 0;
        liveCount = 0;
    }
}
