module client.streaming;

import core.stdc.math : acoshf, coshf;
import core.stdc.stdlib : calloc, free;
import core.sys.posix.pthread : pthread_cond_broadcast, pthread_cond_destroy, pthread_cond_init, pthread_cond_signal, pthread_cond_t, pthread_cond_wait, pthread_create, pthread_join, pthread_mutex_destroy, pthread_mutex_init, pthread_mutex_lock, pthread_mutex_t, pthread_mutex_unlock, pthread_t;
import core.sys.posix.unistd : _SC_NPROCESSORS_ONLN, sysconf;
import common.array : Array;
import common.clock : nowMilliseconds;
import common.coords : CHUNK_DIRECTIONS, ChunkDirection, CoordSign;
import common.dodeca : CHUNK_BOUNDING_SPHERE_RADIUS, VERTEX_COUNT, Vertex, adjacentVertices, canonicalSides, chunkBoundingSphereCenter;
import common.eviction : KEEP_RADIUS, Unloaded;
import common.graph : Graph, NO_SLOT, Node;
import common.math : MIsometry, MPoint;
import common.neighbors : chunkNeighborSlot, isPredictionContradicted, touchChunksAround;
import common.node : Chunk, ChunkId, ChunkSlot, ChunkState, Occupancy;
import common.parallel : Executor, ParallelJob;
import common.traversal : NO_DEADLINE, NearbyNode;
import common.worldgen.building : Building, BuildingPlan;
import common.worldgen.generation : ChunkParams, GeneratedVoxels;

enum uint RESERVED_CORES = 2;
enum uint MAIN_WORKER = 0;
enum double RESCAN = 0;
enum uint MAX_SCAN_NODES_PER_FRAME = 4096;
enum size_t SKIPPED_PER_CLOCK_CHECK = 1024;
enum uint IN_FLIGHT_PER_WORKER = 256;
enum double WORLDGEN_BUDGET_MILLISECONDS = 6.0;

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

struct GenQueue {
    pthread_mutex_t mutex;
    pthread_cond_t workAvailable;
    pthread_cond_t resultsReady;
    pthread_cond_t jobFinished;
    Array!GenRequest pending;
    Array!GenResult done;
    Array!BuildingRequest pendingBuildings;
    Array!BuildingResult doneBuildings;
    ParallelJob* job;
    size_t pendingHead;
    size_t pendingBuildingHead;
    bool isStopping;

    bool isJobOpen() const {
        return job !is null && job.claimed < job.count;
    }

    bool hasPendingBuilding() const {
        return pendingBuildingHead < pendingBuildings.length;
    }

    bool hasWork() const {
        return isJobOpen() || hasPendingBuilding() || pendingHead < pending.length;
    }

    bool hasResults() const {
        return done.length > 0 || doneBuildings.length > 0;
    }

    void waitForWork() {
        while (!hasWork() && !isStopping) {
            pthread_cond_wait(&workAvailable, &mutex);
        }
    }

    void serve(uint worker) {
        waitForWork();
        while (hasWork()) {
            if (isJobOpen()) {
                runClaimed(worker);
            } else if (hasPendingBuilding()) {
                buildNext();
            } else {
                generateNext();
            }
            waitForWork();
        }
    }

    void runClaimed(uint worker) {
        ParallelJob* claimedJob = job;
        size_t index = claimedJob.claimed;
        claimedJob.claimed += 1;
        pthread_mutex_unlock(&mutex);
        claimedJob.run(claimedJob.context, index, worker);
        bool isLate = nowMilliseconds() >= claimedJob.deadline;
        pthread_mutex_lock(&mutex);
        if (isLate && claimedJob.count > claimedJob.claimed) {
            claimedJob.count = claimedJob.claimed;
        }
        claimedJob.finished += 1;
        if (claimedJob.finished == claimedJob.count) {
            pthread_cond_signal(&jobFinished);
        }
    }

    void generateNext() {
        GenRequest request = pending.ptr[pendingHead];
        pendingHead += 1;
        if (pendingHead >= pending.length) {
            pending.clear();
            pendingHead = 0;
        }
        pthread_mutex_unlock(&mutex);
        GeneratedVoxels generated = request.params.generateVoxels();
        pthread_mutex_lock(&mutex);
        done.append(GenResult(generated, request.chunk, request.isRestoring));
        pthread_cond_signal(&resultsReady);
    }

