module common.view;

import core.bitop : bsf;
import base.array : Array;
import base.hashmap : HashMap;
import common.graph : ALL_FACES, Graph, NO_FACE, NO_SLOT, NodeId, ParentEntry, ParentList, childId, childParentFaces, farthestFaceBeyond;
import common.node : ChunkLayout;
import common.position : Position;
import common.worldgen.blueprint : Blueprint;
import common.worldgen.building : Building;
import common.worldgen.generation : ChunkStructure, NodeState, Worldgen;
import common.worldgen.horospheres : CornerKey, GroundKey, HorosphereRef, Horospheres, ROOT, Rise, RisingList, applyDiscoveries, makeHorosphere, makeWantedHorospheres;
import common.worldgen.store : NodeStructure;
import common.worldgen.structure : ClaimKey;
import geometry.honeycomb : CORNER_COUNT, Corner, FACE_COUNT, Face, faceBit, mirror;
import geometry.lorentz : Point;

enum uint VIRTUAL = 1u << 31;

struct ViewNode {
    ParentList parents;
    uint[FACE_COUNT] children;
    NodeId id;
    NodeState state;
    uint depth;
    ushort parentFaces;
    bool hasState;
}

struct SideKey {
    uint node;
    Face side;

    size_t toHash() const {
        return cast(size_t) node * FACE_COUNT + side;
    }
}

struct SlotKey {
    uint slot;

    size_t toHash() const {
        return slot;
    }
}

struct SlotCorner {
    uint slot;
    Corner corner;

    size_t toHash() const {
        return cast(size_t) slot * CORNER_COUNT + corner;
    }
}

struct RefRange {
    uint start;
    uint count;
}

struct WantedHorosphere {
    uint start;
    uint pathStart;
    uint pathLength;
    uint parent;
    Corner corner;
}

struct GraphView {
    const(Graph)* graph;
    Graph* owner;
    Array!ViewNode nodes;
    Array!WantedHorosphere wanted;
    Array!Face wantedPaths;
    HashMap!(NodeId, uint) virtualIds;
    HashMap!(SideKey, uint) missingChildren;
    HashMap!(SlotKey, NodeState) statesOfSlots;
    Array!HorosphereRef refs;
    HashMap!(SlotKey, RefRange) refsOfNodes;
    Array!uint risingFound;
    HashMap!(GroundKey, RisingList) rising;
    HashMap!(SlotCorner, Rise) choices;
    Array!uint storedSlots;
    Array!GroundKey risingKeys;
    Array!SlotCorner choiceKeys;
    bool isBlocked;

    static GraphView over(ref const Graph graph) {
        GraphView view;
        view.graph = &graph;
        return view;
    }

    void forget() {
        nodes.clear();
        virtualIds.clear();
        missingChildren.clear();
        statesOfSlots.clear();
        refs.clear();
        refsOfNodes.clear();
        risingFound.clear();
        rising.clear();
        choices.clear();
        storedSlots.clear();
        risingKeys.clear();
        choiceKeys.clear();
        isBlocked = false;
    }

    void release() {
        nodes.release();
        wanted.release();
        wantedPaths.release();
        virtualIds.release();
        missingChildren.release();
        statesOfSlots.release();
        refs.release();
        refsOfNodes.release();
        risingFound.release();
        rising.release();
        choices.release();
        storedSlots.release();
        risingKeys.release();
        choiceKeys.release();
    }

    ref const(ChunkLayout) layout() const {
        return graph.layout;
    }

    ref const(Worldgen) worldgen() const {
        return graph.worldgen;
    }

    ref const(Horospheres) horospheres() const {
        return graph.horospheres;
    }

    ref const(Blueprint) blueprint() const {
        return graph.structures.blueprint;
    }

    static bool isVirtual(uint node) {
        return (node & VIRTUAL) != 0;
    }

    ref inout(ViewNode) virtualAt(uint node) inout {
        return nodes.ptr[node & ~VIRTUAL];
    }

    NodeId idAt(uint node) const {
        if (isVirtual(node)) {
            return virtualAt(node).id;
        } else {
            return graph.idAt(node);
        }
    }

    uint depthOf(uint node) const {
        if (isVirtual(node)) {
            return virtualAt(node).depth;
        } else {
            return graph.depthOf(node);
        }
    }

    ushort parentFacesOf(uint node) const {
        if (isVirtual(node)) {
            return virtualAt(node).parentFaces;
        } else {
            return graph.nodeAt(node).parentFaces;
        }
    }

