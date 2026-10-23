module common.worldgen.store;

import core.stdc.string : memcpy;
import base.array : Array;
import base.hashmap : HashMap;
import base.parallel : Executor;
import base.slab : Run, RunPool, Slab;
import common.graph : Graph, NO_SLOT, NodeId;
import common.view : GraphView;
import common.worldgen.blueprint : Blueprint, Painted;
import common.worldgen.building : Building;
import common.worldgen.strokes : Stroke, Strokes;
import common.worldgen.structure : LineTouch, PendingTouch;

enum uint NO_BUILDING = 0;
enum uint NO_PENDING = 0;

struct Grower {
    void function(void* context, ref Graph graph, int through) grow;
    void function(void* context, ref Graph graph, uint slot) cover;
    void function(void* context, ref Graph graph, const(uint)[] candidates, Executor executor) paintAhead;
    void function(void* context) release;
    void* context;
}

struct TileKey {
    NodeId node;
    ubyte feature;

    size_t toHash() const {
        return node.toHash() ^ feature;
    }
}

struct NodeStructure {
    Run touches;
    uint building;
    bool isFinished;
    bool isInStructure;
    bool hasStrokes;
    bool isPinning;
    bool isCovered;
    bool isBuildingQueued;
    bool isBuildingUrgent;

    bool needsBuilding() const {
        return isInStructure || hasStrokes;
    }
}

struct StructureStore {
    Slab!NodeStructure nodes;
    RunPool!LineTouch touches;
    Slab!PendingTouch pending;
    HashMap!(NodeId, uint) pendingHeads;
    HashMap!(TileKey, uint) tiledFaces;
    Array!LineTouch scratch;
    Slab!Building buildings;
    Array!uint freeBuildings;
    Blueprint blueprint;
    Strokes strokes;
    Grower grower;
    uint pendingCount;
    uint buildingCount;
    int grownThrough = -1;

    void ensureSlots(uint count) {
        nodes.ensure(count);
    }

    ref inout(NodeStructure) at(uint slot) inout return {
        return *nodes.at(slot);
    }

    const(LineTouch)[] touchesAt(uint slot) const {
        return touches.slice(at(slot).touches);
    }

    void setTouches(uint slot, const(LineTouch)[] found) {
        Run run = touches.reserve(cast(uint) found.length);
        memcpy(touches.slice(run).ptr, found.ptr, found.length * LineTouch.sizeof);
        at(slot).touches = run;
    }

    void addPending(NodeId id, LineTouch touch) {
        const(uint)* head = pendingHeads.find(id);
        uint next = NO_PENDING;
        if (head !is null) {
            next = *head;
        }
        pendingCount += 1;
        pending.ensure(pendingCount);
        *pending.at(pendingCount - 1) = PendingTouch(touch, next);
        pendingHeads.insert(id, pendingCount);
    }

    const(Building)* buildingAt(uint slot) const {
        uint building = at(slot).building;
        if (building == NO_BUILDING) {
            return null;
        } else {
            return buildings.at(building - 1);
        }
    }

    void storeBuilding(uint slot, Building building) {
        assert(at(slot).building == NO_BUILDING);
        uint index = buildingCount;
        if (freeBuildings.length > 0) {
            freeBuildings.length -= 1;
            index = freeBuildings.ptr[freeBuildings.length];
        } else {
            buildingCount += 1;
            buildings.ensure(buildingCount);
        }
        *buildings.at(index) = building;
        at(slot).building = index + 1;
    }

    void releaseBuilding(uint slot) {
        uint building = at(slot).building;
        if (building != NO_BUILDING) {
            buildings.at(building - 1).release();
            freeBuildings.append(building - 1);
            at(slot).building = NO_BUILDING;
        }
    }

    void forget(uint slot) {
        releaseBuilding(slot);
        touches.release(at(slot).touches);
        at(slot) = NodeStructure.init;
    }

    void addStroke(ref GraphView view, uint record, uint node, Stroke stroke) {
        uint run = blueprint.addStroke(record, view.idAt(node), stroke);
        strokes.add(view, record, run, node, stroke, blueprint.paintedBy(record).reached);
    }

    void release() {
        if (grower.release !is null) {
            grower.release(grower.context);
        }
        grower = Grower.init;
        foreach (index; 0 .. buildingCount) {
            buildings.at(index).release();
        }
        nodes.release();
        touches.release();
        pending.release();
        pendingHeads.release();
        tiledFaces.release();
        scratch.release();
        buildings.release();
        freeBuildings.release();
        blueprint.release();
        strokes.release();
        pendingCount = 0;
        buildingCount = 0;
    }
}

void pin(ref Graph graph, uint slot) {
    graph.structures.at(slot).isPinning = true;
    graph.changePins(slot, true);
}

void unpin(ref Graph graph, uint slot) {
    if (graph.structures.at(slot).isPinning) {
        graph.structures.at(slot).isPinning = false;
        graph.changePins(slot, false);
    }
}

void changePins(ref Graph graph, uint slot, bool isPinned) {
    Blueprint* blueprint = &graph.structures.blueprint;
    foreach (touch; graph.structures.touchesAt(slot)) {
        if (isPinned) {
            blueprint.linePins.ptr[touch.line] += 1;
        } else {
            blueprint.linePins.ptr[touch.line] -= 1;
        }
    }
}

bool isTilePinned(ref const Graph graph, uint tile) {
    const(Blueprint)* blueprint = &graph.structures.blueprint;
    const(Painted)* painted = &blueprint.tiles.ptr[tile].painted;
    size_t run = 0;
    while (run < painted.runs.length && blueprint.linePins.ptr[painted.runs.ptr[run].line] == 0) {
        run += 1;
    }
    size_t reached = 0;
    while (reached < painted.reached.length && !graph.isPinning(painted.reached.ptr[reached])) {
        reached += 1;
    }
    return run < painted.runs.length || reached < painted.reached.length;
}

bool isPinning(ref const Graph graph, NodeId id) {
    uint slot = graph.slotOf(id);
    return slot != NO_SLOT && graph.structures.at(slot).isPinning;
}

void dropTile(ref Graph graph, uint tile) {
    StructureStore* structures = &graph.structures;
    foreach (id; structures.blueprint.tiles.ptr[tile].painted.reached.slice()) {
        structures.strokes.remove(id, tile);
        uint slot = graph.slotOf(id);
        if (slot != NO_SLOT && !structures.at(slot).isFinished) {
            structures.at(slot).isCovered = false;
        }
    }
    structures.blueprint.dropTile(tile);
}
