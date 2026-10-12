module client.streaming;

import core.atomic : atomicLoad;
import core.stdc.math : acoshf, coshf;
import core.stdc.stdlib : calloc, free;
import core.sys.posix.unistd : _SC_NPROCESSORS_ONLN, sysconf;
import base.array : Array;
import base.clock : nowMilliseconds;
import base.parallel : Executor, ParallelJob, TaskSource, WorkerPool;
import base.units : Length;
import client.arrivals : Integrator;
import client.tasks : BuildingRequest, BuildingResult, GenRequest, GenResult, QUEUE_CAPACITY, TaskQueues, pushedPrefix, takeTask, workerThreadCount;
import common.character.features : RequiredChunks, visitCells;
import common.eviction : KEEP_RADIUS, Unloaded;
import common.graph : Graph;
import common.node : ChunkSlot, ChunkState, Occupancy;
import common.position : Position;
import common.traversal : NearbyNode;
import common.view : GraphView;
import common.worldgen.building : BuildingPlan;
import common.worldgen.generation : ChunkParams, GeneratedVoxels;
import geometry.honeycomb : CORNER_COUNT, CUBE_RADIUS, Corner, cubeCenter;
import geometry.lorentz : Motion, Point;

enum size_t LOOKAHEAD_PER_CANDIDATE = 8;
enum double RESCAN = 0;
enum uint MAX_SCAN_NODES_PER_FRAME = 4096;
enum size_t SCAN_WINDOW = 4096;
enum uint IN_FLIGHT_PER_WORKER = 256;
enum size_t INTEGRATION_BATCH = 4096;
enum Length FOCUS_REACH = Length(0.75f);
enum double NEAR_REFRESH_TRAVEL = 0.25;
enum uint NEAR_BANDS = 2;
immutable float[NEAR_BANDS] NEAR_BAND_RADII = [1.5f, 3.0f];

struct ScanOutcome {
    float nearestOutOfRange;
    float nearestDropped;
    bool isWaitingOnBuilding;
    bool isInterrupted;
}

struct ScanRange {
    Point!float camera;
    float range;
    float threshold;
    float keepRange;
    float keepThreshold;

    static ScanRange make(Point!float camera, float range, float keepRange) {
        return ScanRange(camera, range, coshf(range), keepRange, coshf(keepRange));
    }

    double margin(ScanOutcome outcome) const {
        float fresh = outcome.nearestOutOfRange == float.infinity ? float.infinity : acoshf(outcome.nearestOutOfRange) - range;
        float dropped = outcome.nearestDropped == float.infinity ? float.infinity : acoshf(outcome.nearestDropped) - keepRange;
        return fresh < dropped ? fresh : dropped;
    }
}

struct PlannedChunk {
    ChunkSlot chunk;
    bool isRestoring;
    bool isUrgent;
}

struct PlannedParams {
    ChunkParams params;
    GeneratedVoxels generated;
    Occupancy predicted;
    bool isFailed;
}

// Jobs read the graph and write only the chunks they were given, through ChunkStore.existing.
struct ParamsJob {
    Graph* graph;
    const(PlannedChunk)* chunks;
    PlannedParams* made;
}

