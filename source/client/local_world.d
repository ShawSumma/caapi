module client.local_world;

import core.stdc.math : coshf;
import client.worldgen_driver : WorldgenDriver, createWorldgenDriver, driveWorldgen, getChunkNeighbor, releaseWorldgenDriver;
import common.collision_math : Ray;
import common.graph : Graph, NO_NODE, NodeId, ROOT_NODE, createGraph;
import common.graph_ray_casting : GraphCastHit, rayCast;
import common.margins : fixMargins, neighborAxisPermutation;
import common.math : MIsometry, MPoint, MVector, isNan;
import common.node : Chunk, ChunkId, ChunkState;
import common.proto : Position;
import common.traversal : DEFAULT_NODE_CREATION_BUDGET, NearbyNode, NearbyScratch, ensureAndCollectNearby;
import common.voxel_math : CHUNK_DIRECTIONS, ChunkDirection, Coords, boundaryCoord;
import common.world : Material;

enum float NEARBY_PADDING = 0.05f;
enum float RENDER_RADIUS = 4.5f;
enum float SPAWN_HEIGHT = 1.4f;

struct LocalWorld {
    Graph graph;
    WorldgenDriver worldgenDriver;
    NearbyScratch nearbyScratch;
    Position cameraPosition;
    MPoint!float lastNearbyPoint;
    NearbyNode[] cachedNodes;
    NodeId lastNearbyNode;
    float renderRadius;
    float reach;
    uint nearbyVersion;
    bool hasNearby;
}

LocalWorld createLocalWorld(ubyte dimension, bool flatWorldgen, float reach) {
    LocalWorld world;
    world.graph = createGraph(dimension);
    world.worldgenDriver = createWorldgenDriver(flatWorldgen);
    world.cameraPosition = Position(ROOT_NODE, MIsometry!float.translationAlong([0.0f, SPAWN_HEIGHT, 0.0f]));
    world.renderRadius = RENDER_RADIUS;
    world.reach = reach;
    return world;
}

void releaseLocalWorld(LocalWorld* world) {
    releaseWorldgenDriver(&world.worldgenDriver);
    world.nearbyScratch.release();
    world.graph.release();
}

void updateLocalWorld(LocalWorld* world) {
    MPoint!float cameraPoint = world.cameraPosition.local * MPoint!float.origin();
    if (!world.hasNearby || world.cameraPosition.node != world.lastNearbyNode || world.nearbyScratch.creationCapped || -world.lastNearbyPoint.mip(cameraPoint.vec) > coshf(NEARBY_PADDING)) {
        world.cachedNodes = ensureAndCollectNearby(&world.nearbyScratch, &world.graph, world.cameraPosition.node, world.cameraPosition.local, world.renderRadius + NEARBY_PADDING, DEFAULT_NODE_CREATION_BUDGET);
        world.lastNearbyNode = world.cameraPosition.node;
        world.lastNearbyPoint = cameraPoint;
        world.hasNearby = true;
        world.nearbyVersion += 1;
    }
    driveWorldgen(&world.worldgenDriver, world.cachedNodes, world.cameraPosition.local, world.renderRadius, &world.graph, world.nearbyVersion);
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

bool placeBlock(LocalWorld* world, Material material) {
    GraphCastHit hit = castCenterRay(world);
    bool result = false;
    if (!isNan(hit.tanhDistance)) {
        ubyte dimension = world.graph.layout.dimension;
        Coords coords = hit.voxelCoords;
        int stepped = coords.data[hit.faceAxis] + hit.faceSign;
        if (stepped >= 0 && stepped < dimension) {
            coords.data[hit.faceAxis] = cast(ubyte) stepped;
            result = setVoxel(world, hit.chunk, coords, material);
        } else {
            ChunkDirection direction = ChunkDirection(hit.faceAxis, hit.faceSign);
            ChunkId neighbor = getChunkNeighbor(&world.graph, hit.chunk, direction);
            if (neighbor.node != NO_NODE) {
                coords.data[hit.faceAxis] = boundaryCoord(dimension, direction.sign);
                coords = neighborAxisPermutation(hit.chunk.vertex, direction).apply(coords);
                result = setVoxel(world, neighbor, coords, material);
            }
        }
    }
    return result;
}

bool setVoxel(LocalWorld* world, ChunkId chunkId, Coords coords, Material material) {
    ubyte dimension = world.graph.layout.dimension;
    Chunk* chunk = &world.graph.nodeOf(chunkId.node).chunks[chunkId.vertex];
    bool result = chunk.state == ChunkState.Populated;
    if (result) {
        chunk.voxels.dataMut(dimension)[coords.toIndex(dimension)] = material;
        chunk.generation += 1;
        foreach (direction; CHUNK_DIRECTIONS) {
            ChunkId neighbor = getChunkNeighbor(&world.graph, chunkId, direction);
            if (coords.data[direction.axis] == boundaryCoord(dimension, direction.sign) && neighbor.node != NO_NODE) {
                Chunk* neighborChunk = &world.graph.nodeOf(neighbor.node).chunks[neighbor.vertex];
                if (neighborChunk.state == ChunkState.Populated) {
                    fixMargins(dimension, chunkId.vertex, &chunk.voxels, direction, &neighborChunk.voxels);
                    neighborChunk.generation += 1;
                }
            }
        }
    }
    return result;
}
