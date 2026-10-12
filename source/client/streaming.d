module client.streaming;

import core.atomic : atomicLoad, atomicOp, atomicStore, cas;
import core.stdc.math : acoshf, coshf;
import core.stdc.stdlib : calloc, free;
import core.sys.posix.unistd : _SC_NPROCESSORS_ONLN, sysconf;
import common.array : Array;
import common.clock : nowMilliseconds;
import common.coords : CHUNK_DIRECTIONS, ChunkDirection, CoordSign;
import common.dodeca : CHUNK_BOUNDING_SPHERE_RADIUS, SIDE_COUNT, Side, VERTEX_COUNT, Vertex, adjacentVertices, canonicalSides, chunkBoundingSphereCenter;
import common.eviction : KEEP_RADIUS, Unloaded;
import common.graph : Graph, NODE_HASH_MULTIPLIER, NO_SLOT, Node, ROOT_NODE;
import common.math : MIsometry, MPoint;
import common.margins : CoordsWithMargins, MarginList, copyMargin, directionIndex, hasVoidnessOtherThan, marginCoord;
import common.material : Material;
import common.neighbors : CellHop, chunkNeighborSlot, hopCell, isPredictionContradicted, touchChunksAround;
import common.node : Chunk, ChunkId, ChunkSlot, ChunkState, Integration, Occupancy, VoxelData, interiorCellAt, isArriving;
import common.parallel : ConcurrentQueue, Executor, ParallelJob, TaskSource, WorkerPool, waitWhile, wake;
import common.traversal : NearbyNode;
import common.worldgen.building : Building, BuildingPlan;
import common.view : GraphView;
import common.worldgen.generation : ChunkParams, ChunkStructure, GeneratedVoxels, Worldgen, Yield;
import common.worldgen.sky : applyDiscoveries, makeWantedWorlds;

enum uint RESERVED_CORES = 2;
enum size_t QUEUE_CAPACITY = 1 << 14;
enum size_t LOOKAHEAD_PER_CANDIDATE = 8;
enum double RESCAN = 0;
enum uint MAX_SCAN_NODES_PER_FRAME = 4096;
enum size_t SCAN_WINDOW = 4096;
enum uint IN_FLIGHT_PER_WORKER = 256;
enum size_t INTEGRATION_BATCH = 4096;

struct GenRequest {
    ChunkParams params;
    ChunkSlot chunk;
    bool isRestoring;
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

struct ScanOutcome {
    float nearestOutOfRange;
    float nearestDropped;
    bool isWaitingOnBuilding;
    bool isInterrupted;
}

struct ScanRange {
    MPoint!float camera;
    float range;
    float threshold;
    float keepRange;
    float keepThreshold;

    static ScanRange make(MPoint!float camera, float range, float keepRange) {
        return ScanRange(camera, range, coshf(range), keepRange, coshf(keepRange));
    }

    double margin(ScanOutcome outcome) const {
        float fresh = outcome.nearestOutOfRange == float.infinity ? float.infinity : acoshf(outcome.nearestOutOfRange) - range;
        float dropped = outcome.nearestDropped == float.infinity ? float.infinity : acoshf(outcome.nearestDropped) - keepRange;
        return fresh < dropped ? fresh : dropped;
    }
}

// Worker threads take chunk and building tasks from lock-free queues and hand results back the same way; the main
// thread alone touches the graph, applying results as it drains them.
struct TaskQueues {
    ConcurrentQueue!GenRequest generations;
    ConcurrentQueue!BuildingRequest buildings;
    ConcurrentQueue!GenResult generated;
    ConcurrentQueue!BuildingResult built;
    WorkerPool* pool;
    shared uint completed;
    shared uint isAwaiting;

    static TaskQueues* make() {
        TaskQueues* queues = cast(TaskQueues*) calloc(1, TaskQueues.sizeof);
        queues.generations = ConcurrentQueue!GenRequest.make(QUEUE_CAPACITY);
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
        buildings.release();
        generated.release();
        built.release();
    }
}

struct JobHelp {
    WorkerPool* pool;
    uint worker;
}

void helpWithJob(void* context) {
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
    } else if (queues.generations.pop(request)) {
        JobHelp help = JobHelp(queues.pool, worker);
        bool isPushed = queues.generated.push(GenResult(request.params.generateVoxels(Yield(&helpWithJob, &help)), request.chunk, request.isRestoring));
        assert(isPushed);
        queues.announce();
        return true;
    } else {
        return false;
    }
}

