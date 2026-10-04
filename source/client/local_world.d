module client.local_world;

import core.stdc.math : coshf;
import client.worldgen_driver : WorldgenDriver, chunkAt, createWorldgenDriver, driveWorldgen, getChunkNeighbor, populatedNeighbor, releaseWorldgenDriver, resolveIfExposed, resolveMaterials;
import common.chunk_neighbors : chunkNeighborSlot, touchChunksReading;
import common.collision_math : Ray;
import common.graph : Graph, NO_NODE, NodeId, createGraph;
import common.graph_ray_casting : GraphCastHit, rayCast;
import common.margins : fixMargins, neighborAxisPermutation, withMargins;
import common.math : MIsometry, MPoint, MVector, isNan;
import common.node : Chunk, ChunkId, ChunkSlot, ChunkState;
import common.proto : Position, originPosition;
import common.traversal : NOT_COLLECTED, NO_DEADLINE, NearbyNode, NearbyScratch, beginNearby, continueNearby, nowMilliseconds;
import common.voxel_math : CHUNK_DIRECTIONS, ChunkDirection, Coords, boundaryCoord;
import common.world : Material;

enum float NEARBY_PADDING = 0.05f;
enum float RENDER_RADIUS = 4.5f;
enum double NEARBY_BUDGET_MILLISECONDS = 2.0;

struct LocalWorld {
    Graph graph;
    WorldgenDriver worldgenDriver;
    NearbyScratch[2] nearby;
    Position cameraPosition;
    MPoint!float publishedPoint;
    MPoint!float pendingPoint;
    NearbyNode[] cachedNodes;
    float renderRadius;
    float reach;
    uint published;
    uint nearbyVersion;
    uint epoch;
    bool hasNearby;
}

LocalWorld createLocalWorld(ubyte dimension, bool flatWorldgen, float reach) {
    LocalWorld world;
    world.graph = createGraph(dimension);
    world.worldgenDriver = createWorldgenDriver(flatWorldgen);
    world.cameraPosition = originPosition();
    world.renderRadius = RENDER_RADIUS;
    world.reach = reach;
    return world;
}

void releaseLocalWorld(LocalWorld* world) {
    releaseWorldgenDriver(&world.worldgenDriver);
    world.nearby[0].release();
    world.nearby[1].release();
    world.graph.release();
}

uint cameraNearbyIndex(const(LocalWorld)* world) {
    return world.nearby[world.published].indexOf(world.graph.slotOf(world.cameraPosition.node));
}

MIsometry!float cameraInNearbyFrame(const(LocalWorld)* world) {
    return world.nearby[world.published].nodes.ptr[cameraNearbyIndex(world)].transform * world.cameraPosition.local;
}

void updateLocalWorld(LocalWorld* world, bool unbudgeted) {
    float distance = world.renderRadius + NEARBY_PADDING;
    double deadline = nowMilliseconds() + NEARBY_BUDGET_MILLISECONDS;
    if (unbudgeted) {
        deadline = NO_DEADLINE;
    }
    NearbyScratch* current = &world.nearby[world.published];
    NearbyScratch* next = &world.nearby[1 - world.published];
    if (!world.hasNearby && (!current.building || cameraNearbyIndex(world) == NOT_COLLECTED)) {
        beginNearby(current, &world.graph, world.cameraPosition.node, world.cameraPosition.local, distance);
        world.publishedPoint = world.cameraPosition.local * MPoint!float.origin();
    }
    if (!world.hasNearby) {
        world.hasNearby = continueNearby(current, &world.graph, deadline);
        world.cachedNodes = current.nodes.slice();
        world.nearbyVersion += 1;
    } else if (cameraNearbyIndex(world) == NOT_COLLECTED) {
        beginNearby(next, &world.graph, world.cameraPosition.node, world.cameraPosition.local, distance);
        continueNearby(next, &world.graph, NO_DEADLINE);
        publishNearby(world, world.cameraPosition.local * MPoint!float.origin());
    } else {
        MPoint!float camera = cameraInNearbyFrame(world) * MPoint!float.origin();
        if (!next.building && -world.publishedPoint.mip(camera.vec) > coshf(NEARBY_PADDING / 2)) {
            beginNearby(next, &world.graph, world.cameraPosition.node, world.cameraPosition.local, distance);
            world.pendingPoint = world.cameraPosition.local * MPoint!float.origin();
        }
        if (next.building && continueNearby(next, &world.graph, deadline)) {
            publishNearby(world, world.pendingPoint);
        }
    }
    driveWorldgen(&world.worldgenDriver, world.cachedNodes, cameraInNearbyFrame(world), world.renderRadius, &world.graph, world.nearbyVersion, unbudgeted);
}