    ParentList parents(uint node) const {
        if (isVirtual(node)) {
            return virtualAt(node).parents;
        } else {
            return graph.parents(node);
        }
    }

    uint slotOf(NodeId id) const {
        uint slot = graph.slotOf(id);
        if (slot != NO_SLOT) {
            return slot;
        } else {
            const(uint)* known = virtualIds.find(id);
            if (known is null) {
                return NO_SLOT;
            } else {
                return *known;
            }
        }
    }

    uint neighborSlot(uint node, Face face) const {
        if (!isVirtual(node)) {
            return graph.neighborSlot(node, face);
        } else if ((virtualAt(node).parentFaces & faceBit(face)) != 0) {
            ParentList list = virtualAt(node).parents;
            uint index = 0;
            while (list.links[index].side != face) {
                index += 1;
            }
            return list.links[index].slot;
        } else {
            return virtualAt(node).children[face];
        }
    }

    uint ensureNeighborSlot(uint node, Face face) {
        uint existing = neighborSlot(node, face);
        if (existing != NO_SLOT) {
            return existing;
        } else if (owner !is null) {
            return owner.addChild(node, face);
        } else if (isVirtual(node)) {
            uint child = virtualChild(node, face);
            virtualAt(node).children[face] = child;
            return child;
        } else {
            const(uint)* known = missingChildren.find(SideKey(node, face));
            if (known !is null) {
                return *known;
            } else {
                uint child = virtualChild(node, face);
                missingChildren.insert(SideKey(node, face), child);
                return child;
            }
        }
    }

    uint virtualChild(uint node, Face face) {
        ushort parentFaces = childParentFaces(parentFacesOf(node), face);
        ParentList list;
        uint remaining = parentFaces;
        while (remaining != 0) {
            Face through = cast(Face) bsf(remaining);
            remaining &= remaining - 1;
            uint parent = node;
            if (through != face) {
                parent = ensureNeighborSlot(neighborSlot(node, through), face);
            }
            list.links[list.count] = ParentEntry(parent, through);
            list.count += 1;
        }
        NodeId id = childId(idAt(list.links[0].slot), list.links[0].side);
        const(uint)* known = virtualIds.find(id);
        if (known !is null) {
            return *known;
        } else {
            ViewNode made;
            made.parents = list;
            made.children[] = NO_SLOT;
            made.id = id;
            made.depth = depthOf(node) + 1;
            made.parentFaces = parentFaces;
            nodes.append(made);
            uint handle = cast(uint)(nodes.length - 1) | VIRTUAL;
            virtualIds.insert(id, handle);
            return handle;
        }
    }

    Position ensureNormalized(Position start) {
        uint node = slotOf(start.node);
        uint face = farthestFaceBeyond(start.local * Point!float.origin(), ALL_FACES);
        while (face != NO_FACE) {
            node = ensureNeighborSlot(node, cast(Face) face);
            start.local = mirror(cast(Face) face) * start.local;
            face = farthestFaceBeyond(start.local * Point!float.origin(), ALL_FACES);
        }
        return Position(idAt(node), start.local);
    }

    uint pathTo(uint node, ref Array!Face sides) const {
        if (!isVirtual(node)) {
            return node;
        } else {
            ParentEntry parent = virtualAt(node).parents.links[0];
            uint start = pathTo(parent.slot, sides);
            sides.append(parent.side);
            return start;
        }
    }

    NodeState stateAt(uint node) {
        if (owner !is null) {
            return *owner.ensureState(node);
        } else if (isVirtual(node)) {
            if (!virtualAt(node).hasState) {
                virtualAt(node).state = NodeState.fromParents(this, node);
                virtualAt(node).hasState = true;
            }
            return virtualAt(node).state;
        } else if (graph.nodeAt(node).hasState) {
            return graph.stateAt(node);
        } else {
            const(NodeState)* known = statesOfSlots.find(SlotKey(node));
            if (known !is null) {
                return *known;
            } else {
                NodeState state = NodeState.fromParents(this, node);
                statesOfSlots.insert(SlotKey(node), state);
                return state;
            }
        }
    }

    bool hasStructureAt(uint node) const {
        return !isVirtual(node) && graph.isFinished(node);
    }

    ChunkStructure chunkStructureAt(uint slot) {
        if (owner !is null) {
            if (owner.ensureStructureAt(slot)) {
                return ChunkStructure(owner.ensureBuildingAt(slot), owner.structures.at(slot).isInStructure);
            } else {
                return ChunkStructure(null, false);
            }
        } else {
            const(NodeStructure)* node = &graph.structures.at(slot);
            const(Building)* building = graph.structures.buildingAt(slot);
            if (!node.isFinished || (node.needsBuilding() && building is null)) {
                return ChunkStructure(null, false, false);
            } else {
                return ChunkStructure(building, node.isInStructure);
            }
        }
    }