struct PlannedChunk {
    ChunkSlot chunk;
    bool isRestoring;
}

struct PlannedParams {
    ChunkParams params;
    GeneratedVoxels generated;
    Occupancy predicted;
    bool isFailed;
}

struct ParamsJob {
    const(Graph)* graph;
    GraphView* views;
    const(PlannedChunk)* chunks;
    PlannedParams* made;
}

// Runs on any thread while the graph only gets read: a view finishes what the main thread left undone, and anything
// it cannot decide is made again on the main thread.
void computeParams(void* context, size_t index, uint worker) {
    ParamsJob* job = cast(ParamsJob*) context;
    GraphView* view = &job.views[worker];
    ChunkSlot chunk = job.chunks[index].chunk;
    PlannedParams* made = &job.made[index];
    ChunkStructure structure = view.chunkStructureAt(chunk.slot);
    made.isFailed = !structure.isKnown;
    if (structure.isKnown) {
        made.params = ChunkParams.make(*view, chunk.slot, chunk.vertex, structure);
        made.isFailed = view.isBlocked;
        if (view.isBlocked) {
            view.forget();
        } else {
            made.predicted = made.params.predictOccupancy();
            if (!job.chunks[index].isRestoring) {
                job.graph.heldChunk(chunk).predicted = made.predicted;
                if (made.predicted == Occupancy.empty) {
                    made.generated = made.params.generateVoxels();
                }
            }
        }
    }
}

struct MarginPlan {
    ubyte sources;
    bool isDense;
    bool isTouched;
}

struct IntegrationOutput {
    Array!ChunkSlot adjacent;
    Array!ChunkSlot restored;
    Array!ChunkSlot holders;
    Array!ChunkSlot changed;
    Array!ChunkSlot exposed;

    void clear() {
        adjacent.clear();
        restored.clear();
        holders.clear();
        changed.clear();
        exposed.clear();
    }

    void release() {
        adjacent.release();
        restored.release();
        holders.release();
        changed.release();
        exposed.release();
    }
}

struct IntegrationJob {
    const(Graph)* graph;
    GenResult* arrivals;
    const(ChunkSlot)* targets;
    MarginPlan* plans;
    IntegrationOutput* outputs;
}

// Arrived chunks and their populated neighbors are joined in passes over every thread. Each pass writes only the
// chunk it was given, or claims a neighbor with an atomic swap of one of its fields so exactly one thread takes it;
// what the main thread must still do lands in per-thread lists.
struct Integrator {
    Array!GenResult arrivals;
    Array!ChunkSlot targets;
    Array!MarginPlan plans;
    IntegrationOutput* outputs;
    uint participants;

    static Integrator make(uint participants) {
        Integrator integrator;
        integrator.participants = participants;
        integrator.outputs = cast(IntegrationOutput*) calloc(participants, IntegrationOutput.sizeof);
        return integrator;
    }

    void run(ref Graph graph, Executor executor) {
        if (arrivals.length > 0) {
            join(graph, executor);
        }
    }

    void join(ref Graph graph, Executor executor) {
        IntegrationJob context = IntegrationJob(&graph, arrivals.ptr, null, null, outputs);
        runPass(executor, &storeArrival, &context, arrivals.length);
        runPass(executor, &claimNeighbors, &context, arrivals.length);
        foreach (arrival; arrivals.slice()) {
            targets.append(arrival.chunk);
        }
        foreach (worker; 0 .. participants) {
            targets.appendAll(outputs[worker].adjacent.slice());
            graph.restores.appendAll(outputs[worker].restored.slice());
        }
        plans.resize(targets.length);
        context.targets = targets.ptr;
        context.plans = plans.ptr;
        runPass(executor, &planMargins, &context, targets.length);
        runPass(executor, &densifyTarget, &context, targets.length);
        runPass(executor, &copyMargins, &context, targets.length);
        runPass(executor, &finishTarget, &context, targets.length);
        foreach (worker; 0 .. participants) {
            graph.changedChunks.appendAll(outputs[worker].changed.slice());
        }
        foreach (worker; 0 .. participants) {
            foreach (holder; outputs[worker].holders.slice()) {
                graph.markChanged(holder);
            }
            foreach (exposed; outputs[worker].exposed.slice()) {
                graph.resolveIfExposed(exposed);
            }
            outputs[worker].clear();
        }
        arrivals.clear();
        targets.clear();
    }

