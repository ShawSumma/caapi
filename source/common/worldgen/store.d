module common.worldgen.store;

import core.stdc.string : memcpy;
import base.array : Array;
import base.hashmap : HashMap;
import base.parallel : Executor;
import base.slab : Run, RunPool, Slab;
import common.graph : Graph, NO_SLOT, NodeId;
import common.view : GraphView;
import common.worldgen.blueprint : Blueprint, LineEdge, Painted, TileRecord;
import common.worldgen.building : Building;
import common.worldgen.horospheres : ROOT;
import common.worldgen.strokes : Stroke, Strokes;
import common.worldgen.structure : LineTouch;
import plugins.api.flags : Flags;

enum uint NO_BUILDING = 0;

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

enum NodeMark : ubyte {
    finished,
    inStructure,
    strokes,
    pinning,
    covered,
    buildingQueued,
    buildingUrgent,
}

enum Standing : ubyte {
    unknown,
    outside,
    inside,
}

struct NodeStructure {
    Run touches;
    uint building;
    Flags!NodeMark marks;

    bool isFinished() const {
        return marks.has(NodeMark.finished);
    }

    bool isInStructure() const {
        return marks.has(NodeMark.inStructure);
    }

    bool isPinning() const {
        return marks.has(NodeMark.pinning);
    }

    bool isCovered() const {
        return marks.has(NodeMark.covered);
    }

    bool isBuildingQueued() const {
        return marks.has(NodeMark.buildingQueued);
    }

    bool isBuildingUrgent() const {
        return marks.has(NodeMark.buildingUrgent);
    }

    bool needsBuilding() const {
        return marks.has(NodeMark.inStructure) || marks.has(NodeMark.strokes);
    }

    Standing standing() const {
        if (isInStructure) {
            return Standing.inside;
        } else {
            return Standing.outside;
        }
    }
}

struct StructureStore {
    Slab!NodeStructure nodes;
    RunPool!LineTouch touches;
    HashMap!(NodeId, Array!LineTouch) pending;
    HashMap!(TileKey, uint) tiledFaces;
    Array!LineTouch scratch;
    Slab!Building buildings;
    Array!uint freeBuildings;
    Blueprint blueprint;
    Strokes strokes;
    Grower grower;
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
        foreach (touch; found) {
            blueprint.lineStates.ptr[touch.line].touchers += 1;
        }
    }

    void addPending(NodeId id, LineTouch touch) {
        Array!LineTouch* found = pending.find(id);
        if (found !is null) {
            found.append(touch);
        } else {
            Array!LineTouch made;
            made.append(touch);
            pending.insert(id, made);
        }
    }

    const(LineTouch)[] pendingAt(NodeId id) const {
        const(Array!LineTouch)* found = pending.find(id);
        if (found is null) {
            return null;
        } else {
            return found.slice();
        }
    }

    void removePending(NodeId id, LineEdge edge) {
        Array!LineTouch* touched = pending.find(id);
        size_t index = 0;
        while (touched.ptr[index].line != edge.line || touched.ptr[index].level != edge.level) {
            index += 1;
        }
        foreach (moved; index + 1 .. touched.length) {
            touched.ptr[moved - 1] = touched.ptr[moved];
        }
        touched.length -= 1;
        if (touched.length == 0) {
            touched.release();
            pending.remove(id);
        }
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
        foreach (touch; touchesAt(slot)) {
            blueprint.lineStates.ptr[touch.line].touchers -= 1;
        }
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
        foreach (ref const id, ref list; pending) {
            list.release();
        }
        pending.release();
        tiledFaces.release();
        scratch.release();
        buildings.release();
        freeBuildings.release();
        blueprint.release();
        strokes.release();
        buildingCount = 0;
    }
}

void pin(ref Graph graph, uint slot) {
    graph.structures.at(slot).marks.set(NodeMark.pinning);
    Blueprint* blueprint = &graph.structures.blueprint;
    foreach (touch; graph.structures.touchesAt(slot)) {
        blueprint.linePins.ptr[touch.line] += 1;
    }
}

void unpin(ref Graph graph, uint slot) {
    if (graph.structures.at(slot).isPinning) {
        graph.structures.at(slot).marks.clear(NodeMark.pinning);
        Blueprint* blueprint = &graph.structures.blueprint;
        foreach (touch; graph.structures.touchesAt(slot)) {
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
            structures.at(slot).marks.clear(NodeMark.covered);
        }
    }
    uint horosphere = structures.blueprint.tiles.ptr[tile].horosphere;
    if (horosphere != ROOT) {
        graph.horospheres.horospheres.ptr[horosphere - 1].tiles -= 1;
    }
    structures.blueprint.dropTile(tile);
}

bool isTileGone(ref const Graph graph, uint tile) {
    foreach (ref used; graph.structures.blueprint.tiles.ptr[tile].edges.slice()) {
        foreach (node; used.nodes) {
            if (graph.slotOf(node) != NO_SLOT) {
                return false;
            }
        }
    }
    return true;
}

void forgetTile(ref Graph graph, uint tile) {
    StructureStore* structures = &graph.structures;
    Blueprint* blueprint = &structures.blueprint;
    TileRecord* record = &blueprint.tiles.ptr[tile];
    structures.tiledFaces.remove(TileKey(record.face, record.feature));
    foreach (ref used; record.edges.slice()) {
        if (blueprint.releaseEdge(used.edge)) {
            foreach (node; used.nodes) {
                structures.removePending(node, used.edge);
            }
            blueprint.forgetEdge(used.edge);
        }
    }
    blueprint.freeTile(tile);
}
