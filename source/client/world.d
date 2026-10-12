module client.world;

import core.stdc.math : coshf;
import base.array : Array;
import base.clock : PhaseTimes, nowMilliseconds, threadCpuMilliseconds;
import client.arrivals : resolveIfExposed, resolveMaterials;
import client.camera : CAMERA_FORWARD;
import client.streaming : Streamer;
import common.eviction : Evictor, Unloaded;
import common.graph : Graph, NO_NODE;
import common.material : Material;
import common.neighbors : chunkNeighborId, neighborAxisMap, touchChunksReading;
import common.node : Chunk, ChunkId, ChunkSlot, ChunkState, cellIndex;
import common.position : Position;
import common.raycast.graph : GraphCastHit, rayCast;
import common.traversal : NOT_COLLECTED, NO_DEADLINE, NearbyNode, NearbyScratch;
import common.worldgen.generation : Worldgen;
import geometry.cube : Cell, Direction, boundaryOf;
import geometry.lorentz : Motion, Point, Vec4;
import geometry.ray : Ray;

enum float NEARBY_PADDING = 0.05f;
enum float NEARBY_REBUILD_DISTANCE = 0.25f;
enum float NEARBY_REROOT_DISTANCE = 3.0f;
enum double TELEPORT_TRAVEL = 1.0e3;
enum float RENDER_RADIUS = 8.0f;
enum float FULL_RADIUS = 4.5f;
enum double STEP_BUDGET_MILLISECONDS = 5.0;
enum double NEARBY_LEAST_MILLISECONDS = 1.0;
enum double STREAMER_LEAST_MILLISECONDS = 1.0;
enum size_t STRUCTURE_CANDIDATES = 256;
enum double RECOVERY_BUDGET_MILLISECONDS = 8.0;

struct Placement {
    ChunkId chunk;
    Cell coords;
    bool isFound;
}

struct NearbyStats {
    double slicedMilliseconds = 0;
    double recoveryMilliseconds = 0;
    size_t kept;
    size_t reexpanded;
    uint publishes;
    uint recoveries;
    uint grown;
}

struct StepPhases {
    PhaseTimes paint;
    PhaseTimes nearby;
    PhaseTimes streamer;
    PhaseTimes evict;
    PhaseTimes nearbyCpu;
    PhaseTimes streamerCpu;
}

struct TargetMaterial {
    Material material;
    bool isFound;
}

struct LocalWorld {
    Graph graph;
    Streamer streamer;
    NearbyScratch[2] nearby;
    Position cameraPosition;
    Point!float publishedPoint;
    Point!float pendingPoint;
    Point!float trackedCamera;
    uint trackedVersion;
    NearbyNode[] cachedNodes;
    Array!Unloaded unloaded;
    Array!uint candidates;
    float renderRadius;
    float tanhReach;
    uint published;
    uint nearbyVersion;
    uint epoch;
    Evictor evictor;
    StepPhases phases;
    NearbyStats nearbyStats;
    bool hasNearby;

    static LocalWorld make(ubyte dimension, Worldgen worldgen, float tanhReach) {
        LocalWorld world;
        world.graph = Graph.make(dimension, worldgen);
        world.streamer = Streamer.make();
        world.cameraPosition = Position.origin();
        world.renderRadius = RENDER_RADIUS;
        world.tanhReach = tanhReach;
        return world;
    }

    void release() {
        streamer.release();
        nearby[0].release();
        nearby[1].release();
        evictor.release();
        unloaded.release();
        candidates.release();
        graph.release();
    }

    uint cameraNearbyIndex() const {
        return nearby[published].indexOf(graph.slotOf(cameraPosition.node));
    }

    Motion!float cameraInNearbyFrame() const {
        return nearby[published].nodes.ptr[cameraNearbyIndex()].transform * cameraPosition.local;
    }

    // The world's share of a frame is split by what each phase took last frame: the nearby search gets what the
    // streamer and eviction leave, and every phase gets at least a little so none of them stalls.
    void update(bool isUnbudgeted) {
        double start = nowMilliseconds();
        double end = start + STEP_BUDGET_MILLISECONDS;
        paintAhead();
        double painted = nowMilliseconds();
        double paintedCpu = threadCpuMilliseconds();
        float distance = renderRadius + NEARBY_PADDING;
        double deadline = phaseDeadline(isUnbudgeted, end - phases.streamer.lastMs - phases.evict.lastMs, NEARBY_LEAST_MILLISECONDS);
        if (!hasNearby) {
            buildInitialNearby(distance, deadline);
        } else if (cameraNearbyIndex() == NOT_COLLECTED) {
            recoverNearby(distance);
        } else {
            refreshNearby(distance, deadline);
        }
        trackTravel();
        double found = nowMilliseconds();
        double foundCpu = threadCpuMilliseconds();
        streamer.drive(graph, cachedNodes, cameraPosition, cameraInNearbyFrame(), renderRadius, nearbyVersion, isUnbudgeted, phaseDeadline(isUnbudgeted, end - phases.evict.lastMs, STREAMER_LEAST_MILLISECONDS));
        double streamed = nowMilliseconds();
        double streamedCpu = threadCpuMilliseconds();
        evict();
        phases.paint.add(painted - start);
        phases.nearby.add(found - painted);
        phases.streamer.add(streamed - found);
        phases.evict.add(nowMilliseconds() - streamed);
        phases.nearbyCpu.add(foundCpu - paintedCpu);
        phases.streamerCpu.add(streamedCpu - foundCpu);
    }

