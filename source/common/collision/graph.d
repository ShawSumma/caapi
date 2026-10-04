module common.collision.graph;

import core.stdc.math : atanhf, coshf, fminf;
import common.collision.chunk : ChunkCollisionHit, MAX_FEATURE_SURFACES, SweptShape, chunkShapeCast, isCapsuleIntersectingVoxel;
import common.coords : Coords;
import common.dodeca : BOUNDING_SPHERE_RADIUS, CHUNK_BOUNDING_SPHERE_RADIUS, SIDE_COUNT, Side, VERTEX_COUNT, Vertex, chunkBoundingSphereCenter, nodeToDual, reflection;
import common.graph : Graph, NO_SLOT;
import common.math : MIsometry, MPoint, MVector, isNan;
import common.node : Chunk, ChunkId, ChunkSlot, ChunkState;
import common.position : Position;
import common.ray : MAX_TANH_DISTANCE, Ray;

enum uint REGION_MAX_NODES = 64;
enum uint SHAPE_CAST_MAX_NODES = 128;

struct Capsule {
    float[3] axis;
    float radius;
    float halfHeight;
    float skin;

    SweptShape swept(MIsometry!float localToDual) const {
        MVector!float dualAxis = localToDual * MVector!float([axis[0], axis[1], axis[2], 0]);
        return SweptShape(dualAxis, radius, halfHeight, skin);
    }
}

struct GraphCollisionHit {
    ChunkId chunk;
    MVector!float normal;
    MVector!float[MAX_FEATURE_SURFACES] surfaces;
    float stopDistance = float.nan;
    float gap;
    uint surfaceCount;
    bool isLowestSection;

    static GraphCollisionHit fromChunkHit(ChunkCollisionHit chunkHit, MIsometry!float dualToLocal, ChunkId chunk) {
        MVector!float[MAX_FEATURE_SURFACES] surfaces;
        foreach (i; 0 .. chunkHit.surfaceCount) {
            surfaces[i] = dualToLocal * chunkHit.surfaces[i];
        }
        return GraphCollisionHit(chunk, dualToLocal * chunkHit.normal, surfaces, chunkHit.stopDistance, chunkHit.gap, chunkHit.surfaceCount, chunkHit.isLowestSection);
    }

    bool isHit() const {
        return !isNan(stopDistance);
    }
}

struct NodeVisit {
    uint slot;
    MIsometry!float inverse;
}

bool isVisited(const(NodeVisit)[] visits, uint slot) {
    size_t index = 0;
    while (index < visits.length && visits[index].slot != slot) {
        index += 1;
    }
    return index < visits.length;
}

struct VisitQueue(uint capacity) {
    NodeVisit[capacity] visits = void;
    uint count;
    uint front;

    static VisitQueue fromSlot(uint slot) {
        VisitQueue queue;
        queue.visits[0] = NodeVisit(slot, MIsometry!float.identity());
        queue.count = 1;
        return queue;
    }

    bool hasNext() const {
        return front < count;
    }

    NodeVisit current() const {
        return visits[front];
    }

    bool isVisited(uint slot) const {
        return visits[0 .. count].isVisited(slot);
    }

    bool isUnvisitedWithin(ref const Graph graph, NodeVisit visit, Side side, MVector!float point, float nodeThreshold) const {
        uint neighbor = graph.neighborSlot(visit.slot, side);
        return neighbor != NO_SLOT && !isVisited(neighbor) && !((side.reflection * visit.inverse * point).data[3] > nodeThreshold);
    }

    uint unvisitedCount(ref const Graph graph, NodeVisit visit, MVector!float point, float nodeThreshold) const {
        uint result = 0;
        foreach (sideIndex; 0 .. SIDE_COUNT) {
            if (isUnvisitedWithin(graph, visit, cast(Side) sideIndex, point, nodeThreshold)) {
                result += 1;
            }
        }
        return result;
    }

    bool hasRoomFor(ref const Graph graph, NodeVisit visit, MVector!float point, float nodeThreshold) const {
        return count + unvisitedCount(graph, visit, point, nodeThreshold) <= capacity;
    }

    void expand(ref const Graph graph, NodeVisit visit, MVector!float point, float nodeThreshold) {
        foreach (sideIndex; 0 .. SIDE_COUNT) {
            Side side = cast(Side) sideIndex;
            if (count < capacity && isUnvisitedWithin(graph, visit, side, point, nodeThreshold)) {
                visits[count] = NodeVisit(graph.neighborSlot(visit.slot, side), side.reflection * visit.inverse);
                count += 1;
            }
        }
        front += 1;
    }
}

bool isMissingWithin(ref const Graph graph, NodeVisit visit, Side side, MVector!float point, float nodeThreshold) {
    return graph.neighborSlot(visit.slot, side) == NO_SLOT && !((side.reflection * visit.inverse * point).data[3] > nodeThreshold);
}

