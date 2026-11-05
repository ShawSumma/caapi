module client.world;

import core.stdc.math : coshf, expf, logf, powf;
import base.array : Array;
import base.clock : Deadline, PhaseTimes, nowMilliseconds, threadCpuMilliseconds;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : higherOf, lowerOf;
import base.vector3 : Vec3;
import client.arrivals : resolveIfExposed, resolveMaterials;
import client.camera : CAMERA_FORWARD;
import client.streaming : Pacing, Streamer;
import common.eviction : Evictor, Unloaded;
import common.graph : Graph;
import common.neighbors : chunkNeighborId, neighborAxisMap, touchChunksReading;
import common.node : Chunk, ChunkId, ChunkSlot, ChunkState, cellIndex;
import common.position : Position;
import common.raycast.graph : GraphCastHit, rayCast;
import common.traversal : NearbyNode, NearbyScratch;
import common.worldgen.generation : Worldgen;
import common.worldgen.horospheres : lookAt;
import geometry.cube : Cell, Direction, boundaryOf;
import geometry.honeycomb : NODE_RADIUS;
import geometry.lorentz : Motion, Point, Vec4;
import geometry.ray : Ray;
import plugins.api.api : Color, Look, Material, Tint;

enum float NEARBY_PADDING = 0.05f;
enum float NEARBY_REBUILD_DISTANCE = 0.25f;
enum double REBUILD_NARROW_TRAVEL = 4 * NEARBY_REBUILD_DISTANCE;
enum double REBUILD_ABANDON_TRAVEL = FULL_RADIUS - CAMERA_REACH;
enum float REBUILD_GROWTH = 0.25f;
enum float REBASE_DISTANCE = NODE_RADIUS + 1.0f;
enum float REDERIVE_RADIUS = 6.0f;
enum double TELEPORT_TRAVEL = 1.0e3;
enum float RENDER_RADIUS = 8.0f;
enum float FOG_VISIBILITY_THRESHOLD = 1e-3f;
enum float FOG_LOAD_THRESHOLD = 1.0f / 256;
enum float FOG_SHARPNESS = 4.0f;
enum float FULL_RADIUS = 4.5f;
enum float CAMERA_REACH = 2.0f;
enum double STEP_BUDGET_MILLISECONDS = 8.0;
enum double NEARBY_LEAST_MILLISECONDS = 1.0;
enum double STREAMER_LEAST_MILLISECONDS = 1.0;
version (WebAssembly) {
    enum size_t STRUCTURE_CANDIDATES = 16;
} else {
    enum size_t STRUCTURE_CANDIDATES = 256;
}
enum double RECOVERY_BUDGET_MILLISECONDS = 8.0;
enum float FOG_COLOR_RATE = 1.5f;
enum Color SKY_SRGB = Color(0.55f, 0.7f, 0.94f);

struct Placement {
    ChunkId chunk;
    Cell coords;
}

enum NearbyStage : ubyte {
    initial,
    published,
    rebuilding,
}

struct NearbyStats {
    double slicedMilliseconds = 0;
    double recoveryMilliseconds = 0;
    double pendingTravel = 0;
    uint pendingFrames;
    uint publishes;
    uint recoveries;
    uint grown;
    uint narrowings;
    uint abandons;
    uint rebases;
}

struct StepPhases {
    PhaseTimes paint;
    PhaseTimes nearby;
    PhaseTimes streamer;
    PhaseTimes evict;
    PhaseTimes nearbyCpu;
    PhaseTimes streamerCpu;
}