    // Structure for the nodes the scan needs next is painted on every thread here, so the scan's structure checks on
    // this thread only finish what is already painted.
    void paintAhead() {
        if (graph.structures.grower.paintAhead !is null) {
            candidates.clear();
            streamer.collectUnstructured(graph, cachedNodes, candidates, STRUCTURE_CANDIDATES);
            graph.paintAhead(candidates.slice(), streamer.executor());
        }
    }

    void evict() {
        size_t first = unloaded.length;
        NearbyScratch* next = &nearby[1 - published];
        const(NearbyScratch)* building = null;
        if (next.isBuilding()) {
            building = next;
        }
        evictor.sweep(graph, nearby[published], building, cameraInNearbyFrame() * Point!float.origin(), unloaded, nowMilliseconds());
        streamer.forget(unloaded.slice()[first .. $]);
    }

    void trackTravel() {
        Point!float camera = cameraInNearbyFrame() * Point!float.origin();
        if (trackedVersion == nearbyVersion) {
            float moved = trackedCamera.distance(camera);
            streamer.travel += moved;
            graph.structures.blueprint.travel += moved;
        } else {
            streamer.travel += NEARBY_PADDING;
        }
        trackedCamera = camera;
        trackedVersion = nearbyVersion;
    }

    void buildInitialNearby(float distance, double deadline) {
        NearbyScratch* current = &nearby[published];
        if (!current.isBuilding() || cameraNearbyIndex() == NOT_COLLECTED) {
            current.begin(graph, cameraPosition, distance, FULL_RADIUS);
            publishedPoint = cameraPosition.local * Point!float.origin();
            nearbyVersion += 1;
            streamer.travel += TELEPORT_TRAVEL;
        }
        current.advance(graph, deadline, streamer.executor());
        hasNearby = !current.isBuilding();
        cachedNodes = current.nodes.slice();
    }

    void recoverNearby(float distance) {
        double start = nowMilliseconds();
        NearbyScratch* next = &nearby[1 - published];
        if (!next.isBuilding() || next.indexOf(graph.slotOf(cameraPosition.node)) == NOT_COLLECTED) {
            next.begin(graph, cameraPosition, distance, FULL_RADIUS);
            pendingPoint = cameraPosition.local * Point!float.origin();
            next.advance(graph, start + RECOVERY_BUDGET_MILLISECONDS, streamer.executor());
        }
        nearbyStats.recoveries += 1;
        nearbyStats.recoveryMilliseconds += nowMilliseconds() - start;
        streamer.travel += TELEPORT_TRAVEL;
        publish(pendingPoint);
    }

    void refreshNearby(float distance, double deadline) {
        double start = nowMilliseconds();
        NearbyScratch* current = &nearby[published];
        NearbyScratch* next = &nearby[1 - published];
        Point!float camera = cameraInNearbyFrame() * Point!float.origin();
        if (current.isBuilding()) {
            current.advance(graph, deadline, streamer.executor());
            cachedNodes = current.nodes.slice();
        } else {
            if (!next.isBuilding() && publishedPoint.coshDistance(camera) > coshf(NEARBY_REBUILD_DISTANCE)) {
                startNext(distance, camera);
            }
            if (next.isBuilding()) {
                next.advance(graph, deadline, streamer.executor());
                if (!next.isBuilding()) {
                    publishOrRestart(distance);
                }
            }
        }
        nearbyStats.slicedMilliseconds += nowMilliseconds() - start;
    }

    // The next set grows out of the published one while the camera stays near its frame's origin. Past that, nodes on
    // the far side get transforms large enough to lose precision, so the next set starts over around the camera.
    void startNext(float distance, Point!float camera) {
        NearbyScratch* next = &nearby[1 - published];
        if (camera.distance(Point!float.origin()) < NEARBY_REROOT_DISTANCE) {
            next.beginFrom(nearby[published], graph, camera, distance, FULL_RADIUS, streamer.executor());
            pendingPoint = camera;
            nearbyStats.grown += 1;
            nearbyStats.kept += next.front;
            nearbyStats.reexpanded += next.nodes.length - next.front;
        } else {
            next.begin(graph, cameraPosition, distance, FULL_RADIUS);
            pendingPoint = cameraPosition.local * Point!float.origin();
        }
    }

