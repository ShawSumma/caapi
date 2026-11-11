module client.streaming;

import core.atomic : atomicLoad;
import core.stdc.math : acoshf, coshf;
import core.stdc.stdlib : calloc, free;
import base.array : Array;
import base.clock : Deadline, nowMilliseconds;
import base.flags : Readiness;
import base.heap : rekeyed;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : lowerOf;
import base.parallel : Executor, MAIN_WORKER, ParallelJob, TaskSource, WorkerPool;
import base.units : Length;
import client.arrivals : Integrator;
import client.tasks : BuildingRequest, BuildingResult, GenKind, GenRequest, GenResult, TaskQueues, takeTask, workerThreadCount;
import common.character.features : RequiredChunks, visitCells;
import common.eviction : KEEP_RADIUS, Unloaded;
import common.graph : Graph, NodeContent;
import common.node : Chunk, ChunkSlot, ChunkState, Materials, Occupancy, Voxels;
import common.position : Position;
import common.traversal : NearbyNode, NearbyScratch, ensureDepthAt;
import common.view : GraphView;
import common.worldgen.generation : ChunkParams, ChunkStructure, GeneratedVoxels;
import common.worldgen.horospheres : probeBuried, probeClear;
import common.worldgen.store : NodeMark, NodeStructure;
import geometry.honeycomb : CORNER_COUNT, CUBE_RADIUS, Corner, NODE_RADIUS, cubeCenter;
import geometry.lorentz : Motion, Point;
import plugins.api.api : Material;

enum size_t LOOKAHEAD_PER_CANDIDATE = 8;
version (WebAssembly) {
    enum Maybe!uint MOST_SCANNED_PER_FRAME = Maybe!uint.init;
    enum size_t SCAN_WINDOW = 256;
} else {
    enum Maybe!uint MOST_SCANNED_PER_FRAME = Maybe!uint.of(4096);
    enum size_t SCAN_WINDOW = 1024;
}
enum uint IN_FLIGHT_PER_WORKER = 256;
enum uint FAR_BUILDINGS_PER_WORKER = 4;
enum size_t INTEGRATION_BATCH = 4096;
enum Length FOCUS_REACH = Length(0.75f);
enum double NEAR_REFRESH_TRAVEL = 0.25;
enum uint NEAR_BANDS = 3;
enum uint URGENT_BANDS = 2;
enum float NEAREST_KEY = 1.0f;
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

enum Rescan : ubyte {
    onceTraveled,
    never,
}

struct NextScan {
    double travel = 0;
    Rescan rescan;
}

enum NextScan RESCAN_NOW = NextScan.init;

struct ScanOutcome {
    Maybe!float nearestOutOfRange;
    Maybe!float nearestDropped;
    ScanEnd end;
    float range = 0;
    float keepRange = 0;
}

Maybe!float marginPast(Maybe!float coshNearest, float reach) {
    if (coshNearest.exists) {
        return Maybe!float.of(acoshf(coshNearest.value) - reach);
    } else {
        return Maybe!float.init;
    }
}

Maybe!float nearerOf(Maybe!float a, Maybe!float b) {
    if (!a.exists) {
        return b;
    } else if (!b.exists) {
        return a;
    } else {
        return Maybe!float.of(lowerOf(a.value, b.value));
    }
}

struct ScanRange {
    Point!float camera;
    float range;
    float keepRange;
    float deepRange;

    static ScanRange make(Point!float camera, float range, float keepRange, float deepRange) {
        return ScanRange(camera, range, keepRange, deepRange);
    }

    float rangeFor(NodeContent content) const {
        if (content == NodeContent.deep) {
            return deepRange;
        } else {
            return range;
        }
    }

    NextScan nextAfter(double travel, ScanOutcome outcome) const {
        Maybe!float margin = nearerOf(marginPast(outcome.nearestOutOfRange, outcome.range), marginPast(outcome.nearestDropped, outcome.keepRange));
        if (margin.exists) {
            return NextScan(travel + margin.value, Rescan.onceTraveled);
        } else {
            return NextScan(0, Rescan.never);
        }
    }
}

struct PlannedChunk {
    ChunkSlot chunk;
    float key;
    GenKind kind;
}

