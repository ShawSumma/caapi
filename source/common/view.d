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
import common.worldgen.sky : CornerKey, GroundKey, PLANET, SkyChoice, SkyList, Skies, WorldRef, applyDiscoveries, makeWantedWorlds, makeWorld;
import common.worldgen.store : NodeStructure;
import common.worldgen.structure : ClaimKey;
import geometry.honeycomb : Corner, FACE_COUNT, Face, faceBit, mirror;
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

struct WorldRange {
    uint start;
    uint count;
}

// A world a view needed but could not make, kept as a path from a graph slot so the main thread can make it.
struct WantedWorld {
    uint start;
    uint pathStart;
    uint pathLength;
    uint parent;
    Corner corner;
}

// The one way worldgen reads the graph. The main thread's own view has an owner, and wherever it reads past what the
// graph holds, the graph grows. Any other view leaves the graph alone, so threads can read it at once: a node the
// graph lacks is worked out here the way the graph would make it, under a handle with the VIRTUAL bit, and what the
// graph would store is kept here. Handles below VIRTUAL are graph slots.
struct GraphView {
    const(Graph)* graph;
    Graph* owner;
    Array!ViewNode nodes;
    Array!WantedWorld wanted;
    Array!Face wantedPaths;
    HashMap!(NodeId, uint) virtualIds;
    HashMap!(SideKey, uint) missingChildren;
    HashMap!(SlotKey, NodeState) statesOfSlots;
    Array!WorldRef worldRefs;
    HashMap!(SlotKey, WorldRange) worldsOfNodes;
    Array!uint risingSkies;
    HashMap!(GroundKey, SkyList) rising;
    HashMap!(CornerKey, SkyChoice) choices;
    Array!uint storedSlots;
    Array!GroundKey risingKeys;
    Array!CornerKey choiceKeys;
    bool isBlocked;

    static GraphView over(ref const Graph graph) {
        GraphView view;
        view.graph = &graph;
        return view;
    }