bool hasNeighborsWithin(ref const Graph graph, NodeVisit visit, MVector!float point, float nodeThreshold) {
    uint side = 0;
    while (side < SIDE_COUNT && !graph.isMissingWithin(visit, cast(Side) side, point, nodeThreshold)) {
        side += 1;
    }
    return side == SIDE_COUNT;
}

bool isUnpopulatedWithin(ref const Graph graph, NodeVisit visit, Vertex vertex, MVector!float localPoint, float chunkThreshold) {
    return !(-localPoint.mip(vertex.chunkBoundingSphereCenter.vec) > chunkThreshold) && graph.chunkAt(ChunkSlot(visit.slot, vertex)).state != ChunkState.populated;
}

bool isVisitPopulated(ref const Graph graph, NodeVisit visit, MVector!float point, float chunkThreshold) {
    MVector!float localPoint = visit.inverse * point;
    uint vertex = 0;
    while (vertex < VERTEX_COUNT && !graph.isUnpopulatedWithin(visit, cast(Vertex) vertex, localPoint, chunkThreshold)) {
        vertex += 1;
    }
    return vertex == VERTEX_COUNT;
}

bool isRegionPopulated(ref const Graph graph, Position position, float distance) {
    float nodeThreshold = coshf(distance + BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS);
    float chunkThreshold = coshf(distance + CHUNK_BOUNDING_SPHERE_RADIUS);
    MVector!float point = (position.local * MPoint!float.origin()).vec;
    VisitQueue!REGION_MAX_NODES queue = VisitQueue!REGION_MAX_NODES.fromSlot(graph.slotOf(position.node));
    while (queue.hasNext() && graph.isVisitPopulated(queue.current(), point, chunkThreshold) && graph.hasNeighborsWithin(queue.current(), point, nodeThreshold) && queue.hasRoomFor(graph, queue.current(), point, nodeThreshold)) {
        queue.expand(graph, queue.current(), point, nodeThreshold);
    }
    return !queue.hasNext();
}

GraphCollisionHit shapeCast(ref const Graph graph, Capsule capsule, Position position, Ray ray, float tanhDistance) {
    GraphCollisionHit hit;
    Ray nodeRay = ray.transformedBy(position.local);
    float reach = atanhf(fminf(tanhDistance, MAX_TANH_DISTANCE)) + capsule.radius + capsule.halfHeight;
    float nodeThreshold = coshf(reach + BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS);
    float chunkThreshold = coshf(reach + CHUNK_BOUNDING_SPHERE_RADIUS);
    VisitQueue!SHAPE_CAST_MAX_NODES queue = VisitQueue!SHAPE_CAST_MAX_NODES.fromSlot(graph.slotOf(position.node));
    while (queue.hasNext()) {
        NodeVisit visit = queue.current();
        Ray localRay = nodeRay.transformedBy(visit.inverse);
        foreach (vertexIndex; 0 .. VERTEX_COUNT) {
            Vertex vertex = cast(Vertex) vertexIndex;
            const(Chunk)* chunk = graph.chunkAt(ChunkSlot(visit.slot, vertex));
            if (chunk.state == ChunkState.populated && !(-localRay.position.vec.mip(vertex.chunkBoundingSphereCenter.vec) > chunkThreshold)) {
                MIsometry!float localToDual = vertex.nodeToDual * visit.inverse * position.local;
                ChunkCollisionHit chunkHit = chunkShapeCast(capsule.swept(localToDual), chunk.voxels, graph.layout, localRay.transformedBy(vertex.nodeToDual), tanhDistance);
                if (chunkHit.isHit() && (!hit.isHit() || chunkHit.stopDistance < hit.stopDistance)) {
                    hit = GraphCollisionHit.fromChunkHit(chunkHit, localToDual.inverse(), ChunkId(graph.idAt(visit.slot), vertex));
                }
            }
        }
        queue.expand(graph, visit, nodeRay.position.vec, nodeThreshold);
    }
    return hit;
}

bool isCapsuleOverlappingVoxel(ref const Graph graph, Capsule capsule, Position position, ChunkId chunkId, Coords coords) {
    uint targetSlot = graph.slotOf(chunkId.node);
    float nodeThreshold = coshf(capsule.radius + capsule.halfHeight + BOUNDING_SPHERE_RADIUS);
    MVector!float point = (position.local * MPoint!float.origin()).vec;
    VisitQueue!REGION_MAX_NODES queue = VisitQueue!REGION_MAX_NODES.fromSlot(graph.slotOf(position.node));
    while (queue.hasNext() && queue.current().slot != targetSlot && queue.hasRoomFor(graph, queue.current(), point, nodeThreshold)) {
        queue.expand(graph, queue.current(), point, nodeThreshold);
    }
    if (!queue.hasNext()) {
        return false;
    } else if (queue.current().slot == targetSlot) {
        MIsometry!float localToDual = chunkId.vertex.nodeToDual * queue.current().inverse * position.local;
        return isCapsuleIntersectingVoxel(capsule.swept(localToDual), graph.layout, coords.data, localToDual * MPoint!float.origin());
    } else {
        return true;
    }
}