    void release() {
        foreach (arrival; arrivals.slice()) {
            arrival.generated.voxels.release();
        }
        foreach (worker; 0 .. participants) {
            outputs[worker].release();
        }
        free(outputs);
        outputs = null;
        arrivals.release();
        targets.release();
        plans.release();
    }
}

void runPass(Executor executor, void function(void* context, size_t item, uint worker) pass, IntegrationJob* context, size_t count) {
    ParallelJob job = ParallelJob(pass, context, double.infinity, count);
    executor.run(&job);
}

void storeArrival(void* context, size_t item, uint worker) {
    IntegrationJob* job = cast(IntegrationJob*) context;
    GenResult arrival = job.arrivals[item];
    Chunk* chunk = job.graph.heldChunk(arrival.chunk);
    chunk.voxels = arrival.generated.voxels;
    chunk.hasDeferredMaterials = arrival.generated.hasDeferredMaterials;
    chunk.state = ChunkState.populated;
    chunk.integration = arrival.isRestoring ? Integration.restoring : Integration.populating;
}

// A dropped neighbor of a new chunk is made again, and a populated one that did not arrive takes the new margins;
// either way the first thread to swap its field claims it.
void claimNeighbors(void* context, size_t item, uint worker) {
    IntegrationJob* job = cast(IntegrationJob*) context;
    claimNeighborsOf(*job.graph, job.arrivals[item], job.outputs[worker]);
}

void claimNeighborsOf(ref const Graph graph, GenResult arrival, ref IntegrationOutput output) {
    foreach (direction; CHUNK_DIRECTIONS) {
        ChunkSlot neighbor = graph.chunkNeighborSlot(arrival.chunk, direction);
        if (neighbor.slot != NO_SLOT && graph.hasChunks(neighbor.slot)) {
            Chunk* other = graph.heldChunk(neighbor);
            shared(ChunkState)* state = cast(shared(ChunkState)*) &other.state;
            if (!arrival.isRestoring && cas(state, ChunkState.dropped, ChunkState.generating)) {
                output.restored.append(neighbor);
            } else if (atomicLoad(*state) == ChunkState.populated && cas(cast(shared(Integration)*) &other.integration, Integration.none, Integration.adjacent)) {
                output.adjacent.append(neighbor);
            }
        }
    }
}

// A target takes margins from every populated neighbor when it arrived itself, and otherwise only from the neighbors
// that arrived; it becomes dense when any of those margins could show a face its solid fill would hide.
void planMargins(void* context, size_t item, uint worker) {
    IntegrationJob* job = cast(IntegrationJob*) context;
    job.plans[item] = planTarget(*job.graph, job.targets[item], job.outputs[worker].holders);
}

// Chunks a new chunk touches are meshed again and resolved if their deferred materials now show; a chunk is queued
// for meshing by whichever thread first marks it queued.
void finishTarget(void* context, size_t item, uint worker) {
    IntegrationJob* job = cast(IntegrationJob*) context;
    ChunkSlot target = job.targets[item];
    Chunk* chunk = job.graph.heldChunk(target);
    chunk.integration = Integration.none;
    if (job.plans[item].isTouched) {
        if (!chunk.voxels.isSolid() && cas(cast(shared(bool)*) &chunk.isQueued, false, true)) {
            job.outputs[worker].changed.append(target);
        }
        if (chunk.hasDeferredMaterials && chunk.voxels.hasVoidInMargins(job.graph.layout.dimension)) {
            job.outputs[worker].exposed.append(target);
        }
    }
}

MarginPlan planTarget(ref const Graph graph, ChunkSlot target, ref Array!ChunkSlot holders) {
    const(Chunk)* chunk = graph.chunkAt(target);
    MarginPlan plan = MarginPlan(0, false, chunk.integration == Integration.populating);
    foreach (direction; CHUNK_DIRECTIONS) {
        ChunkSlot neighbor = graph.chunkNeighborSlot(target, direction);
        if (neighbor.slot != NO_SLOT && graph.chunkAt(neighbor).state == ChunkState.populated) {
            const(Chunk)* other = graph.chunkAt(neighbor);
            if (chunk.integration.isArriving() || other.integration.isArriving()) {
                size_t which = directionIndex(direction);
                plan.sources |= cast(ubyte)(1u << which);
                plan.isDense |= !chunk.voxels.isSolid() || graph.margins.hasVoidnessOtherThan(other.voxels, graph.margins.list(target.vertex, which, MarginList.theirBoundary), chunk.voxels.solidMaterial == Material.none);
                plan.isTouched |= other.integration == Integration.populating;
            }
        }
    }
    if (chunk.integration == Integration.populating && (*chunk).isPredictionContradicted()) {
        graph.touchChunksAround(target, holders);
    }
    return plan;
}