    bool hasHorospheresAt(uint node) const {
        return (!isVirtual(node) && graph.horospheres.hasHorospheresAt(node)) || refsOfNodes.find(SlotKey(node)) !is null;
    }

    const(HorosphereRef)[] horospheresAt(uint node) const {
        if (!isVirtual(node) && graph.horospheres.hasHorospheresAt(node)) {
            return graph.horospheres.horospheresAt(node);
        } else {
            const(RefRange)* range = refsOfNodes.find(SlotKey(node));
            if (range is null || range.count == 0) {
                return null;
            } else {
                return refs.ptr[range.start .. range.start + range.count];
            }
        }
    }

    void storeHorospheres(uint node, const(HorosphereRef)[] found) {
        if (owner !is null) {
            owner.horospheres.storeHorospheres(node, found);
        } else {
            refsOfNodes.insert(SlotKey(node), RefRange(cast(uint) refs.length, cast(uint) found.length));
            refs.appendAll(found);
            if (!isVirtual(node)) {
                storedSlots.append(node);
            }
        }
    }

    const(uint)[] knownRising(GroundKey key) const {
        const(uint)[] global = graph.horospheres.knownRising(key);
        const(RisingList)* local = rising.find(key);
        if (global !is null || local is null) {
            return global;
        } else {
            return risingFound.ptr[local.start .. local.start + local.count];
        }
    }

    const(uint)[] storeRising(GroundKey key, const(uint)[] found) {
        if (owner !is null) {
            return owner.horospheres.storeRising(key, found);
        } else {
            RisingList list = RisingList(cast(uint) risingFound.length, cast(uint) found.length);
            risingFound.appendAll(found);
            rising.insert(key, list);
            risingKeys.append(key);
            return risingFound.ptr[list.start .. list.start + list.count];
        }
    }

    bool hasChoice(SlotCorner at) const {
        return (!isVirtual(at.slot) && graph.horospheres.hasRise(at.slot, at.corner)) || choices.find(at) !is null;
    }

    Rise choiceAt(SlotCorner at) const {
        if (!isVirtual(at.slot) && graph.horospheres.hasRise(at.slot, at.corner)) {
            return graph.horospheres.riseAt(at.slot, at.corner);
        } else {
            return *choices.find(at);
        }
    }

    void storeChoice(SlotCorner at, Rise rise) {
        if (owner !is null) {
            owner.horospheres.storeRise(at.slot, at.corner, rise);
        } else {
            choices.insert(at, rise);
            if (!isVirtual(at.slot)) {
                choiceKeys.append(at);
            }
        }
    }

    CornerKey cornerKeyOf(ClaimKey key) const {
        return CornerKey(idAt(key.slot), cast(Corner) key.feature);
    }

    uint ensureHorosphere(ClaimKey rooted, uint face, Corner corner, uint parent, Rise rise) {
        const(uint)* known = graph.horospheres.horosphereOf.find(cornerKeyOf(rooted));
        if (known !is null) {
            return *known;
        } else if (owner !is null) {
            return (*owner).makeHorosphere(rooted, face, corner, parent, rise);
        } else {
            isBlocked = true;
            uint pathStart = cast(uint) wantedPaths.length;
            uint start = pathTo(face, wantedPaths);
            wanted.append(WantedHorosphere(start, pathStart, cast(uint) wantedPaths.length - pathStart, parent, corner));
            return ROOT;
        }
    }

    void clearWanted() {
        wanted.clear();
        wantedPaths.clear();
    }
}

struct ThreadViews {
    Array!GraphView views;

    void begin(ref const Graph graph, uint threads) {
        while (views.length < threads) {
            views.append(GraphView.init);
        }
        foreach (ref view; views.slice()) {
            view.graph = &graph;
            view.forget();
        }
    }

    ref GraphView opIndex(uint worker) return {
        return views.ptr[worker];
    }

    bool finish(ref Graph graph) {
        bool isMade = false;
        foreach (ref view; views.slice()) {
            graph.applyDiscoveries(view);
            isMade = graph.makeWantedHorospheres(view) || isMade;
        }
        return isMade;
    }

    void release() {
        foreach (ref view; views.slice()) {
            view.release();
        }
        views.release();
    }
}
