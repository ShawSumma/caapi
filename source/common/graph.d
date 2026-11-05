module common.graph;

import core.bitop : bsf;
import base.array : Array;
import base.flags : Readiness;
import base.hashmap : FIBONACCI_MULTIPLIER, HashMap;
import base.maybe : Maybe, MaybeIndex;
import base.murmur : Hash128, murmurHash3;
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
import common.worldgen.horospheres : Fill, Horospheres;
import common.worldgen.store : NodeMark, StructureStore, unpin;
import common.worldgen.structure : PAINT_REACH, ensureAnchorSlot, finalizeStructure;
import geometry.honeycomb : BEYOND_TOLERANCE, FACE_COUNT, Face, adjacentFaces, faceBit, mirror, normal;
import geometry.lorentz : Point;

enum size_t NODE_ID_BYTES = 16;

struct NodeId {
    Hash128 value;

    size_t toHash() const {
        return cast(size_t)(value.first + value.second * FIBONACCI_MULTIPLIER);
    }

    ulong spice() const {
        return value.first ^ value.second;
    }
}

enum NodeId ROOT_NODE = NodeId(Hash128(1, 1));
enum uint MAX_PARENTS = 3;
enum ushort ALL_FACES = (1u << FACE_COUNT) - 1;
enum uint DISCARDS_PER_FRAME = 256;

enum NodeContent : ubyte {
    unknown,
    empty,
    holding,
}

enum SlotUse : ubyte {
    free,
    live,
}

struct Node {
    NodeId id;
    MaybeIndex!uint[FACE_COUNT] neighbors;
    uint depth;
    ushort parentFaces;
    ushort liveChildren;
    ushort references;
    NodeContent content;
    Readiness state;
    SlotUse use;

    bool hasState() const {
        return state == Readiness.ready;
    }
}

struct ParentEntry {
    uint slot;
    Face side;
}

struct ParentList {
    ParentEntry[MAX_PARENTS] links;
    uint count;
}

struct Finishing {
    uint slot;
    uint parent;
}

ushort childParentFaces(ushort parentFaces, Face face) {
    return cast(ushort)((parentFaces & adjacentFaces(face)) | faceBit(face));
}

NodeId childId(NodeId firstParent, Face face) {
    ubyte[NODE_ID_BYTES + 1] hashInput;
    hashInput[0 .. NODE_ID_BYTES] = (cast(const(ubyte)*) &firstParent.value)[0 .. NODE_ID_BYTES];
    hashInput[NODE_ID_BYTES] = face;
    return NodeId(murmurHash3(hashInput[]));
}