void densifyTarget(void* context, size_t item, uint worker) {
    IntegrationJob* job = cast(IntegrationJob*) context;
    if (job.plans[item].isDense) {
        job.graph.heldChunk(job.targets[item]).voxels.toDense(job.graph.layout.dimension);
    }
}

void copyMargins(void* context, size_t item, uint worker) {
    IntegrationJob* job = cast(IntegrationJob*) context;
    if (job.plans[item].isDense) {
        copyTargetMargins(*job.graph, job.targets[item], job.plans[item].sources);
    }
}

void copyTargetMargins(ref const Graph graph, ChunkSlot target, ubyte sources) {
    Chunk* chunk = graph.heldChunk(target);
    foreach (direction; CHUNK_DIRECTIONS) {
        size_t which = directionIndex(direction);
        if ((sources & (1u << which)) != 0) {
            const(Chunk)* other = graph.chunkAt(graph.chunkNeighborSlot(target, direction));
            copyMargin(chunk.voxels, graph.margins.list(target.vertex, which, MarginList.ownMargin), other.voxels, graph.margins.list(target.vertex, which, MarginList.theirBoundary));
        }
    }
}

struct ScanFacts {
    uint freshInRange;
    uint droppedInRange;
    float nearestOutOfRange;
    float nearestDropped;
}

ScanFacts scanFacts(ref const Graph graph, NearbyNode nearbyNode, ScanRange range) {
    ScanFacts found = ScanFacts(0, 0, float.infinity, float.infinity);
    foreach (vertexIndex; 0 .. VERTEX_COUNT) {
        Vertex vertex = cast(Vertex) vertexIndex;
        ChunkState state = graph.chunkAt(ChunkSlot(nearbyNode.slot, vertex)).state;
        if (state == ChunkState.fresh || state == ChunkState.dropped) {
            float product = -range.camera.mip((nearbyNode.transform * vertex.chunkBoundingSphereCenter).vec);
            bool isFresh = state == ChunkState.fresh;
            bool isOutOfRange = product > (isFresh ? range.threshold : range.keepThreshold);
            if (!isOutOfRange && isFresh) {
                found.freshInRange |= 1u << vertexIndex;
            } else if (!isOutOfRange) {
                found.droppedInRange |= 1u << vertexIndex;
            } else if (isFresh && product < found.nearestOutOfRange) {
                found.nearestOutOfRange = product;
            } else if (!isFresh && product < found.nearestDropped) {
                found.nearestDropped = product;
            }
        }
    }
    return found;
}

struct ScanJob {
    const(Graph)* graph;
    const(Streamer)* streamer;
    const(NearbyNode)* nodes;
    ScanFacts* facts;
    ScanRange range;
}

void gatherScanFacts(void* context, size_t item, uint worker) {
    ScanJob* job = cast(ScanJob*) context;
    NearbyNode nearbyNode = job.nodes[item];
    if (job.streamer.isScanPending(nearbyNode.slot)) {
        job.facts[item] = scanFacts(*job.graph, nearbyNode, job.range);
    }
}

struct Streamer {
    Array!GenRequest requests;
    Array!BuildingRequest buildingRequests;
    Array!PlannedChunk planned;
    Array!PlannedParams made;
    Array!ScanFacts facts;
    Array!double rescanAt;
    Array!uint waiting;
    Integrator integrator;
    TaskQueues* queues;
    WorkerPool* pool;
    GraphView* views;
    double travel = 0;
    uint workerCount;
    uint inFlight;
    uint buildingsInFlight;
    uint scanCursor;
    uint scanVersion;

    static Streamer make() {
        Streamer streamer;
        streamer.queues = TaskQueues.make();
        streamer.workerCount = workerThreadCount(sysconf(_SC_NPROCESSORS_ONLN));
        streamer.pool = WorkerPool.make(streamer.workerCount, TaskSource(&takeTask, streamer.queues));
        streamer.queues.pool = streamer.pool;
        streamer.views = cast(GraphView*) calloc(streamer.pool.participants(), GraphView.sizeof);
        streamer.integrator = Integrator.make(streamer.pool.participants());
        return streamer;
    }

