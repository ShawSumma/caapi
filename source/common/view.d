module common.view;

import core.stdc.stdlib : calloc, free;
import common.array : Array;
import common.dodeca : SIDE_COUNT, Side, isAdjacentTo, reflection;
import common.graph : FacingSide, Graph, NO_SLOT, Node, NodeId, ParentEntry, ParentList, SlotPosition, childId, sideBit;
import common.hashmap : HashMap;
import common.position : Position;
import common.dodeca : Vertex;
import common.worldgen.generation : ChunkStructure, CornerCache, NodeState;
import common.worldgen.sky : GroundKey, PLANET, SkyChoice, SkyList, VertexKey, WorldRef, hasWorldsAt, knownChoice, knownRising, vertexKeyOf, worldsAt;
import common.worldgen.structure : ClaimKey;

enum uint VIRTUAL = 1u << 31;

ref GraphView viewOf(ref Graph graph) {
    return graph.ownView();
}

ref GraphView viewOf(ref GraphView view) {
    return view;
}

struct ViewNode {
    ParentList parents;
    uint[SIDE_COUNT] children;
    NodeId id;
    NodeState state;
    uint depth;
    ushort parentSides;
    bool hasState;
}

struct SideKey {
    uint node;
    Side side;

    size_t toHash() const {
        return cast(size_t) node * SIDE_COUNT + side;
    }
}

struct SlotKey {
    uint slot;

    size_t toHash() const {
        return slot;
    }
}

// Reads the graph without changing it: a node that does not exist yet is worked out here the way
// Graph.insertChildSlot and NodeState.fromParents would make it, under a handle with the VIRTUAL bit, so a view can
// navigate anywhere while other threads read the same graph. Handles below VIRTUAL are graph slots.
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
    Vertex vertex;
}

struct GraphView {
    const(Graph)* graph;
    Array!ViewNode nodes;
    Array!WantedWorld wanted;
    Array!Side wantedPaths;
    HashMap!(NodeId, uint) virtualIds;
    HashMap!(SideKey, uint) missingChildren;
    HashMap!(SlotKey, NodeState) statesOfSlots;
    Array!WorldRef worldRefs;
    HashMap!(SlotKey, WorldRange) worldsOfNodes;
    Array!uint risingSkies;
    HashMap!(GroundKey, SkyList) rising;
    HashMap!(VertexKey, SkyChoice) choices;
    Array!uint storedSlots;
    Array!GroundKey risingKeys;
    Array!VertexKey choiceKeys;
    CornerCache* corners;
    bool isBlocked;

    static GraphView over(ref const Graph graph) {
        GraphView view;
        view.graph = &graph;
        return view;
    }

    // Virtual nodes keep graph slots as parents, so they are forgotten whenever the graph may have evicted nodes.
    void forget() {
        nodes.clear();
        virtualIds.release();
        missingChildren.release();
        statesOfSlots.release();
        worldRefs.clear();
        worldsOfNodes.release();
        risingSkies.clear();
        rising.release();
        choices.release();
        storedSlots.clear();
        risingKeys.clear();
        choiceKeys.clear();
        isBlocked = false;
    }

    void release() {
        forget();
        nodes.release();
        wanted.release();
        wantedPaths.release();
        worldRefs.release();
        risingSkies.release();
        storedSlots.release();
        risingKeys.release();
        choiceKeys.release();
        free(corners);
        corners = null;
    }

    bool hasWorldsAt(uint node) const {
        return (!isVirtual(node) && (*graph).hasWorldsAt(node)) || worldsOfNodes.find(SlotKey(node)) !is null;
    }

    void storeWorlds(uint node, const(WorldRef)[] found) {
        worldsOfNodes.insert(SlotKey(node), WorldRange(cast(uint) worldRefs.length, cast(uint) found.length));
        worldRefs.appendAll(found);
        if (!isVirtual(node)) {
            storedSlots.append(node);
        }
    }

    const(uint)[] knownRising(GroundKey key) const {
        const(uint)[] global = (*graph).knownRising(key);
        const(SkyList)* local = rising.find(key);
        if (global !is null || local is null) {
            return global;
        } else {
            return risingSkies.ptr[local.start .. local.start + local.count];
        }
    }

    const(uint)[] storeRising(GroundKey key, const(uint)[] skies) {
        SkyList list = SkyList(cast(uint) risingSkies.length, cast(uint) skies.length);
        risingSkies.appendAll(skies);
        rising.insert(key, list);
        risingKeys.append(key);
        return risingSkies.ptr[list.start .. list.start + list.count];
    }

    const(SkyChoice)* knownChoice(VertexKey key) const {
        const(SkyChoice)* global = (*graph).knownChoice(key);
        return global !is null ? global : choices.find(key);
    }

    void storeChoice(VertexKey key, SkyChoice choice) {
        choices.insert(key, choice);
        choiceKeys.append(key);
    }

    // The sides that make a node from a graph slot, so another view or the graph itself can reach the same node.
    uint pathTo(uint node, ref Array!Side sides) const {
        if (!isVirtual(node)) {
            return node;
        } else {
            ParentEntry parent = virtualAt(node).parents.links[0];
            uint start = pathTo(parent.slot, sides);
            sides.append(parent.side);
            return start;
        }
    }

