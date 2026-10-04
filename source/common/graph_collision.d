module common.graph_collision;

import core.stdc.math : atanhf, coshf, fminf;
import common.chunk_collision : ChunkCollisionHit, MAX_FEATURE_SURFACES, SweptShape, chunkShapeCast, isCapsuleIntersectingVoxel;
import common.collision_math : MAX_TANH_DISTANCE, Ray;
import common.dodeca : BOUNDING_SPHERE_RADIUS, CHUNK_BOUNDING_SPHERE_RADIUS, SIDE_COUNT, Side, VERTEX_COUNT, Vertex, chunkBoundingSphereCenter, nodeToDual, reflection;
import common.graph : Graph, NO_SLOT;
import common.math : MIsometry, MPoint, MVector, isNan;
import common.node : Chunk, ChunkId, ChunkSlot, ChunkState;
import common.proto : Position;
import common.voxel_math : Coords;

enum uint REGION_MAX_NODES = 64;
enum uint SHAPE_CAST_MAX_NODES = 128;

struct Capsule {
    float[3] axis;
    float radius;
    float halfHeight;
    float skin;

    SweptShape swept(MIsometry!float localToDual) const {
        MVector!float dualAxis = localToDual * MVector!float(axis[0], axis[1], axis[2], 0);
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

    bool isHit() const {
        return !isNan(stopDistance);
    }
}

struct NodeVisit {
    uint slot;
    MIsometry!float inverse;
}

bool isVisited(const(NodeVisit)[] visits, uint slot) {
    foreach (visit; visits) {
        if (visit.slot == slot) {
            return true;
        }
    }
    return false;
}

bool isRegionPopulated(const(Graph)* graph, Position position, float distance) {
    float nodeThreshold = coshf(distance + BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS);
    float chunkThreshold = coshf(distance + CHUNK_BOUNDING_SPHERE_RADIUS);
    MVector!float point = (position.local * MPoint!float.origin()).vec;
    NodeVisit[REGION_MAX_NODES] visits = void;
    uint count = 1;
    uint front = 0;
    visits[0] = NodeVisit(graph.slotOf(position.node), MIsometry!float.identity());
    while (front < count) {
        NodeVisit visit = visits[front];
        front += 1;
        MVector!float localPoint = visit.inverse * point;
        foreach (vertexIndex; 0 .. VERTEX_COUNT) {
            Vertex vertex = cast(Vertex) vertexIndex;
            if (!(-localPoint.mip(vertex.chunkBoundingSphereCenter.vec) > chunkThreshold) && graph.chunkAt(ChunkSlot(visit.slot, vertex)).state != ChunkState.Populated) {
                return false;
            }
        }
        foreach (sideIndex; 0 .. SIDE_COUNT) {
            Side side = cast(Side) sideIndex;
            uint neighbor = graph.neighborSlot(visit.slot, side);
            MIsometry!float neighborInverse = side.reflection * visit.inverse;
            if (!((neighborInverse * point).data[3] > nodeThreshold)) {
                if (neighbor == NO_SLOT || (!isVisited(visits[0 .. count], neighbor) && count == REGION_MAX_NODES)) {
                    return false;
                } else if (!isVisited(visits[0 .. count], neighbor)) {
                    visits[count] = NodeVisit(neighbor, neighborInverse);
                    count += 1;
                }
            }
        }
    }
    return true;
}

GraphCollisionHit shapeCast(Capsule capsule, const(Graph)* graph, Position position, Ray ray, float tanhDistance) {
    GraphCollisionHit hit;
    Ray nodeRay = ray.transformedBy(position.local);
    float reach = atanhf(fminf(tanhDistance, MAX_TANH_DISTANCE)) + capsule.radius + capsule.halfHeight;
    float nodeThreshold = coshf(reach + BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS);
    float chunkThreshold = coshf(reach + CHUNK_BOUNDING_SPHERE_RADIUS);
    NodeVisit[SHAPE_CAST_MAX_NODES] visits = void;
    uint count = 1;
    uint front = 0;
    visits[0] = NodeVisit(graph.slotOf(position.node), MIsometry!float.identity());
    while (front < count) {
        NodeVisit visit = visits[front];
        front += 1;
        Ray localRay = nodeRay.transformedBy(visit.inverse);
        foreach (vertexIndex; 0 .. VERTEX_COUNT) {
            Vertex vertex = cast(Vertex) vertexIndex;
            const(Chunk)* chunk = graph.chunkAt(ChunkSlot(visit.slot, vertex));
            if (chunk.state == ChunkState.Populated && !(-localRay.position.vec.mip(vertex.chunkBoundingSphereCenter.vec) > chunkThreshold)) {
                MIsometry!float localToDual = vertex.nodeToDual * visit.inverse * position.local;
                ChunkCollisionHit chunkHit = chunkShapeCast(capsule.swept(localToDual), &chunk.voxels, graph.layout, localRay.transformedBy(vertex.nodeToDual), tanhDistance);
                if (chunkHit.isHit() && (!hit.isHit() || chunkHit.stopDistance < hit.stopDistance)) {
                    hit = graphHit(chunkHit, localToDual.inverse(), ChunkId(graph.idAt(visit.slot), vertex));
                }
            }
        }
        foreach (sideIndex; 0 .. SIDE_COUNT) {
            Side side = cast(Side) sideIndex;
            uint neighbor = graph.neighborSlot(visit.slot, side);
            MIsometry!float neighborInverse = side.reflection * visit.inverse;
            if (neighbor != NO_SLOT && !isVisited(visits[0 .. count], neighbor) && count < SHAPE_CAST_MAX_NODES &&!((neighborInverse * nodeRay.position.vec).data[3] > nodeThreshold)) {
                visits[count] = NodeVisit(neighbor, neighborInverse);
                count += 1;
            }
        }
    }
    return hit;
}

GraphCollisionHit graphHit(ChunkCollisionHit chunkHit, MIsometry!float dualToLocal, ChunkId chunk) {
    GraphCollisionHit hit;
    hit.chunk = chunk;
    hit.stopDistance = chunkHit.stopDistance;
    hit.gap = chunkHit.gap;
    hit.normal = dualToLocal * chunkHit.normal;
    foreach (i; 0 .. chunkHit.surfaceCount) {
        hit.surfaces[i] = dualToLocal * chunkHit.surfaces[i];
    }
    hit.surfaceCount = chunkHit.surfaceCount;
    hit.isLowestSection = chunkHit.isLowestSection;
    return hit;
}

bool isCapsuleOverlappingVoxel(Capsule capsule, const(Graph)* graph, Position position, ChunkId chunkId, Coords coords) {
    uint targetSlot = graph.slotOf(chunkId.node);
    float nodeThreshold = coshf(capsule.radius + capsule.halfHeight + BOUNDING_SPHERE_RADIUS);
    MVector!float point = (position.local * MPoint!float.origin()).vec;
    NodeVisit[REGION_MAX_NODES] visits = void;
    uint count = 1;
    uint front = 0;
    visits[0] = NodeVisit(graph.slotOf(position.node), MIsometry!float.identity());
    while (front < count) {
        NodeVisit visit = visits[front];
        front += 1;
        if (visit.slot == targetSlot) {
            MIsometry!float localToDual = chunkId.vertex.nodeToDual * visit.inverse * position.local;
            return isCapsuleIntersectingVoxel(capsule.swept(localToDual), graph.layout, coords.data, localToDual * MPoint!float.origin());
        }
        foreach (sideIndex; 0 .. SIDE_COUNT) {
            Side side = cast(Side) sideIndex;
            uint neighbor = graph.neighborSlot(visit.slot, side);
            MIsometry!float neighborInverse = side.reflection * visit.inverse;
            if (neighbor != NO_SLOT && !isVisited(visits[0 .. count], neighbor) && !((neighborInverse * point).data[3] > nodeThreshold)) {
                if (count == REGION_MAX_NODES) {
                    return true;
                } else {
                    visits[count] = NodeVisit(neighbor, neighborInverse);
                    count += 1;
                }
            }
        }
    }
    return false;
}