    void planParams(ref Graph graph) {
        if (planned.length > 0) {
            made.resize(planned.length);
            foreach (index; 0 .. pool.participants()) {
                views[index].graph = &graph;
                views[index].forget();
            }
            ParamsJob context = ParamsJob(&graph, views, planned.ptr, made.ptr);
            ParallelJob job = ParallelJob(&computeParams, &context, double.infinity, planned.length);
            pool.run(&job);
            foreach (index; 0 .. pool.participants()) {
                graph.applyDiscoveries(views[index]);
                graph.makeWantedWorlds(views[index]);
            }
            foreach (index, plan; planned.slice()) {
                PlannedParams* result = &made.ptr[index];
                if (result.isFailed) {
                    result.params = ChunkParams.make(graph, plan.chunk.slot, plan.chunk.vertex);
                    result.predicted = result.params.predictOccupancy();
                    if (!plan.isRestoring) {
                        graph.chunkFor(plan.chunk).predicted = result.predicted;
                        if (result.predicted == Occupancy.empty) {
                            result.generated = result.params.generateVoxels();
                        }
                    }
                }
                if (plan.isRestoring) {
                    requests.append(GenRequest(result.params, plan.chunk, true));
                } else {
                    if (result.predicted != Occupancy.empty) {
                        requests.append(GenRequest(result.params, plan.chunk, false));
                    } else {
                        integrator.arrivals.append(GenResult(result.generated, plan.chunk, false));
                    }
                }
            }
            planned.clear();
            integrator.run(graph, executor());
        }
    }

    void runParallel(ParallelJob* job) {
        pool.run(job);
    }

    Executor executor() {
        return Executor(pool);
    }

    void drive(ref Graph graph, const(NearbyNode)[] nearby, MIsometry!float cameraLocal, float distance, uint nearbyVersion, bool isUnbudgeted, double deadline) {
        if (rescanAt.length < graph.nodeCount) {
            rescanAt.resize(graph.nodeCount);
        }
        integrate(graph, false, deadline);
        foreach (chunk; graph.restores.slice()) {
            planned.append(PlannedChunk(chunk, true));
        }
        graph.restores.clear();
        if (scanVersion != nearbyVersion) {
            scanVersion = nearbyVersion;
            scanCursor = 0;
            waiting.clear();
        }
        ScanRange range = ScanRange.make(cameraLocal * MPoint!float.origin(), distance + CHUNK_BOUNDING_SPHERE_RADIUS, KEEP_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS);
        uint budget = requestBudget(isUnbudgeted);
        rescanBuilt(graph, nearby, range, budget);
        scanCursor = cast(uint) scan(graph, nearby, range, budget, deadline);
        planParams(graph);
        submitRequests();
    }

    void rescanBuilt(ref Graph graph, const(NearbyNode)[] nearby, ScanRange range, uint budget) {
        size_t kept = 0;
        foreach (index; waiting.slice()) {
            NearbyNode nearbyNode = nearby[index];
            bool isDone = false;
            if (!graph.nodeAt(nearbyNode.slot).isBuildingQueued) {
                immutable ScanOutcome outcome = scanNode(graph, nearbyNode.slot, scanFacts(graph, nearbyNode, range), budget);
                isDone = !outcome.isInterrupted && !outcome.isWaitingOnBuilding;
                if (isDone) {
                    rescanAt.ptr[nearbyNode.slot] = travel + range.margin(outcome);
                }
            }
            if (!isDone) {
                waiting.ptr[kept] = index;
                kept += 1;
            }
        }
        waiting.length = kept;
    }

    uint requestBudget(bool isUnbudgeted) const {
        if (isUnbudgeted) {
            return uint.max;
        } else if (inFlight < workerCount * IN_FLIGHT_PER_WORKER) {
            return workerCount * IN_FLIGHT_PER_WORKER - inFlight;
        } else {
            return 0;
        }
    }

    bool isScanPending(uint slot) const {
        return slot < rescanAt.length && rescanAt.ptr[slot] <= travel;
    }

    // Nodes the scan reaches next whose chunks need their structure first.
    void collectUnstructured(ref const Graph graph, const(NearbyNode)[] nearby, ref Array!uint into, size_t limit) const {
        size_t index = scanCursor;
        size_t end = index + limit * LOOKAHEAD_PER_CANDIDATE;
        while (index < nearby.length && index < end && into.length < limit) {
            uint slot = nearby[index].slot;
            if (isScanPending(slot) && !graph.hasStructureAt(slot) && !graph.nodeAt(slot).isCovered) {
                into.append(slot);
            }
            index += 1;
        }
    }

