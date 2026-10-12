module client.tasks;

import core.atomic : atomicLoad, atomicOp, atomicStore;
import core.stdc.stdlib : calloc;
import base.array : Array;
import base.parallel : ConcurrentQueue, WorkerPool, waitWhile, wake;
import common.node : ChunkSlot;
import common.worldgen.building : Building, BuildingPlan;
import common.worldgen.generation : ChunkParams, GeneratedVoxels, Yield;

enum uint RESERVED_CORES = 2;
enum size_t QUEUE_CAPACITY = 1 << 14;

struct GenRequest {
    ChunkParams params;
    ChunkSlot chunk;
    bool isRestoring;
    bool isUrgent;
}

struct GenResult {
    GeneratedVoxels generated;
    ChunkSlot chunk;
    bool isRestoring;
}

struct BuildingRequest {
    BuildingPlan plan;
    uint slot;
}

struct BuildingResult {
    Building building;
    uint slot;
}

// Worker threads take chunk and building tasks from lock-free queues and hand results back the same way; the main
// thread alone touches the graph, applying results as it drains them. Chunks near the camera go in their own queue,
// which workers empty before the rest.
struct TaskQueues {
    ConcurrentQueue!GenRequest generations;
    ConcurrentQueue!GenRequest urgent;
    ConcurrentQueue!BuildingRequest buildings;
    ConcurrentQueue!GenResult generated;
    ConcurrentQueue!BuildingResult built;
    WorkerPool* pool;
    shared uint completed;
    shared uint isAwaiting;

    static TaskQueues* make() {
        TaskQueues* queues = cast(TaskQueues*) calloc(1, TaskQueues.sizeof);
        queues.generations = ConcurrentQueue!GenRequest.make(QUEUE_CAPACITY);
        queues.urgent = ConcurrentQueue!GenRequest.make(QUEUE_CAPACITY);
        queues.buildings = ConcurrentQueue!BuildingRequest.make(QUEUE_CAPACITY);
        queues.generated = ConcurrentQueue!GenResult.make(QUEUE_CAPACITY);
        queues.built = ConcurrentQueue!BuildingResult.make(QUEUE_CAPACITY);
        return queues;
    }

    void announce() {
        atomicOp!"+="(completed, 1);
        if (atomicLoad(isAwaiting) != 0) {
            wake(completed);
        }
    }

    void await(uint seen) {
        atomicStore(isAwaiting, 1);
        if (atomicLoad(completed) == seen) {
            waitWhile(completed, seen);
        }
        atomicStore(isAwaiting, 0);
    }

    void release() {
        GenRequest request;
        while (generations.pop(request)) {
        }
        while (urgent.pop(request)) {
        }
        BuildingRequest building;
        while (buildings.pop(building)) {
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
    if (queues.buildings.pop(building)) {
        BuildingResult made = BuildingResult(Building.make(building.plan), building.slot);
        building.plan.release();
        bool isPushed = queues.built.push(made);
        assert(isPushed);
        queues.announce();
        return true;
    } else if (queues.urgent.pop(request) || queues.generations.pop(request)) {
        JobHelp help = JobHelp(queues.pool, worker);
        bool isPushed = queues.generated.push(GenResult(request.params.generateVoxels(Yield(&yieldToJob, &help)), request.chunk, request.isRestoring));
        assert(isPushed);
        queues.announce();
        return true;
    } else {
        return false;
    }
}

// Pushes what fits from the front of the pending list; the rest moves to the front and waits for the next push.
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
    if (cores > RESERVED_CORES) {
        return cast(uint)(cores - RESERVED_CORES);
    } else {
        return 1;
    }
}
