module common.worldgen.store;

import core.stdc.string : memcpy;
import base.array : Array;
import base.hashmap : HashMap;
import base.parallel : Executor;
import base.slab : Run, RunPool, Slab;
import common.graph : Graph, NodeId;
import common.worldgen.blueprint : Blueprint;
import common.worldgen.building : Building;
import common.worldgen.strokes : Strokes;
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

struct NodeStructure {
    Run touches;
    uint building;
    bool isFinished;
    bool isInStructure;
    bool isCovered;
    bool isBuildingQueued;
    bool isBuildingUrgent;
}

struct StructureStore {
    Slab!NodeStructure nodes;
    RunPool!LineTouch touches;
    Slab!PendingTouch pending;
    HashMap!(NodeId, uint) pendingHeads;
    HashMap!(NodeId, uint) tiledFaces;
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
        pendingCount += 1;
        pending.ensure(pendingCount);
        *pending.at(pendingCount - 1) = PendingTouch(touch, head is null ? NO_PENDING : *head);
        pendingHeads.insert(id, pendingCount);
    }

    const(Building)* buildingAt(uint slot) const {
        uint building = at(slot).building;
        return building == NO_BUILDING ? null : buildings.at(building - 1);
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