    // Which chunks of the next nodes are in range is worked out on every thread a window at a time, and this thread
    // then acts on those facts in order, so the request budget and the deadline still stop it at the same node.
    size_t scan(ref Graph graph, const(NearbyNode)[] nearby, ScanRange range, uint budget, double deadline) {
        uint scanned = 0;
        size_t index = scanCursor;
        bool isStopped = nowMilliseconds() >= deadline;
        while (index < nearby.length && !isStopped) {
            size_t first = index;
            size_t end = first + SCAN_WINDOW < nearby.length ? first + SCAN_WINDOW : nearby.length;
            facts.resize(end - first);
            ScanJob context = ScanJob(&graph, &this, nearby.ptr + first, facts.ptr, range);
            ParallelJob job = ParallelJob(&gatherScanFacts, &context, double.infinity, end - first);
            pool.run(&job);
            bool isInterrupted = false;
            while (index < end && !isStopped) {
                uint slot = nearby[index].slot;
                if (isScanPending(slot)) {
                    scanned += 1;
                    immutable ScanOutcome outcome = scanNode(graph, slot, facts.ptr[index - first], budget);
                    isInterrupted = outcome.isInterrupted;
                    if (!isInterrupted && outcome.isWaitingOnBuilding) {
                        rescanAt.ptr[slot] = RESCAN;
                        waiting.append(cast(uint) index);
                    } else if (!isInterrupted) {
                        rescanAt.ptr[slot] = travel + range.margin(outcome);
                    }
                    isStopped = isInterrupted || scanned >= MAX_SCAN_NODES_PER_FRAME || nowMilliseconds() >= deadline;
                }
                if (!isInterrupted) {
                    index += 1;
                }
            }
        }
        return index;
    }

    ScanOutcome scanNode(ref Graph graph, uint slot, ScanFacts found, uint budget) {
        ScanOutcome outcome = ScanOutcome(found.nearestOutOfRange, found.nearestDropped, false, false);
        uint wanted = found.freshInRange | found.droppedInRange;
        bool isReadyKnown = false;
        bool isReady = false;
        uint vertexIndex = 0;
        while (vertexIndex < VERTEX_COUNT && !outcome.isInterrupted) {
            uint bit = 1u << vertexIndex;
            if ((wanted & bit) != 0) {
                ChunkSlot chunk = ChunkSlot(slot, cast(Vertex) vertexIndex);
                if (requests.length + planned.length >= budget) {
                    outcome.isInterrupted = true;
                } else if ((found.droppedInRange & bit) != 0) {
                    restore(graph, chunk);
                } else {
                    if (!isReadyKnown) {
                        isReady = isBuildingReady(graph, slot);
                        isReadyKnown = true;
                    }
                    if (isReady) {
                        request(graph, chunk);
                    } else {
                        scheduleBuilding(graph, slot);
                        outcome.isWaitingOnBuilding = true;
                    }
                }
            }
            if (!outcome.isInterrupted) {
                vertexIndex += 1;
            }
        }
        return outcome;
    }

    void restore(ref Graph graph, ChunkSlot slot) {
        graph.chunkFor(slot).state = ChunkState.generating;
        planned.append(PlannedChunk(slot, true));
    }

    void scheduleBuilding(ref Graph graph, uint slot) {
        if (!graph.nodeAt(slot).hasBuilding && !graph.nodeAt(slot).isBuildingQueued) {
            graph.nodeAt(slot).isBuildingQueued = true;
            graph.restoreBrushes(slot);
            buildingRequests.append(BuildingRequest(BuildingPlan.make(graph, slot), slot));
        }
    }

    void request(ref Graph graph, ChunkSlot slot) {
        graph.chunkFor(slot).state = ChunkState.generating;
        planned.append(PlannedChunk(slot, false));
    }

    // Requests that do not fit in a full queue stay at the front of their array and go out on the next drive. Only as
    // many go out as their results have room for, since a worker cannot hold on to a result it has no room to hand back.
    void submitRequests() {
        size_t generations = pushedPrefix(queues.generations, requests, QUEUE_CAPACITY - inFlight);
        size_t buildings = pushedPrefix(queues.buildings, buildingRequests, QUEUE_CAPACITY - buildingsInFlight);
        inFlight += cast(uint) generations;
        buildingsInFlight += cast(uint) buildings;
        if (generations > 0 || buildings > 0) {
            pool.signal();
        }
    }

