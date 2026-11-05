module client.tasks;

import core.atomic : atomicLoad, atomicOp, atomicStore;
import core.stdc.stdlib : calloc;
import base.array : Array;
import base.numbers : higherOf;
import base.parallel : ConcurrentQueue, MAIN_WORKER, WorkerPool, waitWhile, wake;
import common.node : ChunkSlot;
import common.worldgen.building : Building, BuildingPlan;
import common.worldgen.generation : ChunkParams, GeneratedVoxels, Yield;

enum uint RESERVED_CORES = 2;
enum size_t QUEUE_CAPACITY = 1 << 14;

enum GenKind : ubyte {
    fresh,
    restoring,
}

struct GenRequest {
    ChunkParams params;
    ChunkSlot chunk;
    GenKind kind;
}

struct GenResult {
    GeneratedVoxels generated;
    ChunkSlot chunk;
    GenKind kind;
}

struct BuildingRequest {
    BuildingPlan plan;
    uint slot;
}

struct BuildingResult {
    Building building;
    uint slot;
}

struct TaskQueues {
    ConcurrentQueue!GenRequest generations;
    ConcurrentQueue!GenRequest urgent;
    ConcurrentQueue!BuildingRequest buildings;
    ConcurrentQueue!BuildingRequest urgentBuildings;
    ConcurrentQueue!GenResult generated;
    ConcurrentQueue!BuildingResult built;
    WorkerPool* pool;
    shared uint completed;
    shared uint awaiting;

    static TaskQueues* make() {
        TaskQueues* queues = cast(TaskQueues*) calloc(1, TaskQueues.sizeof);
        queues.generations = ConcurrentQueue!GenRequest.make(QUEUE_CAPACITY);
        queues.urgent = ConcurrentQueue!GenRequest.make(QUEUE_CAPACITY);
        queues.buildings = ConcurrentQueue!BuildingRequest.make(QUEUE_CAPACITY);
        queues.urgentBuildings = ConcurrentQueue!BuildingRequest.make(QUEUE_CAPACITY);
        queues.generated = ConcurrentQueue!GenResult.make(QUEUE_CAPACITY);
        queues.built = ConcurrentQueue!BuildingResult.make(QUEUE_CAPACITY);
        return queues;
    }

    void announce() {
        atomicOp!"+="(completed, 1);
        if (atomicLoad(awaiting) != 0) {
            wake(completed);
        }
    }

    void await(uint seen) {
        version (WebAssembly) {
            takeTask(&this, MAIN_WORKER);
        }
        atomicStore(awaiting, 1);
        if (atomicLoad(completed) == seen) {
            waitWhile(completed, seen);
        }
        atomicStore(awaiting, 0);
    }

    void release() {
        GenRequest request;
        while (generations.pop(request)) {
        }
        while (urgent.pop(request)) {
        }
        BuildingRequest building;
        while (buildings.pop(building) || urgentBuildings.pop(building)) {
            building.plan.release();
        }
        GenResult result;
        while (generated.pop(result)) {
            result.generated.voxels.release();
        }
        BuildingResult made;
        while (built.pop(made)) {
            made.building.release();
        }
        generations.release();
        urgent.release();
        buildings.release();
        urgentBuildings.release();
        generated.release();
        built.release();
    }
}

struct JobHelp {
    WorkerPool* pool;
    uint worker;
}

void yieldToJob(void* context) {
    JobHelp* help = cast(JobHelp*) context;
    help.pool.helpWithJob(help.worker);
}

bool takeTask(void* context, uint worker) {
    TaskQueues* queues = cast(TaskQueues*) context;
    BuildingRequest building;
    GenRequest request;
    if (queues.urgentBuildings.pop(building)) {
        makeBuilding(queues, building);
    } else if (queues.urgent.pop(request)) {
        generate(queues, request, worker);
    } else if (queues.buildings.pop(building)) {
        makeBuilding(queues, building);
    } else if (queues.generations.pop(request)) {
        generate(queues, request, worker);
    } else {
        return false;
    }
    queues.announce();
    return true;
}

void makeBuilding(TaskQueues* queues, BuildingRequest building) {
    BuildingResult made = BuildingResult(Building.make(building.plan), building.slot);
    building.plan.release();
    if (!queues.built.push(made)) {
        assert(false);
    }
}

void generate(TaskQueues* queues, GenRequest request, uint worker) {
    JobHelp help = JobHelp(queues.pool, worker);
    if (!queues.generated.push(GenResult(request.params.generateVoxels(Yield(&yieldToJob, &help)), request.chunk, request.kind))) {
        assert(false);
    }
}

size_t pushedPrefix(T)(ref ConcurrentQueue!T queue, ref Array!T pending, size_t room) {
    size_t pushed = 0;
    while (pushed < pending.length && pushed < room && queue.push(pending.ptr[pushed])) {
        pushed += 1;
    }
    foreach (index; pushed .. pending.length) {
        pending.ptr[index - pushed] = pending.ptr[index];
    }
    pending.length -= pushed;
    return pushed;
}

uint workerThreadCount(long cores) {
    return cast(uint) higherOf(cores - RESERVED_CORES, 1L);
}