// Runs on any thread while the graph only gets read: a view finishes what the main thread left undone, and anything
// it cannot decide is made again on the main thread.
void computeParams(void* context, size_t index, uint worker) {
    ParamsJob* job = cast(ParamsJob*) context;
    GraphView* view = &job.graph.threadViews[worker];
    ChunkSlot chunk = job.chunks[index].chunk;
    PlannedParams* made = &job.made[index];
    made.isFailed = !view.chunkStructureAt(chunk.slot).isKnown;
    if (!made.isFailed) {
        made.params = ChunkParams.make(*view, chunk.slot, chunk.corner);
        made.isFailed = view.isBlocked;
        if (view.isBlocked) {
            view.forget();
        } else {
            made.predicted = made.params.predictOccupancy();
            if (!job.chunks[index].isRestoring) {
                job.graph.chunks.existing(chunk).predicted = made.predicted;
                if (made.predicted == Occupancy.empty) {
                    made.generated = made.params.generateVoxels();
                }
            }
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
    foreach (index; 0 .. CORNER_COUNT) {
        Corner corner = cast(Corner) index;
        ChunkState state = graph.chunks.at(ChunkSlot(nearbyNode.slot, corner)).state;
        if (state == ChunkState.fresh || state == ChunkState.dropped) {
            float product = range.camera.coshDistance(nearbyNode.transform * corner.cubeCenter);
            bool isFresh = state == ChunkState.fresh;
            bool isOutOfRange = product > (isFresh ? range.threshold : range.keepThreshold);
            if (!isOutOfRange && isFresh) {
                found.freshInRange |= 1u << index;
            } else if (!isOutOfRange) {
                found.droppedInRange |= 1u << index;
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

struct NearBands {
    Array!uint[NEAR_BANDS] bands;

    void release() {
        foreach (ref band; bands) {
            band.release();
        }
    }
}

struct NearJob {
    const(NearbyNode)* nodes;
    NearBands* outputs;
    Point!float camera;
    float[NEAR_BANDS] thresholds;
}

void sortIntoBand(void* context, size_t item, uint worker) {
    NearJob* job = cast(NearJob*) context;
    float product = job.camera.coshDistance(job.nodes[item].transform * Point!float.origin());
    uint band = 0;
    while (band < NEAR_BANDS && product > job.thresholds[band]) {
        band += 1;
    }
    if (band < NEAR_BANDS) {
        job.outputs[worker].bands[band].append(cast(uint) item);
    }
}

// Decides which chunks to load and when: it walks the nearby set asking for chunks in range, plans their parameters
// on every thread, hands them to the workers and joins what comes back to the graph.
struct Streamer {
    Array!GenRequest requests;
    Array!GenRequest urgentRequests;
    Array!BuildingRequest buildingRequests;
    Array!PlannedChunk planned;
    Array!PlannedParams made;
    Array!ScanFacts facts;
    Array!double rescanAt;
    Array!uint waiting;
    Array!uint nearCamera;
    RequiredChunks around;
    Integrator integrator;
    TaskQueues* queues;
    WorkerPool* pool;
    NearBands* bands;
    double travel = 0;
    double nearTravel = 0;
    size_t nearHead;
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
        streamer.integrator = Integrator.make(streamer.pool.participants());
        streamer.bands = cast(NearBands*) calloc(streamer.pool.participants(), NearBands.sizeof);
        return streamer;
    }

    void planParams(ref Graph graph) {
        if (planned.length > 0) {
            made.resize(planned.length);
            graph.threadViews.begin(graph, pool.participants());
            ParamsJob context = ParamsJob(&graph, planned.ptr, made.ptr);
            ParallelJob job = ParallelJob(&computeParams, &context, double.infinity, planned.length);
            pool.run(&job);
            graph.threadViews.finish(graph);
            foreach (index, plan; planned.slice()) {
                PlannedParams* result = &made.ptr[index];
                if (result.isFailed) {
                    result.params = ChunkParams.make(graph.view, plan.chunk.slot, plan.chunk.corner);
                    result.predicted = result.params.predictOccupancy();
                    if (!plan.isRestoring) {
                        graph.chunks.existing(plan.chunk).predicted = result.predicted;
                        if (result.predicted == Occupancy.empty) {
                            result.generated = result.params.generateVoxels();
                        }
                    }
                }
                if (plan.isRestoring || result.predicted != Occupancy.empty) {
                    GenRequest request = GenRequest(result.params, plan.chunk, plan.isRestoring, plan.isUrgent);
                    if (plan.isUrgent) {
                        urgentRequests.append(request);
                    } else {
                        requests.append(request);
                    }
                } else {
                    integrator.arrivals.append(GenResult(result.generated, plan.chunk, false));
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

    // The scan walks the nearby set from its center outward and only starts over when a new set is published, which
    // can be far behind a moving camera, so the chunks right around the camera are asked for first on every drive,
    // whatever the budget.
    void requestAround(ref Graph graph, Position focus) {
        around.clear();
        visitCells(graph, focus, FOCUS_REACH, around);
        foreach (missing; around.missing.slice()) {
            graph.ensureNeighborSlot(missing.slot, missing.side);
        }
        foreach (chunk; around.chunks.slice()) {
            ChunkState state = graph.chunks.at(chunk).state;
            if (state == ChunkState.dropped) {
                plan(graph, chunk, true, true);
            } else if (state == ChunkState.fresh && isBuildingReady(graph, chunk.slot)) {
                plan(graph, chunk, false, true);
            } else if (state == ChunkState.fresh) {
                scheduleBuilding(graph, chunk.slot);
            }
        }
    }

    void drive(ref Graph graph, const(NearbyNode)[] nearby, Position focus, Motion!float cameraLocal, float distance, uint nearbyVersion, bool isUnbudgeted, double deadline) {
        if (rescanAt.length < graph.slotCount) {
            rescanAt.resize(graph.slotCount);
        }
        integrate(graph, false, deadline);
        foreach (chunk; graph.chunks.restores.slice()) {
            planned.append(PlannedChunk(chunk, true, false));
        }
        graph.chunks.restores.clear();
        ScanRange range = ScanRange.make(cameraLocal * Point!float.origin(), distance + CUBE_RADIUS, KEEP_RADIUS + CUBE_RADIUS);
        if (scanVersion != nearbyVersion) {
            scanVersion = nearbyVersion;
            scanCursor = 0;
            waiting.clear();
            findNearCamera(nearby, range.camera);
        } else if (travel - nearTravel >= NEAR_REFRESH_TRAVEL) {
            findNearCamera(nearby, range.camera);
        }
        requestAround(graph, focus);
        uint budget = requestBudget(isUnbudgeted);
        rescanBuilt(graph, nearby, range, budget);
        bool isStopped = scanNearCamera(graph, nearby, range, deadline);
        if (!isStopped) {
            scanCursor = cast(uint) scan(graph, nearby, range, budget, deadline);
        }
        planParams(graph);
        submitRequests();
    }

    void rescanBuilt(ref Graph graph, const(NearbyNode)[] nearby, ScanRange range, uint budget) {
        size_t kept = 0;
        foreach (index; waiting.slice()) {
            NearbyNode nearbyNode = nearby[index];
            bool isDone = false;
            if (!graph.structures.at(nearbyNode.slot).isBuildingQueued) {
                immutable ScanOutcome outcome = scanNode(graph, nearbyNode.slot, scanFacts(graph, nearbyNode, range), budget, false);
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
            if (isScanPending(slot) && !graph.isFinished(slot) && !graph.structures.at(slot).isCovered) {
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
                if (isScanPending(nearby[index].slot)) {
                    scanned += 1;
                    isInterrupted = scanAt(graph, nearby, index, facts.ptr[index - first], range, budget, false);
                    isStopped = isInterrupted || scanned >= MAX_SCAN_NODES_PER_FRAME || nowMilliseconds() >= deadline;
                }
                if (!isInterrupted) {
                    index += 1;
                }
            }
        }
        return index;
    }

    // Returns whether the request budget ran out partway, in which case the node is scanned again later.
    bool scanAt(ref Graph graph, const(NearbyNode)[] nearby, size_t index, ScanFacts found, ScanRange range, uint budget, bool isUrgent) {
        uint slot = nearby[index].slot;
        immutable ScanOutcome outcome = scanNode(graph, slot, found, budget, isUrgent);
        if (!outcome.isInterrupted && outcome.isWaitingOnBuilding) {
            rescanAt.ptr[slot] = RESCAN;
            waiting.append(cast(uint) index);
        } else if (!outcome.isInterrupted) {
            rescanAt.ptr[slot] = travel + range.margin(outcome);
        }
        return outcome.isInterrupted;
    }

    // The scan's order comes from where the nearby set was searched from, which a moving camera leaves behind, so the
    // nodes near the camera are picked out on every thread, nearest band first, and scanned before the rest.
    void findNearCamera(const(NearbyNode)[] nearby, Point!float camera) {
        NearJob context = NearJob(nearby.ptr, bands, camera);
        foreach (band; 0 .. NEAR_BANDS) {
            context.thresholds[band] = coshf(NEAR_BAND_RADII[band]);
        }
        ParallelJob job = ParallelJob(&sortIntoBand, &context, double.infinity, nearby.length);
        pool.run(&job);
        nearCamera.clear();
        foreach (band; 0 .. NEAR_BANDS) {
            foreach (worker; 0 .. pool.participants()) {
                nearCamera.appendAll(bands[worker].bands[band].slice());
                bands[worker].bands[band].clear();
            }
        }
        nearHead = 0;
        nearTravel = travel;
    }

    // Returns whether scanning stopped for the deadline. Chunks near the camera go out whatever is already in flight.
    bool scanNearCamera(ref Graph graph, const(NearbyNode)[] nearby, ScanRange range, double deadline) {
        bool isStopped = nowMilliseconds() >= deadline;
        while (nearHead < nearCamera.length && !isStopped) {
            uint index = nearCamera.ptr[nearHead];
            if (isScanPending(nearby[index].slot)) {
                scanAt(graph, nearby, index, scanFacts(graph, nearby[index], range), range, uint.max, true);
                isStopped = nowMilliseconds() >= deadline;
            }
            nearHead += 1;
        }
        return isStopped;
    }

    ScanOutcome scanNode(ref Graph graph, uint slot, ScanFacts found, uint budget, bool isUrgent) {
        ScanOutcome outcome = ScanOutcome(found.nearestOutOfRange, found.nearestDropped, false, false);
        uint wanted = found.freshInRange | found.droppedInRange;
        bool isReadyKnown = false;
        bool isReady = false;
        uint index = 0;
        while (index < CORNER_COUNT && !outcome.isInterrupted) {
            uint bit = 1u << index;
            if ((wanted & bit) != 0) {
                ChunkSlot chunk = ChunkSlot(slot, cast(Corner) index);
                if (requests.length + planned.length >= budget) {
                    outcome.isInterrupted = true;
                } else if ((found.droppedInRange & bit) != 0) {
                    plan(graph, chunk, true, isUrgent);
                } else {
                    if (!isReadyKnown) {
                        isReady = isBuildingReady(graph, slot);
                        isReadyKnown = true;
                    }
                    if (isReady) {
                        plan(graph, chunk, false, isUrgent);
                    } else {
                        scheduleBuilding(graph, slot);
                        outcome.isWaitingOnBuilding = true;
                    }
                }
            }
            if (!outcome.isInterrupted) {
                index += 1;
            }
        }
        return outcome;
    }

    void plan(ref Graph graph, ChunkSlot slot, bool isRestoring, bool isUrgent) {
        graph.chunks.writable(slot).state = ChunkState.generating;
        planned.append(PlannedChunk(slot, isRestoring, isUrgent));
    }

    void scheduleBuilding(ref Graph graph, uint slot) {
        if (graph.structures.buildingAt(slot) is null && !graph.structures.at(slot).isBuildingQueued) {
            graph.structures.at(slot).isBuildingQueued = true;
            graph.restoreBrushes(slot);
            buildingRequests.append(BuildingRequest(BuildingPlan.make(graph, slot), slot));
        }
    }

    // Requests that do not fit in a full queue stay at the front of their array and go out on the next drive. Only as
    // many go out as their results have room for, since a worker cannot hold on to a result it has no room to hand back.
    void submitRequests() {
        size_t generations = pushedPrefix(queues.urgent, urgentRequests, QUEUE_CAPACITY - inFlight);
        generations += pushedPrefix(queues.generations, requests, QUEUE_CAPACITY - inFlight - generations);
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
        return inFlight == 0 && buildingsInFlight == 0 && requests.length == 0 && urgentRequests.length == 0 && buildingRequests.length == 0;
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
        buildingsInFlight -= 1;
        graph.structures.at(built.slot).isBuildingQueued = false;
        if (graph.structures.buildingAt(built.slot) !is null) {
            built.building.release();
        } else {
            graph.structures.storeBuilding(built.slot, built.building);
        }
        if (built.slot < rescanAt.length) {
            rescanAt.ptr[built.slot] = RESCAN;
        }
    }

    void release() {
        foreach (index; 0 .. pool.participants()) {
            bands[index].release();
        }
        free(bands);
        bands = null;
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
        urgentRequests.release();
        planned.release();
        made.release();
        facts.release();
        nearCamera.release();
        around.release();
        rescanAt.release();
        waiting.release();
    }
}

bool isBuildingReady(ref Graph graph, uint slot) {
    return !graph.ensureStructureAt(slot) || graph.structures.buildingAt(slot) !is null;
}