struct PendingBuilding {
    uint slot;
    float key;
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
    ChunkStructure structure = view.ensureChunkStructure(chunk.slot);
    if (structure.isKnown) {
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

enum Exposure : ubyte {
    mixed,
    buried,
    clear,
}

struct ScanFacts {
    uint freshInRange;
    uint droppedInRange;
    Maybe!float nearestOutOfRange;
    Maybe!float nearestDropped;
    float range = 0;
    float keepRange = 0;
    Exposure exposure;
}

Exposure exposureOf(Graph* graph, uint slot, uint worker) {
    NodeContent content = graph.nodeAt(slot).content;
    if (content == NodeContent.deep) {
        return Exposure.mixed;
    } else {
        GraphView* view = &graph.threadViews[worker];
        bool buried = (content == NodeContent.unknown || content == NodeContent.shallow) && (*view).probeBuried(slot);
        bool clear = !buried && (*view).probeClear(slot);
        if (view.isBlocked) {
            view.forget();
            return Exposure.mixed;
        } else if (buried) {
            return Exposure.buried;
        } else if (clear) {
            return Exposure.clear;
        } else {
            return Exposure.mixed;
        }
    }
}

bool probeOpenAir(ref Graph graph, uint slot) {
    bool needsBuilding = graph.ensureStructureAt(slot);
    return !needsBuilding;
}

ScanFacts scanFacts(ref const Graph graph, NearbyNode nearbyNode, ScanRange range) {
    ScanFacts found;
    found.range = range.rangeFor(graph.nodeAt(nearbyNode.slot).content);
    found.keepRange = lowerOf(range.keepRange, found.range);
    float threshold = coshf(found.range);
    float keepThreshold = coshf(found.keepRange);
    foreach (index; 0 .. CORNER_COUNT) {
        Corner corner = cast(Corner) index;
        ChunkState state = graph.chunks.at(ChunkSlot(nearbyNode.slot, corner)).state;
        if (state == ChunkState.fresh) {
            float product = range.camera.coshDistance(nearbyNode.transform * corner.cubeCenter);
            if (!(product > threshold)) {
                found.freshInRange |= 1u << index;
            } else {
                found.nearestOutOfRange = nearerOf(found.nearestOutOfRange, Maybe!float.of(product));
            }
        } else if (state == ChunkState.dropped) {
            float product = range.camera.coshDistance(nearbyNode.transform * corner.cubeCenter);
            if (!(product > keepThreshold)) {
                found.droppedInRange |= 1u << index;
            } else {
                found.nearestDropped = nearerOf(found.nearestDropped, Maybe!float.of(product));
            }
        }
    }
    return found;
}

struct ScanJob {
    Graph* graph;
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
        if (job.facts[item].freshInRange != 0) {
            job.facts[item].exposure = exposureOf(job.graph, nearbyNode.slot, worker);
        }
    }
}

struct ExposureJob {
    Graph* graph;
    const(Streamer)* streamer;
    const(NearbyNode)* nodes;
    const(uint)* indices;
    Exposure* exposures;
    ScanRange range;
}

void judgeExposure(void* context, size_t item, uint worker) {
    ExposureJob* job = cast(ExposureJob*) context;
    NearbyNode nearbyNode = job.nodes[job.indices[item]];
    job.exposures[item] = Exposure.mixed;
    if (job.streamer.isScanPending(nearbyNode.slot) && scanFacts(*job.graph, nearbyNode, job.range).freshInRange != 0) {
        job.exposures[item] = exposureOf(job.graph, nearbyNode.slot, worker);
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
    Array!PendingBuilding buildingSlots;
    Array!PendingBuilding urgentBuildingSlots;
    Array!PlannedChunk planned;
    Array!PlannedParams made;
    Array!ScanFacts facts;
    Array!NextScan rescanAt;
    Array!uint waiting;
    Array!uint nearCamera;
    Array!Exposure exposures;
    RequiredChunks around;
    Integrator integrator;
    TaskQueues* queues;
    WorkerPool* pool;
    NearBands* bands;
    ScanRange lastRange;
    double travel = 0;
    double nearTravel = 0;
    double keyedTravel = 0;
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
        version (WebAssembly) {
            streamer.workerCount = 1;
            streamer.pool = WorkerPool.make(0, TaskSource(&takeTask, streamer.queues));
        } else {
            import core.sys.posix.unistd : _SC_NPROCESSORS_ONLN, sysconf;

            streamer.workerCount = workerThreadCount(sysconf(_SC_NPROCESSORS_ONLN));
            streamer.pool = WorkerPool.make(streamer.workerCount, TaskSource(&takeTask, streamer.queues));
        }
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
            ParallelJob job = ParallelJob(&computeParams, &context, Deadline.init,planned.length);
            pool.run(&job);
            graph.threadViews.finish(graph);
            uint pushed = 0;
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
                    queues.generations.push(plan.key, GenRequest(result.params, plan.chunk, plan.kind));
                    pushed += 1;
                } else {
                    integrator.arrivals.append(GenResult(result.generated, plan.chunk, GenKind.fresh));
                }
            }
            planned.clear();
            inFlight += pushed;
            if (pushed > 0) {
                pool.signal();
            }
            integrator.run(graph, executor());
        }
    }

    void runParallel(ParallelJob* job) {
        pool.run(job);
    }

    void runTasksUntil(double deadline) {
        bool took = true;
        double now = nowMilliseconds();
        while (took && now < deadline) {
            took = takeTask(queues, MAIN_WORKER);
            now = nowMilliseconds();
        }
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
                plan(graph, chunk, GenKind.restoring, NEAREST_KEY);
            } else if (state == ChunkState.fresh) {
                bool ready = probeBuildingReady(graph, chunk.slot);
                if (ready) {
                    plan(graph, chunk, GenKind.fresh, NEAREST_KEY);
                } else {
                    scheduleBuilding(graph, chunk.slot, Urgency.urgent, NEAREST_KEY);
                }
            }
        }
    }

    void drive(ref Graph graph, ref const NearbyScratch set, Position focus, Motion!float cameraLocal, float distance, float deepDistance, uint nearbyVersion, Pacing pacing, Deadline deadline) {
        const(NearbyNode)[] nearby = set.nodes.slice();
        if (rescanAt.length < graph.slotCount) {
            rescanAt.resize(graph.slotCount);
        }
        integrate(graph, deadline);
        foreach (chunk; graph.chunks.restores.slice()) {
            planned.append(PlannedChunk(chunk, NEAREST_KEY, GenKind.restoring));
        }
        graph.chunks.restores.clear();
        ScanRange range = ScanRange.make(cameraLocal * Point!float.origin(), distance + CUBE_RADIUS, KEEP_RADIUS + CUBE_RADIUS, lowerOf(distance, deepDistance) + CUBE_RADIUS);
        lastRange = range;
        if (scanVersion != nearbyVersion) {
            scanVersion = nearbyVersion;
            scanCursor = 0;
            waiting.clear();
            findNearCamera(nearby, range.camera);
            rekeyWork(graph, set, range);
        } else if (travel - nearTravel >= NEAR_REFRESH_TRAVEL) {
            findNearCamera(nearby, range.camera);
        }
        if (travel - keyedTravel >= NEAR_REFRESH_TRAVEL) {
            rekeyWork(graph, set, range);
        }
        requestAround(graph, focus);
        version (WebAssembly) {
            size_t plans = scanAndPlan(graph, nearby, range, pacing, deadline);
            double now = nowMilliseconds();
            while (plans > 0 && !deadline.hasPassed(now)) {
                plans = scanAndPlan(graph, nearby, range, pacing, deadline);
                now = nowMilliseconds();
            }
        } else {
            scanAndPlan(graph, nearby, range, pacing, deadline);
        }
    }

    size_t scanAndPlan(ref Graph graph, const(NearbyNode)[] nearby, ScanRange range, Pacing pacing, Deadline deadline) {
        Maybe!uint budget = requestBudget(pacing);
        rescanBuilt(graph, nearby, range, budget);
        ScanProgress progress = scanNearCamera(graph, nearby, range, budget, deadline);
        if (progress == ScanProgress.through) {
            scanCursor = cast(uint) scan(graph, nearby, range, budget, deadline);
        }
        size_t plans = planned.length;
        planParams(graph);
        integrator.run(graph, executor());
        submitRequests(graph);
        return plans;
    }

    void rescanBuilt(ref Graph graph, const(NearbyNode)[] nearby, ScanRange range, Maybe!uint budget) {
        size_t kept = 0;
        foreach (index; waiting.slice()) {
            bool finished = finishWaiting(graph, nearby[index], range, budget);
            if (!finished) {
                waiting.ptr[kept] = index;
                kept += 1;
            }
        }
        waiting.length = kept;
    }

    bool finishWaiting(ref Graph graph, NearbyNode nearbyNode, ScanRange range, Maybe!uint budget) {
        if (graph.structures.at(nearbyNode.slot).isBuildingQueued) {
            return false;
        } else {
            graph.ensureDepthAt(nearbyNode.slot);
            ScanOutcome outcome = scanNode(graph, nearbyNode, scanFacts(graph, nearbyNode, range), range, budget, Urgency.normal);
            if (outcome.end == ScanEnd.finished) {
                rescanAt.ptr[nearbyNode.slot] = range.nextAfter(travel, outcome);
                return true;
            } else {
                return false;
            }
        }
    }

    Maybe!uint requestBudget(Pacing pacing) const {
        if (pacing == Pacing.unbudgeted) {
            return Maybe!uint.init;
        } else if (inFlight < workerCount * IN_FLIGHT_PER_WORKER) {
            return Maybe!uint.of(workerCount * IN_FLIGHT_PER_WORKER - inFlight);
        } else {
            return Maybe!uint.of(0);
        }
    }

    bool isScanPending(uint slot) const {
        return slot < rescanAt.length && rescanAt.ptr[slot].rescan == Rescan.onceTraveled && rescanAt.ptr[slot].travel <= travel;
    }

    void collectUnstructured(ref const Graph graph, const(NearbyNode)[] nearby, ref Array!uint into, size_t limit) const {
        size_t looked = 0;
        size_t near = nearHead;
        while (near < nearCamera.length && looked < limit * LOOKAHEAD_PER_CANDIDATE && into.length < limit) {
            uint slot = nearby[nearCamera.ptr[near]].slot;
            if (near < nearUrgent || graph.nodeAt(slot).content != NodeContent.deep) {
                collectIfUnstructured(graph, slot, into);
            }
            near += 1;
            looked += 1;
        }
        size_t index = scanCursor;
        while (index < nearby.length && looked < limit * LOOKAHEAD_PER_CANDIDATE && into.length < limit) {
            if (graph.nodeAt(nearby[index].slot).content != NodeContent.deep && isWithinLoadReach(graph, nearby[index])) {
                collectIfUnstructured(graph, nearby[index].slot, into);
            }
            index += 1;
            looked += 1;
        }
    }

    bool isWithinLoadReach(ref const Graph graph, NearbyNode node) const {
        float reach = lastRange.rangeFor(graph.nodeAt(node.slot).content) + NODE_RADIUS;
        return !(lastRange.camera.coshDistance(node.transform * Point!float.origin()) > coshf(reach));
    }

    void collectIfUnstructured(ref const Graph graph, uint slot, ref Array!uint into) const {
        if (isScanPending(slot) && !graph.isFinished(slot) && !graph.structures.at(slot).isCovered) {
            into.append(slot);
        }
    }

    size_t scan(ref Graph graph, const(NearbyNode)[] nearby, ScanRange range, Maybe!uint budget, Deadline deadline) {
        double start = nowMilliseconds();
        if (deadline.hasPassed(start) || scanCursor >= nearby.length) {
            return scanCursor;
        } else {
            graph.threadViews.begin(graph, pool.participants());
            size_t reached = scanWindows(graph, nearby, range, budget, deadline);
            graph.threadViews.finish(graph);
            return reached;
        }
    }

    size_t scanWindows(ref Graph graph, const(NearbyNode)[] nearby, ScanRange range, Maybe!uint budget, Deadline deadline) {
        uint scanned = 0;
        size_t index = scanCursor;
        while (index < nearby.length) {
            size_t first = index;
            size_t end = lowerOf(first + SCAN_WINDOW, nearby.length);
            if (hasPendingAmong(nearby[first .. end])) {
                facts.resize(end - first);
                ScanJob context = ScanJob(&graph, &this, nearby.ptr + first, facts.ptr, range);
                ParallelJob job = ParallelJob(&gatherScanFacts, &context, Deadline.init,end - first);
                pool.run(&job);
            }
            while (index < end) {
                if (isScanPending(nearby[index].slot)) {
                    scanned += 1;
                    ScanEnd stopped = scanAt(graph, nearby, index, facts.ptr[index - first], range, budget, Urgency.normal);
                    if (stopped == ScanEnd.interrupted) {
                        return index;
                    }
                    index += 1;
                    double now = nowMilliseconds();
                    if ((MOST_SCANNED_PER_FRAME.exists && scanned >= MOST_SCANNED_PER_FRAME.value) || deadline.hasPassed(now)) {
                        return index;
                    }
                } else {
                    index += 1;
                }
            }
        }
        return index;
    }

    bool hasPendingAmong(const(NearbyNode)[] nodes) const {
        size_t index = 0;
        while (index < nodes.length && !isScanPending(nodes[index].slot)) {
            index += 1;
        }
        return index < nodes.length;
    }

    ScanEnd scanAt(ref Graph graph, const(NearbyNode)[] nearby, size_t index, ScanFacts found, ScanRange range, Maybe!uint budget, Urgency urgency) {
        uint slot = nearby[index].slot;
        ScanFacts settled = found;
        if (found.exposure == Exposure.buried) {
            graph.nodeAt(slot).content = NodeContent.deep;
            settled = scanFacts(graph, nearby[index], range);
        } else if (graph.nodeAt(slot).content == NodeContent.unknown) {
            graph.ensureDepthAt(slot);
            settled = scanFacts(graph, nearby[index], range);
        }
        ScanOutcome outcome = scanNode(graph, nearby[index], settled, range, budget, urgency);
        if (outcome.end == ScanEnd.waitingOnBuilding) {
            rescanAt.ptr[slot] = RESCAN_NOW;
            waiting.append(cast(uint) index);
        } else if (outcome.end == ScanEnd.finished) {
            rescanAt.ptr[slot] = range.nextAfter(travel, outcome);
        }
        return outcome.end;
    }

    void findNearCamera(const(NearbyNode)[] nearby, Point!float camera) {
        NearJob context = NearJob(nearby.ptr, bands, camera);
        foreach (band; 0 .. NEAR_BANDS) {
            context.thresholds[band] = coshf(NEAR_BAND_RADII[band]);
        }
        ParallelJob job = ParallelJob(&sortIntoBand, &context, Deadline.init,nearby.length);
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

    ScanProgress scanNearCamera(ref Graph graph, const(NearbyNode)[] nearby, ScanRange range, Maybe!uint budget, Deadline deadline) {
        double start = nowMilliseconds();
        if (deadline.hasPassed(start)) {
            return ScanProgress.stopped;
        }
        while (nearHead < nearCamera.length && !isScanPending(nearby[nearCamera.ptr[nearHead]].slot)) {
            nearHead += 1;
        }
        size_t first = nearHead;
        exposures.resize(nearCamera.length - first);
        if (first < nearCamera.length) {
            ExposureJob context = ExposureJob(&graph, &this, nearby.ptr, nearCamera.ptr + first, exposures.ptr, range);
            graph.threadViews.begin(graph, pool.participants());
            ParallelJob job = ParallelJob(&judgeExposure, &context, Deadline.init, nearCamera.length - first);
            pool.run(&job);
            graph.threadViews.finish(graph);
        }
        while (nearHead < nearCamera.length) {
            uint index = nearCamera.ptr[nearHead];
            if (isScanPending(nearby[index].slot)) {
                Urgency urgency = Urgency.normal;
                Maybe!uint allowed = budget;
                if (nearHead < nearUrgent) {
                    urgency = Urgency.urgent;
                    allowed = Maybe!uint.init;
                }
                ScanFacts found = scanFacts(graph, nearby[index], range);
                found.exposure = exposures.ptr[nearHead - first];
                ScanEnd scanned = scanAt(graph, nearby, index, found, range, allowed, urgency);
                if (scanned == ScanEnd.interrupted) {
                    return ScanProgress.stopped;
                }
                nearHead += 1;
                double now = nowMilliseconds();
                if (deadline.hasPassed(now)) {
                    return ScanProgress.stopped;
                }
            } else {
                nearHead += 1;
            }
        }
        return ScanProgress.through;
    }

    ScanOutcome scanNode(ref Graph graph, NearbyNode nearbyNode, ScanFacts found, ScanRange range, Maybe!uint budget, Urgency urgency) {
        ScanOutcome outcome = ScanOutcome(found.nearestOutOfRange, found.nearestDropped, ScanEnd.finished, found.range, found.keepRange);
        uint slot = nearbyNode.slot;
        uint wanted = found.freshInRange | found.droppedInRange;
        bool clear = found.exposure == Exposure.clear && found.freshInRange != 0 && probeOpenAir(graph, slot);
        foreach (index; 0 .. CORNER_COUNT) {
            uint bit = 1u << index;
            if ((wanted & bit) != 0) {
                ChunkSlot chunk = ChunkSlot(slot, cast(Corner) index);
                float key = range.camera.coshDistance(nearbyNode.transform * chunk.corner.cubeCenter);
                if (budget.exists && planned.length >= budget.value) {
                    outcome.end = ScanEnd.interrupted;
                    return outcome;
                } else if ((found.droppedInRange & bit) != 0) {
                    plan(graph, chunk, GenKind.restoring, key);
                } else if (clear) {
                    fillAir(graph, chunk);
                } else {
                    bool ready = probeBuildingReady(graph, slot);
                    if (ready) {
                        plan(graph, chunk, GenKind.fresh, key);
                    } else {
                        scheduleBuilding(graph, slot, urgency, range.camera.coshDistance(nearbyNode.transform * Point!float.origin()));
                        outcome.end = ScanEnd.waitingOnBuilding;
                    }
                }
            }
        }
        return outcome;
    }

    void plan(ref Graph graph, ChunkSlot slot, GenKind kind, float key) {
        graph.chunks.writable(slot).state = ChunkState.generating;
        planned.append(PlannedChunk(slot, key, kind));
    }

    void fillAir(ref Graph graph, ChunkSlot slot) {
        Chunk* chunk = graph.chunks.writable(slot);
        chunk.state = ChunkState.generating;
        chunk.predicted = Occupancy.empty;
        integrator.arrivals.append(GenResult(GeneratedVoxels(Voxels.filled(Material.none), Materials.resolved), slot, GenKind.fresh));
    }

    void scheduleBuilding(ref Graph graph, uint slot, Urgency urgency, float key) {
        NodeStructure* node = &graph.structures.at(slot);
        if (graph.structures.buildingAt(slot) is null && !node.isBuildingQueued) {
            node.marks.set(NodeMark.buildingQueued);
            if (urgency == Urgency.urgent) {
                node.marks.set(NodeMark.buildingUrgent);
                urgentBuildingSlots.append(PendingBuilding(slot, key));
            } else {
                node.marks.clear(NodeMark.buildingUrgent);
                buildingSlots.append(PendingBuilding(slot, key));
            }
        } else if (urgency == Urgency.urgent && node.isBuildingQueued && !node.isBuildingUrgent) {
            node.marks.set(NodeMark.buildingUrgent);
            size_t index = 0;
            while (index < buildingSlots.length && buildingSlots.ptr[index].slot != slot) {
                index += 1;
            }
            if (index < buildingSlots.length) {
                foreach (moved; index + 1 .. buildingSlots.length) {
                    buildingSlots.ptr[moved - 1] = buildingSlots.ptr[moved];
                }
                buildingSlots.length -= 1;
                urgentBuildingSlots.append(PendingBuilding(slot, key));
            }
        }
    }

    void submitRequests(ref Graph graph) {
        size_t buildings = submitBuildings(graph, urgentBuildingSlots, urgentBuildingSlots.length);
        size_t farLimit = workerCount * FAR_BUILDINGS_PER_WORKER;
        if (buildingsInFlight + buildings < farLimit) {
            buildings += submitBuildings(graph, buildingSlots, farLimit - buildingsInFlight - buildings);
        }
        buildingsInFlight += cast(uint) buildings;
        if (buildings > 0) {
            pool.signal();
        }
    }

    size_t submitBuildings(ref Graph graph, ref Array!PendingBuilding slots, size_t room) {
        size_t pushed = 0;
        while (pushed < slots.length && pushed < room) {
            PendingBuilding pending = slots.ptr[pushed];
            queues.buildings.push(pending.key, BuildingRequest(graph.planBuilding(pending.slot), pending.slot));
            pushed += 1;
        }
        foreach (index; pushed .. slots.length) {
            slots.ptr[index - pushed] = slots.ptr[index];
        }
        slots.length -= pushed;
        return pushed;
    }

    void rekeyWork(ref Graph graph, ref const NearbyScratch set, ScanRange range) {
        Maybe!float chunkKey(ref GenRequest request) {
            MaybeIndex!uint index = set.indexOf(request.chunk.slot);
            float product = float.infinity;
            if (index.exists) {
                product = range.camera.coshDistance(set.nodes.ptr[index.value].transform * request.chunk.corner.cubeCenter);
            }
            if (request.kind == GenKind.restoring) {
                return Maybe!float.of(product);
            } else if (product > coshf(range.rangeFor(graph.nodeAt(request.chunk.slot).content))) {
                graph.chunks.existing(request.chunk).state = ChunkState.fresh;
                inFlight -= 1;
                rescanAt.ptr[request.chunk.slot] = RESCAN_NOW;
                return Maybe!float.init;
            } else {
                return Maybe!float.of(product);
            }
        }
        Maybe!float buildingKey(ref BuildingRequest request) {
            MaybeIndex!uint index = set.indexOf(request.slot);
            float product = float.infinity;
            if (index.exists) {
                product = range.camera.coshDistance(set.nodes.ptr[index.value].transform * Point!float.origin());
            }
            if (product > coshf(range.rangeFor(graph.nodeAt(request.slot).content) + NODE_RADIUS)) {
                request.plan.release();
                graph.structures.at(request.slot).marks.clear(NodeMark.buildingQueued);
                graph.structures.at(request.slot).marks.clear(NodeMark.buildingUrgent);
                buildingsInFlight -= 1;
                rescanAt.ptr[request.slot] = RESCAN_NOW;
                return Maybe!float.init;
            } else {
                return Maybe!float.of(product);
            }
        }
        rekeyed!chunkKey(queues.generations);
        rekeyed!buildingKey(queues.buildings);
        keyedTravel = travel;
    }

    void forget(const(Unloaded)[] unloaded) {
        foreach (entry; unloaded) {
            if (entry.slot < rescanAt.length) {
                rescanAt.ptr[entry.slot] = RESCAN_NOW;
            }
        }
    }

    bool isIdle() const {
        return inFlight == 0 && buildingsInFlight == 0 && buildingSlots.length == 0 && urgentBuildingSlots.length == 0;
    }

    void settle(ref Graph graph) {
        while (!isIdle()) {
            submitRequests(graph);
            uint seen = atomicLoad(queues.completed);
            uint integrated = integrate(graph, Deadline.init);
            if (integrated == 0) {
                queues.await(seen);
            }
        }
    }

    uint integrate(ref Graph graph, Deadline deadline) {
        uint integrated = 0;
        BuildingResult built;
        bool popped = queues.built.pop(built);
        while (popped) {
            integrateBuilding(graph, built);
            integrated += 1;
            popped = queues.built.pop(built);
        }
        GenResult result;
        popped = true;
        double now = nowMilliseconds();
        while (popped && !deadline.hasPassed(now) && integrator.arrivals.length < INTEGRATION_BATCH) {
            popped = queues.generated.pop(result);
            if (popped) {
                inFlight -= 1;
                integrated += 1;
                integrator.arrivals.append(result);
            }
            now = nowMilliseconds();
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
            rescanAt.ptr[built.slot] = RESCAN_NOW;
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
        planned.release();
        made.release();
        facts.release();
        nearCamera.release();
        exposures.release();
        around.release();
        rescanAt.release();
        waiting.release();
    }
}

bool probeBuildingReady(ref Graph graph, uint slot) {
    bool needsBuilding = graph.ensureStructureAt(slot);
    return !needsBuilding || graph.structures.buildingAt(slot) !is null;
}
