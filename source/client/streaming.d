module client.streaming;

import core.atomic : atomicLoad;
import core.stdc.math : acoshf, coshf;
import core.stdc.stdlib : calloc, free;
import core.sys.posix.unistd : _SC_NPROCESSORS_ONLN, sysconf;
import base.array : Array;
import base.clock : nowMilliseconds;
import base.flags : Readiness;
import base.numbers : lowerOf;
import base.parallel : ConcurrentQueue, Executor, ParallelJob, TaskSource, WorkerPool;
import base.units : Length;
import client.arrivals : Integrator;
import client.tasks : BuildingRequest, BuildingResult, GenKind, GenRequest, GenResult, QUEUE_CAPACITY, TaskQueues, pushedPrefix, takeTask, workerThreadCount;
import common.character.features : RequiredChunks, visitCells;
import common.eviction : KEEP_RADIUS, Unloaded;
import common.graph : Graph;
import common.node : ChunkSlot, ChunkState, Occupancy;
import common.position : Position;
import common.traversal : NO_DEADLINE, NearbyNode;
import common.view : GraphView;
import common.worldgen.generation : ChunkParams, GeneratedVoxels;
import common.worldgen.store : NodeMark, NodeStructure;
import geometry.honeycomb : CORNER_COUNT, CUBE_RADIUS, Corner, cubeCenter;
import geometry.lorentz : Motion, Point;

enum size_t LOOKAHEAD_PER_CANDIDATE = 8;
enum double RESCAN = 0;
enum uint MAX_SCAN_NODES_PER_FRAME = 4096;
enum size_t SCAN_WINDOW = 4096;
enum uint IN_FLIGHT_PER_WORKER = 256;
enum uint FAR_BUILDINGS_PER_WORKER = 4;
enum size_t INTEGRATION_BATCH = 4096;
enum Length FOCUS_REACH = Length(0.75f);
enum double NEAR_REFRESH_TRAVEL = 0.25;
enum uint NEAR_BANDS = 3;
enum uint URGENT_BANDS = 2;
immutable float[NEAR_BANDS] NEAR_BAND_RADII = [1.5f, 3.0f, 4.5f];

enum ScanEnd : ubyte {
    finished,
    waitingOnBuilding,
    interrupted,
}

enum ScanProgress : ubyte {
    through,
    stopped,
}

enum Urgency : ubyte {
    normal,
    urgent,
}

enum Pacing : ubyte {
    budgeted,
    unbudgeted,
}

struct ScanOutcome {
    float nearestOutOfRange;
    float nearestDropped;
    ScanEnd end;
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
        float fresh = float.infinity;
        if (outcome.nearestOutOfRange != float.infinity) {
            fresh = acoshf(outcome.nearestOutOfRange) - range;
        }
        float dropped = float.infinity;
        if (outcome.nearestDropped != float.infinity) {
            dropped = acoshf(outcome.nearestDropped) - keepRange;
        }
        return lowerOf(fresh, dropped);
    }
}

struct PlannedChunk {
    ChunkSlot chunk;
    GenKind kind;
    Urgency urgency;
}

struct PlannedParams {
    ChunkParams params;
    GeneratedVoxels generated;
    Occupancy predicted;
    Readiness state;
}

struct ParamsJob {
    Graph* graph;
    const(PlannedChunk)* chunks;
    PlannedParams* made;
}