void publishNearby(LocalWorld* world, MPoint!float point) {
    world.published = 1 - world.published;
    world.cachedNodes = world.nearby[world.published].nodes.slice();
    world.publishedPoint = point;
    world.nearbyVersion += 1;
}

bool worldgenSettled(const(LocalWorld)* world) {
    return world.hasNearby && world.worldgenDriver.inFlight == 0 && world.worldgenDriver.scanCursor >= world.cachedNodes.length;
}

GraphCastHit castCenterRay(const(LocalWorld)* world) {
    Ray ray = Ray(MPoint!float.origin(), MVector!float(0, 0, -1, 0).normalizedDirection());
    return rayCast(&world.graph, world.cameraPosition.node, world.cameraPosition.local, ray, world.reach);
}

bool breakBlock(LocalWorld* world) {
    GraphCastHit hit = castCenterRay(world);
    bool result = false;
    if (!isNan(hit.tanhDistance)) {
        result = setVoxel(world, hit.chunk, hit.voxelCoords, Material.Void);
    }
    return result;
}

struct Placement {
    ChunkId chunk;
    Coords coords;
    bool found;
}

Placement placementTarget(LocalWorld* world) {
    GraphCastHit hit = castCenterRay(world);
    Placement result;
    if (!isNan(hit.tanhDistance)) {
        ubyte dimension = world.graph.layout.dimension;
        Coords coords = hit.voxelCoords;
        int stepped = coords.data[hit.faceAxis] + hit.faceSign;
        if (stepped >= 0 && stepped < dimension) {
            coords.data[hit.faceAxis] = cast(ubyte) stepped;
            result = Placement(hit.chunk, coords, true);
        } else {
            ChunkDirection direction = ChunkDirection(hit.faceAxis, hit.faceSign);
            ChunkId neighbor = getChunkNeighbor(&world.graph, hit.chunk, direction);
            if (neighbor.node != NO_NODE) {
                coords.data[hit.faceAxis] = boundaryCoord(dimension, direction.sign);
                result = Placement(neighbor, neighborAxisPermutation(hit.chunk.vertex, direction).apply(coords), true);
            }
        }
    }
    return result;
}

bool setVoxel(LocalWorld* world, ChunkId chunkId, Coords coords, Material material) {
    ubyte dimension = world.graph.layout.dimension;
    ChunkSlot slot = ChunkSlot(world.graph.slotOf(chunkId.node), chunkId.vertex);
    Chunk* chunk = chunkAt(&world.graph, slot);
    bool result = chunk.state == ChunkState.Populated;
    if (result) {
        if (chunk.materialsDeferred) {
            resolveMaterials(&world.graph, slot);
        }
        chunk.voxels.dataMut(dimension)[coords.toIndex(dimension)] = material;
        world.graph.markChanged(slot);
        foreach (direction; CHUNK_DIRECTIONS) {
            Chunk* neighbor = populatedNeighbor(&world.graph, slot, direction);
            if (coords.data[direction.axis] == boundaryCoord(dimension, direction.sign) && neighbor !is null) {
                fixMargins(dimension, chunkId.vertex, &chunk.voxels, direction, &neighbor.voxels);
                world.graph.markChanged(chunkNeighborSlot(&world.graph, slot, direction));
                resolveIfExposed(&world.graph, chunkNeighborSlot(&world.graph, slot, direction));
            }
        }
        touchChunksReading(&world.graph, slot, withMargins(coords));
    }
    return result;
}