    // Only the main thread makes worlds; a view that needs a new one stops being trusted until it is forgotten, and
    // keeps what it wanted, which forgetting does not clear.
    uint ensureWorld(ClaimKey rooted, uint face, Vertex vertex, uint parent, SkyChoice choice) {
        const(uint)* known = graph.skies.worldOf.find(vertexKeyOf(this, rooted));
        if (known is null) {
            isBlocked = true;
            uint pathStart = cast(uint) wantedPaths.length;
            uint start = pathTo(face, wantedPaths);
            wanted.append(WantedWorld(start, pathStart, cast(uint) wantedPaths.length - pathStart, parent, vertex));
            return PLANET;
        } else {
            return *known;
        }
    }

    void clearWanted() {
        wanted.clear();
        wantedPaths.clear();
    }

    ref CornerCache cornerCache() {
        if (corners is null) {
            corners = cast(CornerCache*) calloc(1, CornerCache.sizeof);
            *corners = CornerCache.init;
        }
        return *corners;
    }

    ref const(typeof(Graph.layout)) layout() const {
        return graph.layout;
    }

    ref const(typeof(Graph.worldgen)) worldgen() const {
        return graph.worldgen;
    }

    ref const(typeof(Graph.skies)) skies() const {
        return graph.skies;
    }

    ref const(typeof(Graph.blueprint)) blueprint() const {
        return graph.blueprint;
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

    ushort parentSidesOf(uint node) const {
        if (isVirtual(node)) {
            return virtualAt(node).parentSides;
        } else {
            return graph.parentSidesOf(node);
        }
    }

    ParentList parents(uint node) const {
        if (isVirtual(node)) {
            return virtualAt(node).parents;
        } else {
            return graph.parents(node);
        }
    }

    bool hasStructureAt(uint node) const {
        return !isVirtual(node) && graph.hasStructureAt(node);
    }

    // A view reads a structure the main thread already finished; without one it cannot say.
    ChunkStructure chunkStructureAt(uint slot) const {
        const(Node)* node = graph.nodeAt(slot);
        if (!node.hasStructure || (node.isInStructure && !node.hasBuilding)) {
            return ChunkStructure(null, false, false);
        } else if (node.isInStructure) {
            return ChunkStructure(&node.building, true);
        } else {
            return ChunkStructure(null, false);
        }
    }

    const(WorldRef)[] worldsAt(uint node) const {
        if (!isVirtual(node) && (*graph).hasWorldsAt(node)) {
            return (*graph).worldsAt(node);
        } else {
            const(WorldRange)* range = worldsOfNodes.find(SlotKey(node));
            if (range is null || range.count == 0) {
                return null;
            } else {
                return worldRefs.ptr[range.start .. range.start + range.count];
            }
        }
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

    uint neighborSlot(uint node, Side side) const {
        if (!isVirtual(node)) {
            return graph.neighborSlot(node, side);
        } else if ((virtualAt(node).parentSides & sideBit(side)) != 0) {
            return parentAcross(node, side);
        } else {
            return virtualAt(node).children[side];
        }
    }

    uint parentAcross(uint node, Side side) const {
        ParentList list = parents(node);
        uint index = 0;
        while (list.links[index].side != side) {
            index += 1;
        }
        return list.links[index].slot;
    }

    uint ensureNeighborSlot(uint node, Side side) {
        uint existing = neighborSlot(node, side);
        if (existing != NO_SLOT) {
            return existing;
        } else if (isVirtual(node)) {
            uint child = virtualChild(node, side);
            virtualAt(node).children[side] = child;
            return child;
        } else {
            const(uint)* known = missingChildren.find(SideKey(node, side));
            if (known !is null) {
                return *known;
            } else {
                uint child = virtualChild(node, side);
                missingChildren.insert(SideKey(node, side), child);
                return child;
            }
        }
    }

    // A missing neighbor is always a child: parents exist before their children and link to them when made.
    uint virtualChild(uint parent, Side side) {
        ParentList list;
        ushort sides = 0;
        foreach (candidateIndex; 0 .. SIDE_COUNT) {
            Side candidate = cast(Side) candidateIndex;
            if (candidate == side || (candidate.isAdjacentTo(side) && (parentSidesOf(parent) & sideBit(candidate)) != 0)) {
                uint through = parent;
                if (candidate != side) {
                    through = ensureNeighborSlot(neighborSlot(parent, candidate), side);
                }
                list.links[list.count] = ParentEntry(through, candidate);
                sides |= sideBit(candidate);
                list.count += 1;
            }
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
            made.depth = depthOf(parent) + 1;
            made.parentSides = sides;
            nodes.append(made);
            uint handle = cast(uint)(nodes.length - 1) | VIRTUAL;
            virtualIds.insert(id, handle);
            return handle;
        }
    }

    NodeState stateAt(uint node) {
        if (isVirtual(node)) {
            if (!virtualAt(node).hasState) {
                NodeState state = NodeState.fromParents(this, node);
                virtualAt(node).state = state;
                virtualAt(node).hasState = true;
            }
            return virtualAt(node).state;
        } else if (graph.nodeAt(node).hasState) {
            return graph.nodeAt(node).state;
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

    Array!Side sidesToRoot(uint start) const {
        Array!Side sides;
        uint node = start;
        while (depthOf(node) > 0) {
            ParentEntry parent = parents(node).links[0];
            sides.append(parent.side);
            node = parent.slot;
        }
        return sides;
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
}