struct LocalWorld {
    Graph graph;
    Streamer streamer;
    NearbyScratch[2] nearby;
    Position cameraPosition;
    Point!float publishedPoint;
    Point!float pendingPoint;
    Point!float trackedCamera;
    Vec3!float sunward = Vec3!float(0, 1, 0);
    Color fogColor = SKY_SRGB;
    uint trackedVersion;
    NearbyNode[] cachedNodes;
    Array!Unloaded unloaded;
    Array!uint candidates;
    double rebuildTravel = 0;
    double startTravel = 0;
    float renderRadius;
    float radiusCut = 0;
    float publishedCut = 0;
    float pendingCut = 0;
    float tanhReach;
    uint published;
    uint nearbyVersion;
    uint listVersion;
    uint epoch;
    Evictor evictor;
    StepPhases phases;
    NearbyStats nearbyStats;
    NearbyStage nearbyStage;

    static LocalWorld make(ubyte dimension, Worldgen worldgen, float tanhReach) {
        LocalWorld world;
        world.graph = Graph.make(dimension, worldgen);
        world.graph.bindView();
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

    MaybeIndex!uint cameraNearbyIndex() const {
        return nearby[published].indexOf(graph.slotOf(cameraPosition.node).value);
    }

    Motion!float cameraInNearbyFrame() const {
        return nearby[published].nodes.ptr[cameraNearbyIndex().value].transform * cameraPosition.local;
    }

    const(Look)* lookAtCamera() const {
        return graph.lookAt(cameraPosition);
    }

    Color wantedFogColor() const {
        const(Look)* look = lookAtCamera();
        const(Look)* world = &graph.structures.blueprint.look;
        if (look.tint == Tint.fog) {
            return look.fog;
        } else if (world.tint == Tint.fog) {
            return world.fog;
        } else {
            return SKY_SRGB;
        }
    }

    void settleFogColor() {
        fogColor = wantedFogColor();
    }

    void approachFogColor(float seconds) {
        Color wanted = wantedFogColor();
        float kept = expf(-FOG_COLOR_RATE * seconds);
        fogColor.red = wanted.red + (fogColor.red - wanted.red) * kept;
        fogColor.green = wanted.green + (fogColor.green - wanted.green) * kept;
        fogColor.blue = wanted.blue + (fogColor.blue - wanted.blue) * kept;
    }

    float viewRadius() const {
        Maybe!float fog = graph.structures.blueprint.fog;
        if (fog.exists) {
            return lowerOf(renderRadius, fog.value);
        } else {
            return renderRadius;
        }
    }

    float loadRadius() const {
        return fogReach(viewRadius()) * powf(logf(1.0f / FOG_LOAD_THRESHOLD), 1.0f / FOG_SHARPNESS);
    }

    void update(Pacing pacing) {
        double start = nowMilliseconds();
        double end = start + STEP_BUDGET_MILLISECONDS - phases.evict.lastMs;
        paintAhead();
        double painted = nowMilliseconds();
        double paintedCpu = threadCpuMilliseconds();
        Deadline deadline = phaseDeadline(pacing, end - phases.streamer.lastMs, NEARBY_LEAST_MILLISECONDS);
        if (nearbyStage == NearbyStage.initial) {
            buildInitialNearby(deadline);
        } else if (!cameraNearbyIndex().exists) {
            recoverNearby();
        } else {
            refreshNearby(deadline);
        }
        followCamera();
        keepCameraCollected();
        trackTravel();
        double found = nowMilliseconds();
        double foundCpu = threadCpuMilliseconds();
        streamer.drive(graph, cachedNodes, cameraPosition, cameraInNearbyFrame(), loadRadius(), nearbyVersion, pacing, phaseDeadline(pacing, end, STREAMER_LEAST_MILLISECONDS));
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

    void keepCameraCollected() {
        uint cameraSlot = graph.slotOf(cameraPosition.node).value;
        nearby[published].collectAround(graph, cameraSlot, cameraInNearbyFrame() * Point!float.origin(), CAMERA_REACH);
        NearbyScratch* next = &nearby[1 - published];
        MaybeIndex!uint index = next.indexOf(cameraSlot);
        if (next.isBuilding() && !next.isKeeping() && index.exists) {
            next.collectAround(graph, cameraSlot, next.nodes.ptr[index.value].transform * cameraPosition.local * Point!float.origin(), CAMERA_REACH);
        }
        cachedNodes = nearby[published].nodes.slice();
    }

    void trackTravel() {
        Point!float camera = cameraInNearbyFrame() * Point!float.origin();
        if (trackedVersion == nearbyVersion) {
            streamer.travel += trackedCamera.distance(camera);
        } else {
            streamer.travel += NEARBY_PADDING;
        }
        trackedCamera = camera;
        trackedVersion = nearbyVersion;
    }

    void buildInitialNearby(Deadline deadline) {
        NearbyScratch* current = &nearby[published];
        if (!current.isBuilding() || !cameraNearbyIndex().exists) {
            current.begin(graph, cameraPosition, rebuildDistance(), FULL_RADIUS);
            publishedPoint = cameraPosition.local * Point!float.origin();
            publishedCut = radiusCut;
            nearbyVersion += 1;
            listVersion += 1;
            streamer.travel += TELEPORT_TRAVEL;
            startTravel = streamer.travel;
        }
        current.advance(graph, deadline, streamer.executor());
        if (!current.isBuilding()) {
            nearbyStage = NearbyStage.published;
        }
        cachedNodes = current.nodes.slice();
    }

    void recoverNearby() {
        double start = nowMilliseconds();
        NearbyScratch* next = &nearby[1 - published];
        if (!next.isBuilding() || next.isKeeping() || !next.indexOf(graph.slotOf(cameraPosition.node).value).exists) {
            next.begin(graph, cameraPosition, rebuildDistance(), FULL_RADIUS);
            pendingPoint = cameraPosition.local * Point!float.origin();
            pendingCut = radiusCut;
            next.advance(graph, Deadline.at(start + RECOVERY_BUDGET_MILLISECONDS), streamer.executor());
        }
        nearbyStats.recoveries += 1;
        nearbyStats.recoveryMilliseconds += nowMilliseconds() - start;
        streamer.travel += TELEPORT_TRAVEL;
        startTravel = streamer.travel;
        publish(pendingPoint);
    }

    void refreshNearby(Deadline deadline) {
        double start = nowMilliseconds();
        NearbyScratch* current = &nearby[published];
        NearbyScratch* next = &nearby[1 - published];
        Point!float camera = cameraInNearbyFrame() * Point!float.origin();
        if ((current.isBuilding() || nearbyStage == NearbyStage.rebuilding) && streamer.travel - startTravel > REBUILD_ABANDON_TRAVEL) {
            abandonRebuild(deadline);
        } else if (current.isBuilding()) {
            current.advance(graph, deadline, streamer.executor());
            cachedNodes = current.nodes.slice();
        } else {
            double traveled = streamer.travel - rebuildTravel;
            if (next.isBuilding() && !next.isKeeping() && traveled > REBUILD_NARROW_TRAVEL) {
                cutRadius(traveled);
                next.narrow(rebuildDistance());
                pendingCut = radiusCut;
                rebuildTravel = streamer.travel;
                nearbyStats.narrowings += 1;
            } else if (nearbyStage == NearbyStage.published && (publishedPoint.coshDistance(camera) > coshf(NEARBY_REBUILD_DISTANCE) || publishedCut > 0)) {
                startNext(camera);
            }
            if (nearbyStage == NearbyStage.rebuilding) {
                nearbyStats.pendingFrames += 1;
                next.continueKeeping(*current, deadline, streamer.executor());
                next.advance(graph, deadline, streamer.executor());
                if (!next.isBuilding()) {
                    publishOrRestart();
                }
            }
        }
        nearbyStats.slicedMilliseconds += nowMilliseconds() - start;
    }

    void abandonRebuild(Deadline deadline) {
        NearbyScratch* next = &nearby[1 - published];
        cutRadius(streamer.travel - rebuildTravel);
        next.begin(graph, cameraPosition, rebuildDistance(), FULL_RADIUS);
        pendingPoint = cameraPosition.local * Point!float.origin();
        pendingCut = radiusCut;
        rebuildTravel = streamer.travel;
        startTravel = streamer.travel;
        next.advance(graph, deadline, streamer.executor());
        nearbyStats.abandons += 1;
        publish(pendingPoint);
    }

    float rebuildDistance() const {
        return loadRadius() - radiusCut + NEARBY_PADDING;
    }

    void cutRadius(double traveled) {
        if (traveled > NEARBY_REBUILD_DISTANCE) {
            radiusCut += 0.5f * logf(cast(float)(traveled / NEARBY_REBUILD_DISTANCE));
        } else if (traveled < NEARBY_REBUILD_DISTANCE / 2) {
            radiusCut -= REBUILD_GROWTH;
        }
        radiusCut = higherOf(lowerOf(radiusCut, loadRadius() - FULL_RADIUS), 0.0f);
    }

    void startNext(Point!float camera) {
        NearbyScratch* current = &nearby[published];
        NearbyScratch* next = &nearby[1 - published];
        current.rederive(graph, graph.slotOf(cameraPosition.node).value, camera, FULL_RADIUS + NODE_RADIUS, streamer.executor());
        next.beginFrom(*current, graph, camera, rebuildDistance(), FULL_RADIUS);
        pendingPoint = camera;
        pendingCut = radiusCut;
        rebuildTravel = streamer.travel;
        startTravel = streamer.travel;
        nearbyStage = NearbyStage.rebuilding;
        nearbyStats.grown += 1;
    }

    void publishOrRestart() {
        NearbyScratch* next = &nearby[1 - published];
        if (next.indexOf(graph.slotOf(cameraPosition.node).value).exists) {
            cutRadius(streamer.travel - rebuildTravel);
            nearbyStats.pendingTravel += streamer.travel - startTravel;
            publish(pendingPoint);
        } else {
            next.begin(graph, cameraPosition, rebuildDistance(), FULL_RADIUS);
            pendingPoint = cameraPosition.local * Point!float.origin();
            pendingCut = radiusCut;
            startTravel = streamer.travel;
        }
    }

    void publish(Point!float point) {
        published = 1 - published;
        nearbyStage = NearbyStage.published;
        publishedCut = pendingCut;
        cachedNodes = nearby[published].nodes.slice();
        publishedPoint = point;
        nearbyVersion += 1;
        listVersion += 1;
        nearbyStats.publishes += 1;
    }

    void followCamera() {
        uint cameraSlot = graph.slotOf(cameraPosition.node).value;
        NearbyScratch* current = &nearby[published];
        NearbyScratch* next = &nearby[1 - published];
        Motion!float toCamera = current.nodes.ptr[current.indexOf(cameraSlot).value].transform;
        if (!next.isKeeping() && isFarFromOrigin(toCamera * cameraPosition.local)) {
            Motion!float toFrame = toCamera.inverse();
            current.rebase(graph, cameraSlot, toFrame, REDERIVE_RADIUS, streamer.executor());
            publishedPoint = toFrame * publishedPoint;
            trackedCamera = toFrame * trackedCamera;
            listVersion += 1;
            nearbyStats.rebases += 1;
        }
        MaybeIndex!uint index = next.indexOf(cameraSlot);
        if (next.isBuilding() && !next.isKeeping() && index.exists && isFarFromOrigin(next.nodes.ptr[index.value].transform * cameraPosition.local)) {
            Motion!float toFrame = next.nodes.ptr[index.value].transform.inverse();
            next.rebase(graph, cameraSlot, toFrame, REDERIVE_RADIUS, streamer.executor());
            pendingPoint = toFrame * pendingPoint;
        }
    }

    bool isWorldgenSettled() const {
        return nearbyStage != NearbyStage.initial && !nearby[published].isBuilding() && radiusCut == 0 && publishedCut == 0 && streamer.isIdle() && streamer.waiting.length == 0 && streamer.scanCursor >= cachedNodes.length;
    }

    Maybe!GraphCastHit castCenterRay() const {
        Ray ray = Ray(Point!float.origin(), Vec4!float([CAMERA_FORWARD.x, CAMERA_FORWARD.y, CAMERA_FORWARD.z, 0]).toNormal());
        return graph.rayCast(cameraPosition, ray, tanhReach);
    }

    Maybe!Material targetMaterial() const {
        Maybe!GraphCastHit hit = castCenterRay();
        if (hit.exists) {
            const(Chunk)* chunk = graph.chunks.at(ChunkSlot(graph.slotOf(hit.value.chunk.node).value, hit.value.chunk.corner));
            Cell cell = hit.value.voxelCoords;
            return Maybe!Material.of(chunk.voxels.at(cellIndex(graph.layout.dimension, cell.x, cell.y, cell.z)));
        } else {
            return Maybe!Material.init;
        }
    }

    bool breakBlock() {
        Maybe!GraphCastHit hit = castCenterRay();
        if (hit.exists) {
            return setVoxel(hit.value.chunk, hit.value.voxelCoords, Material.none);
        } else {
            return false;
        }
    }

    Maybe!Placement placementTarget() const {
        Maybe!GraphCastHit hit = castCenterRay();
        if (hit.exists) {
            return placementBeside(hit.value);
        } else {
            return Maybe!Placement.init;
        }
    }

    Maybe!Placement placementBeside(GraphCastHit hit) const {
        ubyte dimension = graph.layout.dimension;
        Cell coords = hit.voxelCoords;
        int stepped = coords[hit.faceAxis] + hit.faceSign;
        Direction direction = Direction(hit.faceAxis, hit.faceSign);
        Maybe!ChunkId neighbor = graph.chunkNeighborId(hit.chunk, direction);
        if (stepped >= 0 && stepped < dimension) {
            coords[hit.faceAxis] = cast(ubyte) stepped;
            return Maybe!Placement.of(Placement(hit.chunk, coords));
        } else if (neighbor.exists) {
            coords[hit.faceAxis] = boundaryOf(dimension, direction.sign);
            return Maybe!Placement.of(Placement(neighbor.value, neighborAxisMap(hit.chunk.corner, direction).apply(coords)));
        } else {
            return Maybe!Placement.init;
        }
    }

    bool setVoxel(ChunkId chunkId, Cell coords, Material material) {
        ubyte dimension = graph.layout.dimension;
        ChunkSlot slot = ChunkSlot(graph.slotOf(chunkId.node).value, chunkId.corner);
        if (graph.chunks.at(slot).state != ChunkState.populated) {
            return false;
        } else {
            Chunk* chunk = graph.chunks.existing(slot);
            if (chunk.hasDeferredMaterials) {
                graph.resolveMaterials(slot);
            }
            chunk.denseVoxels(dimension)[cellIndex(dimension, coords.x, coords.y, coords.z)] = material;
            chunk.markEdited();
            graph.markChanged(slot);
            Array!ChunkSlot holders;
            graph.touchChunksReading(slot, coords.as!int(), holders);
            foreach (holder; holders.slice()) {
                graph.markChanged(holder);
                graph.resolveIfExposed(holder);
            }
            holders.release();
            return true;
        }
    }
}

float fogReach(float renderRadius) {
    return renderRadius / powf(logf(1.0f / FOG_VISIBILITY_THRESHOLD), 1.0f / FOG_SHARPNESS);
}

float fogVisibility(float distance, float renderRadius) {
    return expf(-powf(distance / fogReach(renderRadius), FOG_SHARPNESS));
}

bool isFarFromOrigin(Motion!float camera) {
    return (camera * Point!float.origin()).v.c[3] > coshf(REBASE_DISTANCE);
}

Deadline phaseDeadline(Pacing pacing, double planned, double leastMilliseconds) {
    if (pacing == Pacing.unbudgeted) {
        return Deadline.init;
    } else {
        return Deadline.at(higherOf(planned, nowMilliseconds() + leastMilliseconds));
    }
}
