module client.world;

import core.stdc.math : acoshf, coshf;
import client.camera : CAMERA_FORWARD;
import client.streaming : Streamer, chunkNeighborId, hasPopulatedNeighbor, resolveIfExposed, resolveMaterials;
import common.clock : PhaseTimes, nowMilliseconds, threadCpuMilliseconds;
import common.array : Array;
import common.coords : CHUNK_DIRECTIONS, ChunkDirection, Coords, boundaryCoord;
import common.eviction : Evictor, Unloaded;
import common.graph : Graph, NO_NODE;
import common.margins : CoordsWithMargins, neighborAxisPermutation;
import common.material : Material;
import common.math : MIsometry, MPoint, MVector;
import common.neighbors : chunkNeighborSlot, touchChunksReading;
import common.node : Chunk, ChunkId, ChunkSlot, ChunkState;
import common.position : Position;
import common.ray : Ray;
import common.raycast.graph : GraphCastHit, rayCast;
import common.traversal : NOT_COLLECTED, NO_DEADLINE, NearbyNode, NearbyScratch;
import common.worldgen.generation : Worldgen;

enum float NEARBY_PADDING = 0.05f;
enum float NEARBY_REBUILD_DISTANCE = 0.25f;
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
    Coords coords;
    bool isFound;
}

struct NearbyStats {
    double slicedMilliseconds = 0;
    double recoveryMilliseconds = 0;
    uint publishes;
    uint recoveries;
}

struct StepPhases {
    PhaseTimes prepare;
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
    MPoint!float publishedPoint;
    MPoint!float pendingPoint;
    MPoint!float trackedCamera;
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

    MIsometry!float cameraInNearbyFrame() const {
        return nearby[published].nodes.ptr[cameraNearbyIndex()].transform * cameraPosition.local;
    }

    // The world's share of a frame is split by what each phase took last frame: the nearby search gets what the
    // streamer and eviction leave, and every phase gets at least a little so none of them stalls.
    void update(bool isUnbudgeted) {
        double start = nowMilliseconds();
        double end = start + STEP_BUDGET_MILLISECONDS;
        prepareStructures();
        double prepared = nowMilliseconds();
        double preparedCpu = threadCpuMilliseconds();
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
        streamer.drive(graph, cachedNodes, cameraInNearbyFrame(), renderRadius, nearbyVersion, isUnbudgeted, phaseDeadline(isUnbudgeted, end - phases.evict.lastMs, STREAMER_LEAST_MILLISECONDS));
        double streamed = nowMilliseconds();
        double streamedCpu = threadCpuMilliseconds();
        evict();
        phases.prepare.add(prepared - start);
        phases.nearby.add(found - prepared);
        phases.streamer.add(streamed - found);
        phases.evict.add(nowMilliseconds() - streamed);
        phases.nearbyCpu.add(foundCpu - preparedCpu);
        phases.streamerCpu.add(streamedCpu - foundCpu);
    }

    // Structure for the nodes the scan needs next is painted on every thread here, so the scan's structure checks on
    // this thread only finish what is already painted.
    void prepareStructures() {
        if (graph.grower.prepare !is null) {
            candidates.clear();
            streamer.collectUnstructured(graph, cachedNodes, candidates, STRUCTURE_CANDIDATES);
            graph.prepareStructures(candidates.slice(), streamer.executor());
        }
    }

    void evict() {
        size_t first = unloaded.length;
        NearbyScratch* next = &nearby[1 - published];
        const(NearbyScratch)* building = null;
        if (next.isBuilding()) {
            building = next;
        }
        evictor.sweep(graph, nearby[published], building, cameraInNearbyFrame() * MPoint!float.origin(), unloaded, nowMilliseconds());
        streamer.forget(unloaded.slice()[first .. $]);
    }

