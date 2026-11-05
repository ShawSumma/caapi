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
        uint waiting = atomicLoad(awaiting);
        if (waiting != 0) {
            wake(completed);
        }
    }

    void await(uint seen) {
        version (WebAssembly) {
            takeTask(&this, MAIN_WORKER);
        }
        atomicStore(awaiting, 1);
        uint latest = atomicLoad(completed);
        if (latest == seen) {
            waitWhile(completed, seen);
        }
        atomicStore(awaiting, 0);
    }

    void release() {
        void dropRequest(ref GenRequest request) {
        }
        void dropPlan(ref BuildingRequest request) {
            request.plan.release();
        }
        void dropVoxels(ref GenResult result) {
            result.generated.voxels.release();
        }
        void dropBuilding(ref BuildingResult result) {
            result.building.release();
        }
        drained!dropRequest(generations);
        drained!dropRequest(urgent);
        drained!dropPlan(buildings);
        drained!dropPlan(urgentBuildings);
        drained!dropVoxels(generated);
        drained!dropBuilding(built);
        generations.release();
        urgent.release();
        buildings.release();
        urgentBuildings.release();
        generated.release();
        built.release();
    }
}

void drained(alias drop, T)(ref ConcurrentQueue!T queue) {
    T item;
    bool popped = queue.pop(item);
    while (popped) {
        drop(item);
        popped = queue.pop(item);
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
    bool took = queues.urgentBuildings.pop(building);
    if (took) {
        makeBuilding(queues, building);
    }
    if (!took) {
        took = queues.urgent.pop(request);
        if (took) {
            generate(queues, request, worker);
        }
    }
    if (!took) {
        took = queues.buildings.pop(building);
        if (took) {
            makeBuilding(queues, building);
        }
    }
    if (!took) {
        took = queues.generations.pop(request);
        if (took) {
            generate(queues, request, worker);
        }
    }
    if (took) {
        queues.announce();
    }
    return took;
}

void makeBuilding(TaskQueues* queues, BuildingRequest building) {
    BuildingResult made = BuildingResult(Building.make(building.plan), building.slot);
    building.plan.release();
    bool accepted = queues.built.push(made);
    assert(accepted);
}

void generate(TaskQueues* queues, GenRequest request, uint worker) {
    JobHelp help = JobHelp(queues.pool, worker);
    bool accepted = queues.generated.push(GenResult(request.params.generateVoxels(Yield(&yieldToJob, &help)), request.chunk, request.kind));
    assert(accepted);
}

size_t pushedPrefix(T)(ref ConcurrentQueue!T queue, ref Array!T pending, size_t room) {
    size_t pushed = 0;
    bool accepted = true;
    while (accepted && pushed < pending.length && pushed < room) {
        accepted = queue.push(pending.ptr[pushed]);
        if (accepted) {
            pushed += 1;
        }
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