    void buildNext() {
        BuildingRequest request = pendingBuildings.ptr[pendingBuildingHead];
        pendingBuildingHead += 1;
        if (pendingBuildingHead >= pendingBuildings.length) {
            pendingBuildings.clear();
            pendingBuildingHead = 0;
        }
        pthread_mutex_unlock(&mutex);
        Building building = Building.make(request.plan);
        request.plan.release();
        pthread_mutex_lock(&mutex);
        doneBuildings.append(BuildingResult(building, request.slot));
        pthread_cond_signal(&resultsReady);
    }
}

struct WorkerStart {
    GenQueue* queue;
    uint index;
}

extern (C) void* workerMain(void* argument) {
    WorkerStart* start = cast(WorkerStart*) argument;
    pthread_mutex_lock(&start.queue.mutex);
    start.queue.serve(start.index);
    pthread_mutex_unlock(&start.queue.mutex);
    return null;
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

struct Streamer {
    Array!pthread_t workers;
    Array!WorkerStart starts;
    Array!GenRequest requests;
    Array!GenResult results;
    Array!BuildingRequest buildingRequests;
    Array!double rescanAt;
    Array!uint waiting;
    GenQueue* queue;
    size_t resultsHead;
    double travel = 0;
    uint workerCount;
    uint inFlight;
    uint buildingsInFlight;
    uint scanCursor;
    uint scanVersion;

    static Streamer make() {
        Streamer streamer;
        streamer.queue = cast(GenQueue*) calloc(1, GenQueue.sizeof);
        pthread_mutex_init(&streamer.queue.mutex, null);
        pthread_cond_init(&streamer.queue.workAvailable, null);
        pthread_cond_init(&streamer.queue.resultsReady, null);
        pthread_cond_init(&streamer.queue.jobFinished, null);
        uint threadCount = workerThreadCount(sysconf(_SC_NPROCESSORS_ONLN));
        streamer.workers.resize(threadCount);
        streamer.starts.resize(threadCount);
        foreach (i; 0 .. threadCount) {
            streamer.starts.ptr[i] = WorkerStart(streamer.queue, i + 1);
            pthread_create(&streamer.workers.ptr[i], null, &workerMain, &streamer.starts.ptr[i]);
        }
        streamer.workerCount = threadCount;
        return streamer;
    }

    void runParallel(ParallelJob* job) {
        pthread_mutex_lock(&queue.mutex);
        queue.job = job;
        pthread_cond_broadcast(&queue.workAvailable);
        while (queue.isJobOpen()) {
            queue.runClaimed(MAIN_WORKER);
        }
        while (job.finished < job.count) {
            pthread_cond_wait(&queue.jobFinished, &queue.mutex);
        }
        queue.job = null;
        pthread_mutex_unlock(&queue.mutex);
    }

    Executor executor() {
        return Executor(&runOn, &this, workerCount + 1);
    }

    void drive(ref Graph graph, const(NearbyNode)[] nearby, MIsometry!float cameraLocal, float distance, uint nearbyVersion, bool isUnbudgeted) {
        double deadline = budgetDeadline(isUnbudgeted);
        if (rescanAt.length < graph.nodeCount) {
            rescanAt.resize(graph.nodeCount);
        }
        integrate(graph, false, deadline);
        requests.clear();
        buildingRequests.clear();
        foreach (chunk; graph.restores.slice()) {
            requests.append(GenRequest(ChunkParams.make(graph, chunk.slot, chunk.vertex), chunk, true));
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
        submitRequests();
    }

    void rescanBuilt(ref Graph graph, const(NearbyNode)[] nearby, ScanRange range, uint budget) {
        size_t kept = 0;
        foreach (index; waiting.slice()) {
            NearbyNode nearbyNode = nearby[index];
            bool isDone = false;
            if (!graph.nodeAt(nearbyNode.slot).isBuildingQueued) {
                immutable ScanOutcome outcome = scanNode(graph, nearbyNode, range, budget);
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
        return rescanAt.ptr[slot] <= travel;
    }

    size_t scan(ref Graph graph, const(NearbyNode)[] nearby, ScanRange range, uint budget, double deadline) {
        uint scanned = 0;
        size_t index = scanCursor;
        bool isLate = nowMilliseconds() >= deadline;
        while (index < nearby.length && scanned < MAX_SCAN_NODES_PER_FRAME && !isLate) {
            NearbyNode nearbyNode = nearby[index];
            if (isScanPending(nearbyNode.slot)) {
                scanned += 1;
                immutable ScanOutcome outcome = scanNode(graph, nearbyNode, range, budget);
                if (outcome.isInterrupted) {
                    break;
                } else if (outcome.isWaitingOnBuilding) {
                    rescanAt.ptr[nearbyNode.slot] = RESCAN;
                    waiting.append(cast(uint) index);
                } else {
                    rescanAt.ptr[nearbyNode.slot] = travel + range.margin(outcome);
                }
                isLate = nowMilliseconds() >= deadline;
            } else if (index % SKIPPED_PER_CLOCK_CHECK == 0) {
                isLate = nowMilliseconds() >= deadline;
            }
            index += 1;
        }
        return index;
    }

    float rangeProduct(NearbyNode nearbyNode, Vertex vertex, MPoint!float camera) const {
        return -camera.mip((nearbyNode.transform * vertex.chunkBoundingSphereCenter).vec);
    }

    ScanOutcome scanNode(ref Graph graph, NearbyNode nearbyNode, ScanRange range, uint budget) {
        ScanOutcome outcome = ScanOutcome(float.infinity, float.infinity, false, false);
        uint vertexIndex = 0;
        while (vertexIndex < VERTEX_COUNT && !outcome.isInterrupted) {
            Vertex vertex = cast(Vertex) vertexIndex;
            ChunkSlot slot = ChunkSlot(nearbyNode.slot, vertex);
            ChunkState state = graph.chunkAt(slot).state;
            if (state == ChunkState.fresh || state == ChunkState.dropped) {
                float product = rangeProduct(nearbyNode, vertex, range.camera);
                bool isFresh = state == ChunkState.fresh;
                bool isOutOfRange = product > (isFresh ? range.threshold : range.keepThreshold);
                if (!isOutOfRange && requests.length >= budget) {
                    outcome.isInterrupted = true;
                } else if (isFresh && isOutOfRange) {
                    if (product < outcome.nearestOutOfRange) {
                        outcome.nearestOutOfRange = product;
                    }
                } else if (isFresh && !isBuildingReady(graph, nearbyNode.slot)) {
                    scheduleBuilding(graph, nearbyNode.slot);
                    outcome.isWaitingOnBuilding = true;
                } else if (isFresh) {
                    request(graph, slot);
                } else if (isOutOfRange) {
                    if (product < outcome.nearestDropped) {
                        outcome.nearestDropped = product;
                    }
                } else {
                    restore(graph, slot);
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
        requests.append(GenRequest(ChunkParams.make(graph, slot.slot, slot.vertex), slot, true));
    }

    void scheduleBuilding(ref Graph graph, uint slot) {
        if (!graph.nodeAt(slot).hasBuilding && !graph.nodeAt(slot).isBuildingQueued) {
            graph.nodeAt(slot).isBuildingQueued = true;
            graph.restoreBrushes(slot);
            buildingRequests.append(BuildingRequest(BuildingPlan.make(graph, slot), slot));
        }
    }

    void request(ref Graph graph, ChunkSlot slot) {
        ChunkParams params = ChunkParams.make(graph, slot.slot, slot.vertex);
        Chunk* chunk = graph.chunkFor(slot);
        chunk.predicted = params.predictOccupancy();
        if (chunk.predicted != Occupancy.empty) {
            requests.append(GenRequest(params, slot, false));
            chunk.state = ChunkState.generating;
        } else {
            graph.populateChunk(slot, params.generateVoxels());
        }
    }

    void submitRequests() {
        if (requests.length > 0 || buildingRequests.length > 0) {
            inFlight += cast(uint) requests.length;
            buildingsInFlight += cast(uint) buildingRequests.length;
            pthread_mutex_lock(&queue.mutex);
            queue.pending.appendAll(requests.slice());
            queue.pendingBuildings.appendAll(buildingRequests.slice());
            pthread_cond_broadcast(&queue.workAvailable);
            pthread_mutex_unlock(&queue.mutex);
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
        return inFlight == 0 && buildingsInFlight == 0;
    }

    void settle(ref Graph graph) {
        while (!isIdle()) {
            integrate(graph, true, 0);
        }
    }

    void integrate(ref Graph graph, bool isWaiting, double deadline) {
        pthread_mutex_lock(&queue.mutex);
        while (isWaiting && !queue.hasResults() && resultsHead == results.length) {
            pthread_cond_wait(&queue.resultsReady, &queue.mutex);
        }
        results.appendAll(queue.done.slice());
        queue.done.clear();
        foreach (built; queue.doneBuildings.slice()) {
            integrateBuilding(graph, built);
        }
        queue.doneBuildings.clear();
        pthread_mutex_unlock(&queue.mutex);
        while (resultsHead < results.length && (isWaiting || nowMilliseconds() < deadline)) {
            GenResult result = results.ptr[resultsHead];
            resultsHead += 1;
            inFlight -= 1;
            if (result.isRestoring) {
                graph.restoreChunk(result.chunk, result.generated);
            } else {
                graph.populateChunk(result.chunk, result.generated);
            }
        }
        if (resultsHead == results.length) {
            results.clear();
            resultsHead = 0;
        }
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
        pthread_mutex_lock(&queue.mutex);
        queue.isStopping = true;
        pthread_cond_broadcast(&queue.workAvailable);
        pthread_mutex_unlock(&queue.mutex);
        foreach (i; 0 .. workerCount) {
            pthread_join(workers.ptr[i], null);
        }
        workerCount = 0;
        workers.release();
        starts.release();
        foreach (result; queue.done.slice()) {
            result.generated.voxels.release();
        }
        foreach (built; queue.doneBuildings.slice()) {
            built.building.release();
        }
        foreach (request; queue.pendingBuildings.slice()[queue.pendingBuildingHead .. $]) {
            request.plan.release();
        }
        queue.pendingBuildings.release();
        queue.doneBuildings.release();
        buildingRequests.release();
        foreach (result; results.slice()[resultsHead .. $]) {
            result.generated.voxels.release();
        }
        queue.pending.release();
        queue.done.release();
        pthread_cond_destroy(&queue.workAvailable);
        pthread_cond_destroy(&queue.resultsReady);
        pthread_cond_destroy(&queue.jobFinished);
        pthread_mutex_destroy(&queue.mutex);
        free(queue);
        queue = null;
        requests.release();
        results.release();
        rescanAt.release();
        waiting.release();
    }
}

void runOn(void* context, ParallelJob* job) {
    (cast(Streamer*) context).runParallel(job);
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

double budgetDeadline(bool isUnbudgeted) {
    if (isUnbudgeted) {
        return NO_DEADLINE;
    } else {
        return nowMilliseconds() + WORLDGEN_BUDGET_MILLISECONDS;
    }
}

void generateNow(ref Graph graph, ChunkSlot chunk) {
    if (graph.chunkAt(chunk).state == ChunkState.fresh) {
        ChunkParams params = ChunkParams.make(graph, chunk.slot, chunk.vertex);
        graph.chunkFor(chunk).predicted = params.predictOccupancy();
        graph.populateChunk(chunk, params.generateVoxels());
    }
}

bool hasPopulatedNeighbor(ref const Graph graph, ChunkSlot chunk, ChunkDirection direction) {
    ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
    return neighbor.slot != NO_SLOT && graph.chunkAt(neighbor).state == ChunkState.populated;
}

void populateChunk(ref Graph graph, ChunkSlot chunk, GeneratedVoxels generated) {
    Chunk* target = graph.chunkFor(chunk);
    target.voxels = generated.voxels;
    target.hasDeferredMaterials = generated.hasDeferredMaterials;
    bool isContradicted = (*target).isPredictionContradicted();
    graph.restoreDroppedNeighbors(chunk);
    graph.connectMargins(chunk);
    target.state = ChunkState.populated;
    if (isContradicted) {
        graph.touchChunksAround(chunk);
    }
    graph.resolveIfExposed(chunk);
    foreach (direction; CHUNK_DIRECTIONS) {
        if (graph.hasPopulatedNeighbor(chunk, direction)) {
            graph.resolveIfExposed(graph.chunkNeighborSlot(chunk, direction));
        }
    }
}

void restoreDroppedNeighbors(ref Graph graph, ChunkSlot chunk) {
    foreach (direction; CHUNK_DIRECTIONS) {
        ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
        if (neighbor.slot != NO_SLOT && graph.chunkAt(neighbor).state == ChunkState.dropped) {
            graph.chunkFor(neighbor).state = ChunkState.generating;
            graph.restores.append(neighbor);
        }
    }
}

void restoreChunk(ref Graph graph, ChunkSlot chunk, GeneratedVoxels generated) {
    Chunk* target = graph.chunkFor(chunk);
    target.voxels = generated.voxels;
    target.hasDeferredMaterials = generated.hasDeferredMaterials;
    foreach (direction; CHUNK_DIRECTIONS) {
        if (graph.hasPopulatedNeighbor(chunk, direction)) {
            target.voxels.fixMargins(graph.chunkFor(graph.chunkNeighborSlot(chunk, direction)).voxels, graph.margins, chunk.vertex, direction);
        }
    }
    target.state = ChunkState.populated;
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

ChunkId chunkNeighborId(ref const Graph graph, ChunkId chunk, ChunkDirection direction) {
    if (direction.sign == CoordSign.plus) {
        return ChunkId(chunk.node, chunk.vertex.adjacentVertices[direction.axis]);
    } else {
        return ChunkId(graph.neighbor(chunk.node, chunk.vertex.canonicalSides[direction.axis]), chunk.vertex);
    }
}