    // Virtual nodes keep graph slots as parents and the caches hold what the graph lacked, so a view is cleared
    // whenever the graph may have changed. What it wanted stays until the main thread makes it.
    void forget() {
        nodes.clear();
        virtualIds.clear();
        missingChildren.clear();
        statesOfSlots.clear();
        worldRefs.clear();
        worldsOfNodes.clear();
        risingSkies.clear();
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
        worldRefs.release();
        worldsOfNodes.release();
        risingSkies.release();
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

    ref const(Skies) skies() const {
        return graph.skies;
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
        return isVirtual(node) ? virtualAt(node).id : graph.idAt(node);
    }

    uint depthOf(uint node) const {
        return isVirtual(node) ? virtualAt(node).depth : graph.depthOf(node);
    }

    ushort parentFacesOf(uint node) const {
        return isVirtual(node) ? virtualAt(node).parentFaces : graph.nodeAt(node).parentFaces;
    }

    ParentList parents(uint node) const {
        return isVirtual(node) ? virtualAt(node).parents : graph.parents(node);
    }

    uint slotOf(NodeId id) const {
        uint slot = graph.slotOf(id);
        if (slot != NO_SLOT) {
            return slot;
        } else {
            const(uint)* known = virtualIds.find(id);
            return known is null ? NO_SLOT : *known;
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
        if (owner !is null) {
            return existing == NO_SLOT ? owner.addChild(node, face) : existing;
        } else if (existing != NO_SLOT) {
            return existing;
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

    // Worked out as Graph.addChild makes it.
    uint virtualChild(uint node, Face face) {
        ushort parentFaces = childParentFaces(parentFacesOf(node), face);
        ParentList list;
        uint remaining = parentFaces;
        while (remaining != 0) {
            Face through = cast(Face) bsf(remaining);
            remaining &= remaining - 1;
            uint parent = through == face ? node : ensureNeighborSlot(neighborSlot(node, through), face);
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

    // The faces crossed from a node down to the root, nearest first.
    Array!Face sidesToRoot(uint start) const {
        Array!Face sides;
        uint node = start;
        while (depthOf(node) > 0) {
            ParentEntry parent = parents(node).links[0];
            sides.append(parent.side);
            node = parent.slot;
        }
        return sides;
    }

    // The faces that make a node from a graph slot, so another view or the graph itself can reach the same node.
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

    // The main thread finishes a node's structure and building as it asks; another view can only read what is
    // finished, and says when it cannot know.
    ChunkStructure chunkStructureAt(uint slot) {
        if (owner !is null) {
            if (owner.ensureStructureAt(slot)) {
                return ChunkStructure(owner.ensureBuildingAt(slot), true);
            } else {
                return ChunkStructure(null, false);
            }
        } else {
            const(NodeStructure)* node = &graph.structures.at(slot);
            const(Building)* building = graph.structures.buildingAt(slot);
            if (!node.isFinished || (node.isInStructure && building is null)) {
                return ChunkStructure(null, false, false);
            } else {
                return ChunkStructure(building, node.isInStructure);
            }
        }
    }

    bool hasWorldsAt(uint node) const {
        return (!isVirtual(node) && graph.skies.hasWorldsAt(node)) || worldsOfNodes.find(SlotKey(node)) !is null;
    }

    const(WorldRef)[] worldsAt(uint node) const {
        if (!isVirtual(node) && graph.skies.hasWorldsAt(node)) {
            return graph.skies.worldsAt(node);
        } else {
            const(WorldRange)* range = worldsOfNodes.find(SlotKey(node));
            if (range is null || range.count == 0) {
                return null;
            } else {
                return worldRefs.ptr[range.start .. range.start + range.count];
            }
        }
    }

    void storeWorlds(uint node, const(WorldRef)[] found) {
        if (owner !is null) {
            owner.skies.storeWorlds(node, found);
        } else {
            worldsOfNodes.insert(SlotKey(node), WorldRange(cast(uint) worldRefs.length, cast(uint) found.length));
            worldRefs.appendAll(found);
            if (!isVirtual(node)) {
                storedSlots.append(node);
            }
        }
    }

    const(uint)[] knownRising(GroundKey key) const {
        const(uint)[] global = graph.skies.knownRising(key);
        const(SkyList)* local = rising.find(key);
        if (global !is null || local is null) {
            return global;
        } else {
            return risingSkies.ptr[local.start .. local.start + local.count];
        }
    }

    const(uint)[] storeRising(GroundKey key, const(uint)[] skies) {
        if (owner !is null) {
            return owner.skies.storeRising(key, skies);
        } else {
            SkyList list = SkyList(cast(uint) risingSkies.length, cast(uint) skies.length);
            risingSkies.appendAll(skies);
            rising.insert(key, list);
            risingKeys.append(key);
            return risingSkies.ptr[list.start .. list.start + list.count];
        }
    }

    const(SkyChoice)* knownChoice(CornerKey key) const {
        const(SkyChoice)* global = graph.skies.choices.find(key);
        return global !is null ? global : choices.find(key);
    }

    void storeChoice(CornerKey key, SkyChoice choice) {
        if (owner !is null) {
            owner.skies.choices.insert(key, choice);
        } else {
            choices.insert(key, choice);
            choiceKeys.append(key);
        }
    }

    CornerKey cornerKeyOf(ClaimKey key) const {
        return CornerKey(idAt(key.slot), cast(Corner) key.feature);
    }

    // Only the main thread makes worlds. Another view that needs a new one stops being trusted until it is
    // forgotten, and keeps what it wanted, which forgetting does not clear.
    uint ensureWorld(ClaimKey rooted, uint face, Corner corner, uint parent, SkyChoice choice) {
        const(uint)* known = graph.skies.worldOf.find(cornerKeyOf(rooted));
        if (known !is null) {
            return *known;
        } else if (owner !is null) {
            return (*owner).makeWorld(rooted, face, corner, parent, choice);
        } else {
            isBlocked = true;
            uint pathStart = cast(uint) wantedPaths.length;
            uint start = pathTo(face, wantedPaths);
            wanted.append(WantedWorld(start, pathStart, cast(uint) wantedPaths.length - pathStart, parent, corner));
            return PLANET;
        }
    }

    void clearWanted() {
        wanted.clear();
        wantedPaths.clear();
    }
}

// One view per thread for parallel jobs, cleared as each job begins. When it ends, what the views worked out is kept
// and the worlds they stopped at are made.
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

    // Returns whether any world was made, after which work the views stopped at can run again.
    bool finish(ref Graph graph) {
        bool isMade = false;
        foreach (ref view; views.slice()) {
            graph.applyDiscoveries(view);
            isMade = graph.makeWantedWorlds(view) || isMade;
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
