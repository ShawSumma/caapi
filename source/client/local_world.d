module client.local_world;

import core.stdc.math : coshf;
import client.worldgen_driver : WorldgenDriver, chunkNeighborId, hasPopulatedNeighbor, resolveIfExposed, resolveMaterials;
import common.chunk_neighbors : chunkNeighborSlot, touchChunksReading;
import common.collision_math : Ray;
import common.graph : Graph, NO_NODE;
import common.graph_ray_casting : GraphCastHit, rayCast;
import common.margins : neighborAxisPermutation, withMargins;
import common.math : MIsometry, MPoint, MVector;
import common.node : Chunk, ChunkId, ChunkSlot, ChunkState;
import common.proto : Position;
import common.traversal : NOT_COLLECTED, NO_DEADLINE, NearbyNode, NearbyScratch, nowMilliseconds;
import common.voxel_math : CHUNK_DIRECTIONS, ChunkDirection, Coords, boundaryCoord;
import common.world : Material;

enum float NEARBY_PADDING = 0.05f;
enum float RENDER_RADIUS = 4.5f;
enum double NEARBY_BUDGET_MILLISECONDS = 2.0;

struct Placement {
    ChunkId chunk;
    Coords coords;
    bool isFound;
}

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

    static LocalWorld make(ubyte dimension, bool isFlat, float reach) {
        LocalWorld world;
        world.graph = Graph.make(dimension);
        world.worldgenDriver = WorldgenDriver.make(isFlat);
        world.cameraPosition = Position.origin();
        world.renderRadius = RENDER_RADIUS;
        world.reach = reach;
        return world;
    }

    void release() {
        worldgenDriver.release();
        nearby[0].release();
        nearby[1].release();
        graph.release();
    }

    uint cameraNearbyIndex() const {
        return nearby[published].indexOf(graph.slotOf(cameraPosition.node));
    }

    MIsometry!float cameraInNearbyFrame() const {
        return nearby[published].nodes.ptr[cameraNearbyIndex()].transform * cameraPosition.local;
    }

    void update(bool isUnbudgeted) {
        float distance = renderRadius + NEARBY_PADDING;
        immutable double deadline = nearbyDeadline(isUnbudgeted);
        if (!hasNearby) {
            buildInitialNearby(distance, deadline);
        } else if (cameraNearbyIndex() == NOT_COLLECTED) {
            rebuildNearbyNow(distance);
        } else {
            refreshNearby(distance, deadline);
        }
        worldgenDriver.drive(cachedNodes, cameraInNearbyFrame(), renderRadius, &graph, nearbyVersion, isUnbudgeted);
    }

    void buildInitialNearby(float distance, double deadline) {
        NearbyScratch* current = &nearby[published];
        if (!current.isBuilding || cameraNearbyIndex() == NOT_COLLECTED) {
            current.begin(&graph, cameraPosition, distance);
            publishedPoint = cameraPosition.local * MPoint!float.origin();
            nearbyVersion += 1;
        }
        immutable bool isComplete = current.advance(&graph, deadline);
        hasNearby = isComplete;
        cachedNodes = current.nodes.slice();
    }

    void rebuildNearbyNow(float distance) {
        NearbyScratch* next = &nearby[1 - published];
        next.begin(&graph, cameraPosition, distance);
        next.advance(&graph, NO_DEADLINE);
        publish(cameraPosition.local * MPoint!float.origin());
    }

    void refreshNearby(float distance, double deadline) {
        NearbyScratch* next = &nearby[1 - published];
        MPoint!float camera = cameraInNearbyFrame() * MPoint!float.origin();
        if (!next.isBuilding && -publishedPoint.mip(camera.vec) > coshf(NEARBY_PADDING / 2)) {
            next.begin(&graph, cameraPosition, distance);
            pendingPoint = cameraPosition.local * MPoint!float.origin();
        }
        if (next.isBuilding) {
            immutable bool isComplete = next.advance(&graph, deadline);
            if (isComplete) {
                publish(pendingPoint);
            }
        }
    }

    void publish(MPoint!float point) {
        published = 1 - published;
        cachedNodes = nearby[published].nodes.slice();
        publishedPoint = point;
        nearbyVersion += 1;
    }

    bool isWorldgenSettled() const {
        return hasNearby && worldgenDriver.inFlight == 0 && worldgenDriver.scanCursor >= cachedNodes.length;
    }

    GraphCastHit castCenterRay() const {
        Ray ray = Ray(MPoint!float.origin(), MVector!float(0, 0, -1, 0).normalizedDirection());
        return rayCast(&graph, cameraPosition, ray, reach);
    }

    bool breakBlock() {
        GraphCastHit hit = castCenterRay();
        if (hit.isHit()) {
            return setVoxel(hit.chunk, hit.voxelCoords, Material.Void);
        } else {
            return false;
        }
    }

    Placement placementTarget() const {
        GraphCastHit hit = castCenterRay();
        ubyte dimension = graph.layout.dimension;
        Coords coords = hit.voxelCoords;
        int stepped = coords.data[hit.faceAxis] + hit.faceSign;
        ChunkDirection direction = ChunkDirection(hit.faceAxis, hit.faceSign);
        if (!hit.isHit()) {
            return Placement.init;
        } else if (stepped >= 0 && stepped < dimension) {
            coords.data[hit.faceAxis] = cast(ubyte) stepped;
            return Placement(hit.chunk, coords, true);
        } else {
            ChunkId neighbor = chunkNeighborId(&graph, hit.chunk, direction);
            coords.data[hit.faceAxis] = boundaryCoord(dimension, direction.sign);
            if (neighbor.node == NO_NODE) {
                return Placement.init;
            } else {
                return Placement(neighbor, neighborAxisPermutation(hit.chunk.vertex, direction).apply(coords), true);
            }
        }
    }

    bool setVoxel(ChunkId chunkId, Coords coords, Material material) {
        ubyte dimension = graph.layout.dimension;
        ChunkSlot slot = ChunkSlot(graph.slotOf(chunkId.node), chunkId.vertex);
        Chunk* chunk = graph.chunkAt(slot);
        if (chunk.state != ChunkState.Populated) {
            return false;
        } else {
            if (chunk.hasDeferredMaterials) {
                resolveMaterials(&graph, slot);
            }
            chunk.voxels.dataMut(dimension)[coords.toIndex(dimension)] = material;
            graph.markChanged(slot);
            foreach (direction; CHUNK_DIRECTIONS) {
                if (coords.data[direction.axis] == boundaryCoord(dimension, direction.sign) && hasPopulatedNeighbor(&graph, slot, direction)) {
                    ChunkSlot neighbor = chunkNeighborSlot(&graph, slot, direction);
                    chunk.voxels.fixMargins(&graph.chunkAt(neighbor).voxels, dimension, chunkId.vertex, direction);
                    graph.markChanged(neighbor);
                    resolveIfExposed(&graph, neighbor);
                }
            }
            touchChunksReading(&graph, slot, withMargins(coords));
            return true;
        }
    }
}

double nearbyDeadline(bool isUnbudgeted) {
    if (isUnbudgeted) {
        return NO_DEADLINE;
    } else {
        return nowMilliseconds() + NEARBY_BUDGET_MILLISECONDS;
    }
}