    void forget(const(Unloaded)[] unloaded) {
        foreach (entry; unloaded) {
            if (entry.slot < rescanAt.length) {
                rescanAt.ptr[entry.slot] = RESCAN;
            }
        }
    }

    bool isIdle() const {
        return inFlight == 0 && buildingsInFlight == 0 && requests.length == 0 && buildingRequests.length == 0;
    }

    void settle(ref Graph graph) {
        while (!isIdle()) {
            submitRequests();
            uint seen = atomicLoad(queues.completed);
            if (integrate(graph, true, 0) == 0) {
                queues.await(seen);
            }
        }
    }

    uint integrate(ref Graph graph, bool isWaiting, double deadline) {
        uint integrated = 0;
        BuildingResult built;
        while (queues.built.pop(built)) {
            integrateBuilding(graph, built);
            integrated += 1;
        }
        GenResult result;
        while ((isWaiting || nowMilliseconds() < deadline) && integrator.arrivals.length < INTEGRATION_BATCH && queues.generated.pop(result)) {
            inFlight -= 1;
            integrated += 1;
            integrator.arrivals.append(result);
        }
        integrator.run(graph, executor());
        return integrated;
    }

    void integrateBuilding(ref Graph graph, BuildingResult built) {
        Node* node = graph.nodeAt(built.slot);
        buildingsInFlight -= 1;
        node.isBuildingQueued = false;
        if (node.hasBuilding) {
            built.building.release();
        } else {
            node.building = built.building;
            node.hasBuilding = true;
        }
        if (built.slot < rescanAt.length) {
            rescanAt.ptr[built.slot] = RESCAN;
        }
    }

