module client.world;

import core.stdc.math : coshf;
import client.streaming : Streamer, chunkNeighborId, hasPopulatedNeighbor, resolveIfExposed, resolveMaterials;
import common.coords : CHUNK_DIRECTIONS, ChunkDirection, Coords, boundaryCoord;
import common.graph : Graph, NO_NODE;
import common.margins : CoordsWithMargins, neighborAxisPermutation;
import common.material : Material;
import common.math : MIsometry, MPoint, MVector;
import common.neighbors : chunkNeighborSlot, touchChunksReading;
import common.node : Chunk, ChunkId, ChunkSlot, ChunkState;
import common.proto : Position;
import common.ray : Ray;
import common.raycast.graph : GraphCastHit, rayCast;
import common.traversal : NOT_COLLECTED, NO_DEADLINE, NearbyNode, NearbyScratch, nowMilliseconds;

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
    Streamer streamer;
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
        world.streamer = Streamer.make(isFlat);
        world.cameraPosition = Position.origin();
        world.renderRadius = RENDER_RADIUS;
        world.reach = reach;
        return world;
    }

    void release() {
        streamer.release();
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
        double deadline = nearbyDeadline(isUnbudgeted);
        if (!hasNearby) {
            buildInitialNearby(distance, deadline);
        } else if (cameraNearbyIndex() == NOT_COLLECTED) {
            rebuildNearbyNow(distance);
        } else {
            refreshNearby(distance, deadline);
        }
        streamer.drive(graph, cachedNodes, cameraInNearbyFrame(), renderRadius, nearbyVersion, isUnbudgeted);
    }

    void buildInitialNearby(float distance, double deadline) {
        NearbyScratch* current = &nearby[published];
        if (!current.isBuilding() || cameraNearbyIndex() == NOT_COLLECTED) {
            current.begin(graph, cameraPosition, distance);
            publishedPoint = cameraPosition.local * MPoint!float.origin();
            nearbyVersion += 1;
        }
        current.advance(graph, deadline);
        hasNearby = !current.isBuilding();
        cachedNodes = current.nodes.slice();
    }

    void rebuildNearbyNow(float distance) {
        NearbyScratch* next = &nearby[1 - published];
        next.begin(graph, cameraPosition, distance);
        next.advance(graph, NO_DEADLINE);
        publish(cameraPosition.local * MPoint!float.origin());
    }

    void refreshNearby(float distance, double deadline) {
        NearbyScratch* next = &nearby[1 - published];
        MPoint!float camera = cameraInNearbyFrame() * MPoint!float.origin();
        if (!next.isBuilding() && -publishedPoint.mip(camera.vec) > coshf(NEARBY_PADDING / 2)) {
            next.begin(graph, cameraPosition, distance);
            pendingPoint = cameraPosition.local * MPoint!float.origin();
        }
        if (next.isBuilding()) {
            next.advance(graph, deadline);
            if (!next.isBuilding()) {
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
        return hasNearby && streamer.inFlight == 0 && streamer.scanCursor >= cachedNodes.length;
    }

    GraphCastHit castCenterRay() const {
        Ray ray = Ray(MPoint!float.origin(), MVector!float([0, 0, -1, 0]).normalizedDirection());
        return graph.rayCast(cameraPosition, ray, reach);
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
        Chunk* chunk = graph.chunkAt(slot);
        if (chunk.state != ChunkState.populated) {
            return false;
        } else {
            if (chunk.hasDeferredMaterials) {
                graph.resolveMaterials(slot);
            }
            chunk.voxels.dataMut(dimension)[coords.toIndex(dimension)] = material;
            graph.markChanged(slot);
            foreach (direction; CHUNK_DIRECTIONS) {
                if (coords.data[direction.axis] == boundaryCoord(dimension, direction.sign) && graph.hasPopulatedNeighbor(slot, direction)) {
                    ChunkSlot neighbor = graph.chunkNeighborSlot(slot, direction);
                    chunk.voxels.fixMargins(graph.chunkAt(neighbor).voxels, dimension, chunkId.vertex, direction);
                    graph.markChanged(neighbor);
                    graph.resolveIfExposed(neighbor);
                }
            }
            graph.touchChunksReading(slot, CoordsWithMargins.fromCoords(coords));
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