    // A search started before the camera jumped, or left behind by a recovery and resumed, may not reach the camera;
    // publishing it would lose the camera, so it starts over from where the camera is.
    void publishOrRestart(float distance) {
        NearbyScratch* next = &nearby[1 - published];
        if (next.indexOf(graph.slotOf(cameraPosition.node)) != NOT_COLLECTED) {
            publish(pendingPoint);
        } else {
            next.begin(graph, cameraPosition, distance, FULL_RADIUS);
            pendingPoint = cameraPosition.local * Point!float.origin();
        }
    }

    void publish(Point!float point) {
        published = 1 - published;
        cachedNodes = nearby[published].nodes.slice();
        publishedPoint = point;
        nearbyVersion += 1;
        nearbyStats.publishes += 1;
    }

    bool isWorldgenSettled() const {
        return hasNearby && !nearby[published].isBuilding() && streamer.isIdle() && streamer.waiting.length == 0 && streamer.scanCursor >= cachedNodes.length;
    }

    GraphCastHit castCenterRay() const {
        Ray ray = Ray(Point!float.origin(), Vec4!float([CAMERA_FORWARD[0], CAMERA_FORWARD[1], CAMERA_FORWARD[2], 0]).toNormal());
        return graph.rayCast(cameraPosition, ray, tanhReach);
    }

    TargetMaterial targetMaterial() const {
        GraphCastHit hit = castCenterRay();
        if (!hit.isHit()) {
            return TargetMaterial.init;
        } else {
            const(Chunk)* chunk = graph.chunks.at(ChunkSlot(graph.slotOf(hit.chunk.node), hit.chunk.corner));
            ubyte[3] cell = hit.voxelCoords.c;
            return TargetMaterial(chunk.voxels.at(cellIndex(graph.layout.dimension, cell[0], cell[1], cell[2])), true);
        }
    }

    bool breakBlock() {
        GraphCastHit hit = castCenterRay();
        if (hit.isHit()) {
            return setVoxel(hit.chunk, hit.voxelCoords, Material.none);
        } else {
            return false;
        }
    }

    Placement placementTarget() const {
        GraphCastHit hit = castCenterRay();
        if (!hit.isHit()) {
            return Placement.init;
        } else {
            return placementBeside(hit);
        }
    }

    Placement placementBeside(GraphCastHit hit) const {
        ubyte dimension = graph.layout.dimension;
        Cell coords = hit.voxelCoords;
        int stepped = coords.c[hit.faceAxis] + hit.faceSign;
        Direction direction = Direction(hit.faceAxis, hit.faceSign);
        ChunkId neighbor = graph.chunkNeighborId(hit.chunk, direction);
        if (stepped >= 0 && stepped < dimension) {
            coords.c[hit.faceAxis] = cast(ubyte) stepped;
            return Placement(hit.chunk, coords, true);
        } else if (neighbor.node == NO_NODE) {
            return Placement.init;
        } else {
            coords.c[hit.faceAxis] = boundaryOf(dimension, direction.sign);
            return Placement(neighbor, Cell(neighborAxisMap(hit.chunk.corner, direction).apply(coords.c)), true);
        }
    }

    bool setVoxel(ChunkId chunkId, Cell coords, Material material) {
        ubyte dimension = graph.layout.dimension;
        ChunkSlot slot = ChunkSlot(graph.slotOf(chunkId.node), chunkId.corner);
        if (graph.chunks.at(slot).state != ChunkState.populated) {
            return false;
        } else {
            Chunk* chunk = graph.chunks.existing(slot);
            if (chunk.hasDeferredMaterials) {
                graph.resolveMaterials(slot);
            }
            chunk.voxels.toDense(dimension)[cellIndex(dimension, coords.c[0], coords.c[1], coords.c[2])] = material;
            chunk.isEdited = true;
            graph.markChanged(slot);
            Array!ChunkSlot holders;
            graph.touchChunksReading(slot, [coords.c[0], coords.c[1], coords.c[2]], holders);
            foreach (holder; holders.slice()) {
                graph.markChanged(holder);
                graph.resolveIfExposed(holder);
            }
            holders.release();
            return true;
        }
    }
}

double phaseDeadline(bool isUnbudgeted, double planned, double leastMilliseconds) {
    double earliest = nowMilliseconds() + leastMilliseconds;
    if (isUnbudgeted) {
        return NO_DEADLINE;
    } else if (planned > earliest) {
        return planned;
    } else {
        return earliest;
    }
}