void computeParams(void* context, size_t index, uint worker) {
    ParamsJob* job = cast(ParamsJob*) context;
    GraphView* view = &job.graph.threadViews[worker];
    ChunkSlot chunk = job.chunks[index].chunk;
    PlannedParams* made = &job.made[index];
    made.state = Readiness.pending;
    if (view.chunkStructureAt(chunk.slot).isKnown) {
        made.params = ChunkParams.make(*view, chunk.slot, chunk.corner);
        if (view.isBlocked) {
            view.forget();
        } else {
            made.state = Readiness.ready;
            made.predicted = made.params.predictOccupancy();
            if (job.chunks[index].kind == GenKind.fresh) {
                job.graph.chunks.existing(chunk).predicted = made.predicted;
                if (made.params.isUniformlyFilled(made.predicted)) {
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
        if (state == ChunkState.fresh) {
            float product = range.camera.coshDistance(nearbyNode.transform * corner.cubeCenter);
            if (!(product > range.threshold)) {
                found.freshInRange |= 1u << index;
            } else if (product < found.nearestOutOfRange) {
                found.nearestOutOfRange = product;
            }
        } else if (state == ChunkState.dropped) {
            float product = range.camera.coshDistance(nearbyNode.transform * corner.cubeCenter);
            if (!(product > range.keepThreshold)) {
                found.droppedInRange |= 1u << index;
            } else if (product < found.nearestDropped) {
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

struct Streamer {
    Array!GenRequest requests;
    Array!GenRequest urgentRequests;
    Array!uint buildingSlots;
    Array!uint urgentBuildingSlots;
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
    size_t nearUrgent;
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
                if (result.state == Readiness.pending) {
                    result.params = ChunkParams.make(graph.view, plan.chunk.slot, plan.chunk.corner);
                    result.predicted = result.params.predictOccupancy();
                    if (plan.kind == GenKind.fresh) {
                        graph.chunks.existing(plan.chunk).predicted = result.predicted;
                        if (result.params.isUniformlyFilled(result.predicted)) {
                            result.generated = result.params.generateVoxels();
                        }
                    }
                }
                if (plan.kind == GenKind.restoring || !result.params.isUniformlyFilled(result.predicted)) {
                    GenRequest request = GenRequest(result.params, plan.chunk, plan.kind);
                    if (plan.urgency == Urgency.urgent) {
                        urgentRequests.append(request);
                    } else {
                        requests.append(request);
                    }
                } else {
                    integrator.arrivals.append(GenResult(result.generated, plan.chunk, GenKind.fresh));
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

    void requestAround(ref Graph graph, Position focus) {
        around.clear();
        visitCells(graph, focus, FOCUS_REACH, around);
        foreach (missing; around.missing.slice()) {
            graph.ensureNeighborSlot(missing.slot, missing.side);
        }
        foreach (chunk; around.chunks.slice()) {
            ChunkState state = graph.chunks.at(chunk).state;
            if (state == ChunkState.dropped) {
                plan(graph, chunk, GenKind.restoring, Urgency.urgent);
            } else if (state == ChunkState.fresh && isBuildingReady(graph, chunk.slot)) {
                plan(graph, chunk, GenKind.fresh, Urgency.urgent);
            } else if (state == ChunkState.fresh) {
                scheduleBuilding(graph, chunk.slot, Urgency.urgent);
            }
        }
    }

    void drive(ref Graph graph, const(NearbyNode)[] nearby, Position focus, Motion!float cameraLocal, float distance, uint nearbyVersion, Pacing pacing, double deadline) {
        if (rescanAt.length < graph.slotCount) {
            rescanAt.resize(graph.slotCount);
        }
        integrate(graph, deadline);
        foreach (chunk; graph.chunks.restores.slice()) {
            planned.append(PlannedChunk(chunk, GenKind.restoring, Urgency.normal));
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
        uint budget = requestBudget(pacing);
        rescanBuilt(graph, nearby, range, budget);
        if (scanNearCamera(graph, nearby, range, budget, deadline) == ScanProgress.through) {
            scanCursor = cast(uint) scan(graph, nearby, range, budget, deadline);
        }
        planParams(graph);
        submitRequests(graph);
    }

    void rescanBuilt(ref Graph graph, const(NearbyNode)[] nearby, ScanRange range, uint budget) {
        size_t kept = 0;
        foreach (index; waiting.slice()) {
            if (!finishWaiting(graph, nearby[index], range, budget)) {
                waiting.ptr[kept] = index;
                kept += 1;
            }
        }
        waiting.length = kept;
    }

    bool finishWaiting(ref Graph graph, NearbyNode nearbyNode, ScanRange range, uint budget) {
        if (graph.structures.at(nearbyNode.slot).isBuildingQueued) {
            return false;
        } else {
            ScanOutcome outcome = scanNode(graph, nearbyNode.slot, scanFacts(graph, nearbyNode, range), budget, Urgency.normal);
            if (outcome.end == ScanEnd.finished) {
                rescanAt.ptr[nearbyNode.slot] = travel + range.margin(outcome);
                return true;
            } else {
                return false;
            }
        }
    }

    uint requestBudget(Pacing pacing) const {
        if (pacing == Pacing.unbudgeted) {
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

    void collectUnstructured(ref const Graph graph, const(NearbyNode)[] nearby, ref Array!uint into, size_t limit) const {
        size_t looked = 0;
        size_t near = nearHead;
        while (near < nearCamera.length && looked < limit * LOOKAHEAD_PER_CANDIDATE && into.length < limit) {
            collectIfUnstructured(graph, nearby[nearCamera.ptr[near]].slot, into);
            near += 1;
            looked += 1;
        }
        size_t index = scanCursor;
        while (index < nearby.length && looked < limit * LOOKAHEAD_PER_CANDIDATE && into.length < limit) {
            collectIfUnstructured(graph, nearby[index].slot, into);
            index += 1;
            looked += 1;
        }
    }

    void collectIfUnstructured(ref const Graph graph, uint slot, ref Array!uint into) const {
        if (isScanPending(slot) && !graph.isFinished(slot) && !graph.structures.at(slot).isCovered) {
            into.append(slot);
        }
    }

    size_t scan(ref Graph graph, const(NearbyNode)[] nearby, ScanRange range, uint budget, double deadline) {
        uint scanned = 0;
        size_t index = scanCursor;
        if (nowMilliseconds() >= deadline) {
            return index;
        }
        while (index < nearby.length) {
            size_t first = index;
            size_t end = lowerOf(first + SCAN_WINDOW, nearby.length);
            facts.resize(end - first);
            ScanJob context = ScanJob(&graph, &this, nearby.ptr + first, facts.ptr, range);
            ParallelJob job = ParallelJob(&gatherScanFacts, &context, double.infinity, end - first);
            pool.run(&job);
            while (index < end) {
                if (isScanPending(nearby[index].slot)) {
                    scanned += 1;
                    if (scanAt(graph, nearby, index, facts.ptr[index - first], range, budget, Urgency.normal) == ScanEnd.interrupted) {
                        return index;
                    }
                    index += 1;
                    if (scanned >= MAX_SCAN_NODES_PER_FRAME || nowMilliseconds() >= deadline) {
                        return index;
                    }
                } else {
                    index += 1;
                }
            }
        }
        return index;
    }

    ScanEnd scanAt(ref Graph graph, const(NearbyNode)[] nearby, size_t index, ScanFacts found, ScanRange range, uint budget, Urgency urgency) {
        uint slot = nearby[index].slot;
        ScanOutcome outcome = scanNode(graph, slot, found, budget, urgency);
        if (outcome.end == ScanEnd.waitingOnBuilding) {
            rescanAt.ptr[slot] = RESCAN;
            waiting.append(cast(uint) index);
        } else if (outcome.end == ScanEnd.finished) {
            rescanAt.ptr[slot] = travel + range.margin(outcome);
        }
        return outcome.end;
    }

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
            if (band + 1 == URGENT_BANDS) {
                nearUrgent = nearCamera.length;
            }
        }
        nearHead = 0;
        nearTravel = travel;
    }

    ScanProgress scanNearCamera(ref Graph graph, const(NearbyNode)[] nearby, ScanRange range, uint budget, double deadline) {
        if (nowMilliseconds() >= deadline) {
            return ScanProgress.stopped;
        }
        while (nearHead < nearCamera.length) {
            uint index = nearCamera.ptr[nearHead];
            if (isScanPending(nearby[index].slot)) {
                Urgency urgency = Urgency.normal;
                uint allowed = budget;
                if (nearHead < nearUrgent) {
                    urgency = Urgency.urgent;
                    allowed = uint.max;
                }
                if (scanAt(graph, nearby, index, scanFacts(graph, nearby[index], range), range, allowed, urgency) == ScanEnd.interrupted) {
                    return ScanProgress.stopped;
                }
                nearHead += 1;
                if (nowMilliseconds() >= deadline) {
                    return ScanProgress.stopped;
                }
            } else {
                nearHead += 1;
            }
        }
        return ScanProgress.through;
    }

    ScanOutcome scanNode(ref Graph graph, uint slot, ScanFacts found, uint budget, Urgency urgency) {
        ScanOutcome outcome = ScanOutcome(found.nearestOutOfRange, found.nearestDropped, ScanEnd.finished);
        uint wanted = found.freshInRange | found.droppedInRange;
        foreach (index; 0 .. CORNER_COUNT) {
            uint bit = 1u << index;
            if ((wanted & bit) != 0) {
                ChunkSlot chunk = ChunkSlot(slot, cast(Corner) index);
                if (requests.length + planned.length >= budget) {
                    outcome.end = ScanEnd.interrupted;
                    return outcome;
                } else if ((found.droppedInRange & bit) != 0) {
                    plan(graph, chunk, GenKind.restoring, urgency);
                } else if (isBuildingReady(graph, slot)) {
                    plan(graph, chunk, GenKind.fresh, urgency);
                } else {
                    scheduleBuilding(graph, slot, urgency);
                    outcome.end = ScanEnd.waitingOnBuilding;
                }
            }
        }
        return outcome;
    }

    void plan(ref Graph graph, ChunkSlot slot, GenKind kind, Urgency urgency) {
        graph.chunks.writable(slot).state = ChunkState.generating;
        planned.append(PlannedChunk(slot, kind, urgency));
    }

    void scheduleBuilding(ref Graph graph, uint slot, Urgency urgency) {
        NodeStructure* node = &graph.structures.at(slot);
        if (graph.structures.buildingAt(slot) is null && !node.isBuildingQueued) {
            node.marks.set(NodeMark.buildingQueued);
            if (urgency == Urgency.urgent) {
                node.marks.set(NodeMark.buildingUrgent);
                urgentBuildingSlots.append(slot);
            } else {
                node.marks.clear(NodeMark.buildingUrgent);
                buildingSlots.append(slot);
            }
        } else if (urgency == Urgency.urgent && node.isBuildingQueued && !node.isBuildingUrgent) {
            node.marks.set(NodeMark.buildingUrgent);
            size_t index = 0;
            while (index < buildingSlots.length && buildingSlots.ptr[index] != slot) {
                index += 1;
            }
            if (index < buildingSlots.length) {
                foreach (moved; index + 1 .. buildingSlots.length) {
                    buildingSlots.ptr[moved - 1] = buildingSlots.ptr[moved];
                }
                buildingSlots.length -= 1;
                urgentBuildingSlots.append(slot);
            }
        }
    }

    void submitRequests(ref Graph graph) {
        size_t generations = pushedPrefix(queues.urgent, urgentRequests, QUEUE_CAPACITY - inFlight);
        generations += pushedPrefix(queues.generations, requests, QUEUE_CAPACITY - inFlight - generations);
        size_t buildings = submitBuildings(graph, urgentBuildingSlots, queues.urgentBuildings, QUEUE_CAPACITY - buildingsInFlight);
        size_t farLimit = workerCount * FAR_BUILDINGS_PER_WORKER;
        if (buildingsInFlight + buildings < farLimit) {
            buildings += submitBuildings(graph, buildingSlots, queues.buildings, farLimit - buildingsInFlight - buildings);
        }
        inFlight += cast(uint) generations;
        buildingsInFlight += cast(uint) buildings;
        if (generations > 0 || buildings > 0) {
            pool.signal();
        }
    }

    size_t submitBuildings(ref Graph graph, ref Array!uint slots, ref ConcurrentQueue!BuildingRequest queue, size_t room) {
        size_t pushed = 0;
        while (pushed < slots.length && pushed < room) {
            uint slot = slots.ptr[pushed];
            if (!queue.push(BuildingRequest(graph.planBuilding(slot), slot))) {
                assert(false);
            }
            pushed += 1;
        }
        foreach (index; pushed .. slots.length) {
            slots.ptr[index - pushed] = slots.ptr[index];
        }
        slots.length -= pushed;
        return pushed;
    }

    void forget(const(Unloaded)[] unloaded) {
        foreach (entry; unloaded) {
            if (entry.slot < rescanAt.length) {
                rescanAt.ptr[entry.slot] = RESCAN;
            }
        }
    }

    bool isIdle() const {
        return inFlight == 0 && buildingsInFlight == 0 && requests.length == 0 && urgentRequests.length == 0 && buildingSlots.length == 0 && urgentBuildingSlots.length == 0;
    }

    void settle(ref Graph graph) {
        while (!isIdle()) {
            submitRequests(graph);
            uint seen = atomicLoad(queues.completed);
            if (integrate(graph, NO_DEADLINE) == 0) {
                queues.await(seen);
            }
        }
    }

    uint integrate(ref Graph graph, double deadline) {
        uint integrated = 0;
        BuildingResult built;
        while (queues.built.pop(built)) {
            integrateBuilding(graph, built);
            integrated += 1;
        }
        GenResult result;
        while (nowMilliseconds() < deadline && integrator.arrivals.length < INTEGRATION_BATCH && queues.generated.pop(result)) {
            inFlight -= 1;
            integrated += 1;
            integrator.arrivals.append(result);
        }
        integrator.run(graph, executor());
        return integrated;
    }

    void integrateBuilding(ref Graph graph, BuildingResult built) {
        buildingsInFlight -= 1;
        graph.structures.at(built.slot).marks.clear(NodeMark.buildingQueued);
        graph.structures.at(built.slot).marks.clear(NodeMark.buildingUrgent);
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
        buildingSlots.release();
        urgentBuildingSlots.release();
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