    void release() {
        foreach (index; 0 .. pool.participants()) {
            views[index].release();
        }
        free(views);
        views = null;
        integrator.release();
        pool.release();
        free(pool);
        pool = null;
        workerCount = 0;
        queues.release();
        free(queues);
        queues = null;
        foreach (request; buildingRequests.slice()) {
            request.plan.release();
        }
        buildingRequests.release();
        requests.release();
        planned.release();
        made.release();
        facts.release();
        rescanAt.release();
        waiting.release();
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

bool isBuildingReady(ref Graph graph, uint slot) {
    return !graph.ensureStructureAt(slot) || graph.nodeAt(slot).hasBuilding;
}

uint workerThreadCount(long cores) {
    if (cores > RESERVED_CORES) {
        return cast(uint)(cores - RESERVED_CORES);
    } else {
        return 1;
    }
}

void generateNow(ref Graph graph, ChunkSlot chunk) {
    if (graph.chunkAt(chunk).state == ChunkState.fresh) {
        ChunkParams params = ChunkParams.make(graph, chunk.slot, chunk.vertex);
        graph.chunkFor(chunk).predicted = params.predictOccupancy();
        graph.populateChunk(chunk, params.generateVoxels());
    }
}

void populateChunk(ref Graph graph, ChunkSlot chunk, GeneratedVoxels generated) {
    Integrator integrator = Integrator.make(1);
    integrator.arrivals.append(GenResult(generated, chunk, false));
    integrator.run(graph, Executor(null));
    integrator.release();
}

bool hasPopulatedNeighbor(ref const Graph graph, ChunkSlot chunk, ChunkDirection direction) {
    ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
    return neighbor.slot != NO_SLOT && graph.chunkAt(neighbor).state == ChunkState.populated;
}

void connectMargins(ref Graph graph, ChunkSlot chunk) {
    Chunk* target = graph.chunkFor(chunk);
    foreach (direction; CHUNK_DIRECTIONS) {
        if (graph.hasPopulatedNeighbor(chunk, direction)) {
            ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
            target.voxels.fixMargins(graph.chunkFor(neighbor).voxels, graph.margins, chunk.vertex, direction);
            graph.markChanged(neighbor);
        }
    }
    graph.markChanged(chunk);
}

void resolveIfExposed(ref Graph graph, ChunkSlot chunk) {
    const(Chunk)* target = graph.chunkAt(chunk);
    if (target.hasDeferredMaterials && target.voxels.hasVoidInMargins(graph.layout.dimension)) {
        graph.resolveMaterials(chunk);
    }
}

void resolveMaterials(ref Graph graph, ChunkSlot chunk) {
    ChunkParams params = ChunkParams.make(graph, chunk.slot, chunk.vertex);
    params.isResolvingMaterials = true;
    GeneratedVoxels generated = params.generateVoxels();
    Chunk* target = graph.chunkFor(chunk);
    target.voxels.release();
    target.voxels = generated.voxels;
    target.hasDeferredMaterials = false;
    graph.connectMargins(chunk);
}

enum ubyte TEST_DIMENSION = 4;
enum ulong TEST_MIX = 0xBF58476D1CE4E5B9;
enum size_t TEST_KINDS = 4;
enum size_t TEST_VOID_ODDS = 3;
enum size_t TEST_BATCH_STRIDE = 3;

GeneratedVoxels testVoxels(size_t chunk) {
    if (chunk % TEST_KINDS == 0) {
        return GeneratedVoxels(VoxelData.fromMaterial(Material.granite), false);
    } else if (chunk % TEST_KINDS == 1) {
        return GeneratedVoxels(VoxelData.fromMaterial(Material.none), false);
    } else {
        VoxelData voxels = VoxelData.fromMaterial(Material.granite);
        Material[] data = voxels.toDense(TEST_DIMENSION);
        foreach (cell; 0 .. cast(size_t) TEST_DIMENSION * TEST_DIMENSION * TEST_DIMENSION) {
            if (((chunk * NODE_HASH_MULTIPLIER + cell) * TEST_MIX >> 32) % TEST_VOID_ODDS == 0) {
                data[interiorCellAt(TEST_DIMENSION, cell).toIndex(TEST_DIMENSION)] = Material.none;
            }
        }
        voxels.initializeMargins(TEST_DIMENSION);
        return GeneratedVoxels(voxels, false);
    }
}

// Every face cell of a margin must agree with the neighbor's cell about voidness, or the mesher shows or hides faces wrongly.
bool hasConsistentMargins(ref const Graph graph, ChunkSlot chunk) {
    const(Chunk)* own = graph.chunkAt(chunk);
    bool isConsistent = true;
    foreach (direction; CHUNK_DIRECTIONS) {
        if (graph.hasPopulatedNeighbor(chunk, direction)) {
            foreach (j; 1 .. TEST_DIMENSION + 1) {
                foreach (i; 1 .. TEST_DIMENSION + 1) {
                    CoordsWithMargins margin = CoordsWithMargins.fromTuv(marginCoord(TEST_DIMENSION, direction.sign), cast(ubyte) i, cast(ubyte) j, direction.axis);
                    CellHop hop = graph.hopCell(chunk, margin, direction.axis);
                    bool isOwnVoid = own.voxels.get(margin.toIndex(TEST_DIMENSION)) == Material.none;
                    bool isTheirVoid = graph.chunkAt(hop.chunk).voxels.get(hop.coords.toIndex(TEST_DIMENSION)) == Material.none;
                    isConsistent = isConsistent && isOwnVoid == isTheirVoid;
                }
            }
        }
    }
    return isConsistent;
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.makeTerrain());
    uint root = graph.slotOf(ROOT_NODE);
    foreach (side; 0 .. SIDE_COUNT) {
        graph.ensureNeighborSlot(root, cast(Side) side);
    }
    size_t chunkCount = cast(size_t) graph.nodeCount * VERTEX_COUNT;
    Integrator integrator = Integrator.make(1);
    foreach (batch; 0 .. 2) {
        foreach (index; 0 .. chunkCount) {
            if (index / TEST_BATCH_STRIDE % 2 == batch) {
                graph.chunkFor(ChunkSlot.fromIndex(index)).state = ChunkState.generating;
                integrator.arrivals.append(GenResult(testVoxels(index), ChunkSlot.fromIndex(index), batch == 1 && index % 2 == 0));
            }
        }
        integrator.run(graph, Executor(null));
        foreach (index; 0 .. chunkCount) {
            if (graph.chunkAt(ChunkSlot.fromIndex(index)).state == ChunkState.populated) {
                assert(graph.hasConsistentMargins(ChunkSlot.fromIndex(index)));
            }
        }
    }
    integrator.release();
    graph.release();
}

ChunkId chunkNeighborId(ref const Graph graph, ChunkId chunk, ChunkDirection direction) {
    if (direction.sign == CoordSign.plus) {
        return ChunkId(chunk.node, chunk.vertex.adjacentVertices[direction.axis]);
    } else {
        return ChunkId(graph.neighbor(chunk.node, chunk.vertex.canonicalSides[direction.axis]), chunk.vertex);
    }
}