    void trackTravel() {
        MPoint!float camera = cameraInNearbyFrame() * MPoint!float.origin();
        if (trackedVersion == nearbyVersion) {
            float product = -trackedCamera.mip(camera.vec);
            if (product > 1) {
                float moved = acoshf(product);
                streamer.travel += moved;
                graph.blueprint.travel += moved;
            }
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
            publishedPoint = cameraPosition.local * MPoint!float.origin();
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
            pendingPoint = cameraPosition.local * MPoint!float.origin();
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
        MPoint!float camera = cameraInNearbyFrame() * MPoint!float.origin();
        if (current.isBuilding()) {
            current.advance(graph, deadline, streamer.executor());
            cachedNodes = current.nodes.slice();
        } else {
            if (!next.isBuilding() && -publishedPoint.mip(camera.vec) > coshf(NEARBY_REBUILD_DISTANCE)) {
                next.begin(graph, cameraPosition, distance, FULL_RADIUS);
                pendingPoint = cameraPosition.local * MPoint!float.origin();
            }
            if (next.isBuilding()) {
                next.advance(graph, deadline, streamer.executor());
                if (!next.isBuilding()) {
                    publish(pendingPoint);
                }
            }
        }
        nearbyStats.slicedMilliseconds += nowMilliseconds() - start;
    }

    void publish(MPoint!float point) {
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
        Ray ray = Ray(MPoint!float.origin(), MVector!float([CAMERA_FORWARD[0], CAMERA_FORWARD[1], CAMERA_FORWARD[2], 0]).normalizedDirection());
        return graph.rayCast(cameraPosition, ray, tanhReach);
    }

    TargetMaterial targetMaterial() const {
        GraphCastHit hit = castCenterRay();
        if (!hit.isHit()) {
            return TargetMaterial.init;
        } else {
            const(Chunk)* chunk = graph.chunkAt(ChunkSlot(graph.slotOf(hit.chunk.node), hit.chunk.vertex));
            return TargetMaterial(chunk.voxels.get(hit.voxelCoords.toIndex(graph.layout.dimension)), true);
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
        Coords coords = hit.voxelCoords;
        int stepped = coords.data[hit.faceAxis] + hit.faceSign;
        ChunkDirection direction = ChunkDirection(hit.faceAxis, hit.faceSign);
        ChunkId neighbor = graph.chunkNeighborId(hit.chunk, direction);
        if (stepped >= 0 && stepped < dimension) {
            coords.data[hit.faceAxis] = cast(ubyte) stepped;
            return Placement(hit.chunk, coords, true);
        } else if (neighbor.node == NO_NODE) {
            return Placement.init;
        } else {
            coords.data[hit.faceAxis] = boundaryCoord(dimension, direction.sign);
            return Placement(neighbor, neighborAxisPermutation(hit.chunk.vertex, direction).apply(coords), true);
        }
    }

    bool setVoxel(ChunkId chunkId, Coords coords, Material material) {
        ubyte dimension = graph.layout.dimension;
        ChunkSlot slot = ChunkSlot(graph.slotOf(chunkId.node), chunkId.vertex);
        if (graph.chunkAt(slot).state != ChunkState.populated) {
            return false;
        } else {
            Chunk* chunk = graph.chunkFor(slot);
            if (chunk.hasDeferredMaterials) {
                graph.resolveMaterials(slot);
            }
            chunk.voxels.toDense(dimension)[coords.toIndex(dimension)] = material;
            chunk.isEdited = true;
            graph.markChanged(slot);
            foreach (direction; CHUNK_DIRECTIONS) {
                if (coords.data[direction.axis] == boundaryCoord(dimension, direction.sign) && graph.hasPopulatedNeighbor(slot, direction)) {
                    ChunkSlot neighbor = graph.chunkNeighborSlot(slot, direction);
                    chunk.voxels.fixMargins(graph.chunkFor(neighbor).voxels, graph.margins, chunkId.vertex, direction);
                    graph.markChanged(neighbor);
                    graph.resolveIfExposed(neighbor);
                }
            }
            Array!ChunkSlot holders;
            graph.touchChunksReading(slot, CoordsWithMargins.fromCoords(coords), holders);
            foreach (holder; holders.slice()) {
                graph.markChanged(holder);
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