Maybe!Face farthestFaceBeyond(Point!float point, ushort allowed) {
    Maybe!Face farthest;
    float most = BEYOND_TOLERANCE * point.v.c[3];
    foreach (index; 0 .. FACE_COUNT) {
        float beyond = normal(cast(Face) index).minkowski(point.v);
        if ((allowed & (1u << index)) != 0 && beyond > most) {
            most = beyond;
            farthest = Maybe!Face.of(cast(Face) index);
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
    Horospheres horospheres;
    GraphView ownView;
    ThreadViews threadViews;
    Worldgen worldgen;
    ChunkLayout layout;
    uint slotCount;
    uint liveCount;
    uint madeNodes;
    uint anchorSlot;

    static Graph make(ubyte dimension, Worldgen chosen) {
        Graph graph;
        graph.bindView();
        graph.layout = ChunkLayout.make(dimension);
        graph.worldgen = chosen;
        graph.horospheres.rootFill = Fill.terrain;
        if (chosen.hasPlaneGround()) {
            graph.horospheres.rootFill = Fill.flat;
        }
        graph.structures.blueprint = Blueprint.make(dimension);
        uint root = graph.addNode(ROOT_NODE, 0, 0);
        graph.anchorSlot = root;
        if (chosen.hasStructure()) {
            graph.anchorSlot = graph.ensureAnchorSlot();
        }
        graph.reference(root);
        graph.reference(graph.anchorSlot);
        return graph;
    }

    void bindView() {
        ownView.graph = &this;
        ownView.owner = &this;
    }

    ref GraphView view() return {
        assert(ownView.owner is &this);
        return ownView;
    }

    inout(Node)* nodeAt(uint slot) inout {
        return nodes.at(slot);
    }

    bool isLive(uint slot) const {
        return nodeAt(slot).use == SlotUse.live;
    }

    MaybeIndex!uint slotOf(NodeId id) const {
        const(uint)* found = slots.find(id);
        if (found is null) {
            return MaybeIndex!uint.init;
        } else {
            return MaybeIndex!uint.of(*found);
        }
    }

    NodeId idAt(uint slot) const {
        return nodeAt(slot).id;
    }

    uint depthOf(uint slot) const {
        return nodeAt(slot).depth;
    }

    MaybeIndex!uint neighborSlot(uint slot, Face face) const {
        return nodeAt(slot).neighbors[face];
    }

    Maybe!NodeId neighbor(NodeId node, Face face) const {
        MaybeIndex!uint found = neighborSlot(slotOf(node).value, face);
        if (found.exists) {
            return Maybe!NodeId.of(idAt(found.value));
        } else {
            return Maybe!NodeId.init;
        }
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
            list.links[list.count] = ParentEntry(node.neighbors[face].value, cast(Face) face);
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
            horospheres.ensureSlots(slotCount);
        }
        Node* added = nodeAt(slot);
        *added = Node.init;
        added.id = id;
        added.depth = depth;
        added.parentFaces = parentFaces;
        added.use = SlotUse.live;
        liveCount += 1;
        madeNodes += 1;
        slots.insert(id, slot);
        return slot;
    }

    void removeNode(uint slot) {
        ParentList list = parents(slot);
        foreach (link; list.links[0 .. list.count]) {
            Node* parent = nodeAt(link.slot);
            parent.neighbors[link.side] = MaybeIndex!uint.init;
            parent.liveChildren -= 1;
        }
        slots.remove(idAt(slot));
        *nodeAt(slot) = Node.init;
        freeSlots.add(slot);
        nodes.note(slot, 1);
        states.note(slot, 1);
        chunks.blocks.note(slot, 1);
        structures.nodes.note(slot, 1);
        horospheres.nodes.note(slot, 1);
        horospheres.rises.note(slot, 1);
        liveCount -= 1;
    }

    void discardFreed() {
        uint calls = DISCARDS_PER_FRAME;
        chunks.discardFreed(calls);
        nodes.discardNoted(freeSlots, slotCount, 1, calls);
        states.discardNoted(freeSlots, slotCount, 1, calls);
        chunks.blocks.discardNoted(freeSlots, slotCount, 1, calls);
        structures.nodes.discardNoted(freeSlots, slotCount, 1, calls);
        horospheres.nodes.discardNoted(freeSlots, slotCount, 1, calls);
        horospheres.rises.discardNoted(freeSlots, slotCount, 1, calls);
    }

    uint ensureNeighborSlot(uint slot, Face face) {
        MaybeIndex!uint existing = neighborSlot(slot, face);
        if (existing.exists) {
            return existing.value;
        } else {
            return addChild(slot, face);
        }
    }

    uint addChild(uint slot, Face face) {
        ushort parentFaces = childParentFaces(nodeAt(slot).parentFaces, face);
        ParentList list;
        uint remaining = parentFaces;
        while (remaining != 0) {
            Face through = cast(Face) bsf(remaining);
            remaining &= remaining - 1;
            uint parent = slot;
            if (through != face) {
                parent = ensureNeighborSlot(neighborSlot(slot, through).value, face);
            }
            list.links[list.count] = ParentEntry(parent, through);
            list.count += 1;
        }
        NodeId id = childId(idAt(list.links[0].slot), list.links[0].side);
        assert(!slotOf(id).exists);
        uint child = addNode(id, depthOf(slot) + 1, parentFaces);
        foreach (link; list.links[0 .. list.count]) {
            nodeAt(link.slot).neighbors[link.side] = MaybeIndex!uint.of(child);
            nodeAt(link.slot).liveChildren += 1;
            nodeAt(child).neighbors[link.side] = MaybeIndex!uint.of(link.slot);
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
        uint slot = slotOf(start.node).value;
        Point!float point = start.local * Point!float.origin();
        Maybe!Face face = farthestFaceBeyond(point, linkedFaces(slot));
        while (face.exists) {
            slot = neighborSlot(slot, face.value).value;
            start.local = mirror(face.value) * start.local;
            point = start.local * Point!float.origin();
            face = farthestFaceBeyond(point, linkedFaces(slot));
        }
        return Position(idAt(slot), start.local);
    }

    ushort linkedFaces(uint slot) const {
        ushort linked = 0;
        foreach (index; 0 .. FACE_COUNT) {
            if (nodeAt(slot).neighbors[index].exists) {
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
            nodeAt(slot).state = Readiness.ready;
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
            Array!Finishing stack;
            stack.append(Finishing(slot, 0));
            while (stack.length > 0) {
                Finishing* top = &stack.ptr[stack.length - 1];
                ParentList list = parents(top.slot);
                if (top.parent < list.count) {
                    uint parent = list.links[top.parent].slot;
                    top.parent += 1;
                    if (!isFinished(parent)) {
                        stack.append(Finishing(parent, 0));
                    }
                } else {
                    uint done = top.slot;
                    stack.length -= 1;
                    finishStructure(done);
                }
            }
            stack.release();
        }
        return structures.at(slot).needsBuilding();
    }

    void finishStructure(uint slot) {
        growBefore(depthOf(slot));
        if (structures.grower.cover !is null && !structures.at(slot).isCovered) {
            structures.grower.cover(structures.grower.context, this, slot);
        }
        this.finalizeStructure(slot);
        structures.at(slot).marks.set(NodeMark.finished);
    }

    void paintAhead(const(uint)[] candidates, Executor executor) {
        if (structures.grower.paintAhead !is null && candidates.length > 0) {
            structures.grower.paintAhead(structures.grower.context, this, candidates, executor);
        }
    }

    void growBefore(uint depth) {
        uint through = depth + PAINT_REACH;
        if (structures.grower.grow !is null && through >= structures.grownBelow) {
            structures.grownBelow = through + 1;
            structures.grower.grow(structures.grower.context, this, cast(int) through);
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
            BuildingPlan plan = planBuilding(slot);
            structures.storeBuilding(slot, Building.make(plan));
            plan.release();
        }
        return structures.buildingAt(slot);
    }

    BuildingPlan planBuilding(uint slot) {
        restoreBrushes(slot);
        BuildingPlan plan = BuildingPlan.make(this, slot);
        this.unpin(slot);
        return plan;
    }

    void release() {
        structures.release();
        chunks.release();
        horospheres.release();
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
