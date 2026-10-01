module common.graph_collision;

import core.stdc.math : atanhf, coshf;
import common.chunk_collision : ChunkCollisionHit, MAX_FEATURE_SURFACES, SweptShape, capsuleIntersectsVoxel, chunkShapeCast;
import common.collision_math : MAX_TANH_DISTANCE, Ray, transformRay;
import common.dodeca : BOUNDING_SPHERE_RADIUS, CHUNK_BOUNDING_SPHERE_RADIUS, SIDE_COUNT, Side, VERTEX_COUNT, Vertex, sideReflection, vertexChunkBoundingSphereCenter, vertexNodeToDual;
import common.graph : Graph, NO_SLOT, NodeId;
import common.math : MIsometry, MPoint, MVector, isNan;
import common.node : Chunk, ChunkId, ChunkState, Node;
import common.voxel_math : Coords;

enum uint REGION_MAX_NODES = 64;
enum uint SHAPE_CAST_MAX_NODES = 128;

struct Capsule {
    float[3] axis;
    float radius;
    float halfHeight;
    float skin;
}

struct GraphCollisionHit {
    ChunkId chunk;
    MVector!float normal;
    MVector!float[MAX_FEATURE_SURFACES] surfaces;
    float stopDistance;
    float gap;
    uint surfaceCount;
    bool lowestSection;
}

struct NodeVisit {
    uint slot;
    MIsometry!float inverse;
}

bool containsSlot(const(NodeVisit)[] visits, uint slot) {
    bool found = false;
    foreach (visit; visits) {
        if (visit.slot == slot) {
            found = true;
        }
    }
    return found;
}

bool regionPopulated(const(Graph)* graph, NodeId positionNode, MIsometry!float positionLocal, float distance) {
    uint startSlot = graph.slotOf(positionNode);
    bool populated = startSlot != NO_SLOT;
    if (populated) {
        float nodeThreshold = coshf(distance + BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS);
        float chunkThreshold = coshf(distance + CHUNK_BOUNDING_SPHERE_RADIUS);
        MVector!float point = (positionLocal * MPoint!float.origin()).vec;
        NodeVisit[REGION_MAX_NODES] visits = void;
        uint count = 1;
        uint front = 0;
        visits[0] = NodeVisit(startSlot, MIsometry!float.identity());
        while (populated && front < count) {
            NodeVisit visit = visits[front];
            front += 1;
            MVector!float localPoint = visit.inverse * point;
            const(Node)* node = graph.nodeAt(visit.slot);
            foreach (vertexIndex; 0 .. VERTEX_COUNT) {
                Vertex vertex = cast(Vertex) vertexIndex;
                if (!(-localPoint.mip(vertexChunkBoundingSphereCenter(vertex).vec) > chunkThreshold) && node.chunks[vertex].state != ChunkState.Populated) {
                    populated = false;
                }
            }
            foreach (sideIndex; 0 .. SIDE_COUNT) {
                if (populated) {
                    Side side = cast(Side) sideIndex;
                    uint neighbor = graph.neighborSlot(visit.slot, side);
                    MIsometry!float neighborInverse = sideReflection(side) * visit.inverse;
                    if (!((neighborInverse * point).data[3] > nodeThreshold)) {
                        if (neighbor == NO_SLOT) {
                            populated = false;
                        } else if (!containsSlot(visits[0 .. count], neighbor) && count < REGION_MAX_NODES) {
                            visits[count] = NodeVisit(neighbor, neighborInverse);
                            count += 1;
                        }
                    }
                }
            }
        }
    }
    return populated;
}

SweptShape chunkShape(Capsule capsule, MIsometry!float localToDual) {
    MVector!float axis = localToDual * MVector!float(capsule.axis[0], capsule.axis[1], capsule.axis[2], 0);
    return SweptShape(axis, capsule.radius, capsule.halfHeight, capsule.skin);
}

GraphCollisionHit shapeCast(Capsule capsule, const(Graph)* graph, NodeId positionNode, MIsometry!float positionLocal, Ray ray, float tanhDistance) {
    GraphCollisionHit hit;
    hit.stopDistance = float.nan;
    uint startSlot = graph.slotOf(positionNode);
    if (startSlot != NO_SLOT) {
        Ray nodeRay = transformRay(positionLocal, ray);
        float capped = MAX_TANH_DISTANCE;
        if (tanhDistance < MAX_TANH_DISTANCE) {
            capped = tanhDistance;
        }
        float reach = atanhf(capped) + capsule.radius + capsule.halfHeight;
        float nodeThreshold = coshf(reach + BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS);
        float chunkThreshold = coshf(reach + CHUNK_BOUNDING_SPHERE_RADIUS);
        NodeVisit[SHAPE_CAST_MAX_NODES] visits = void;
        uint count = 1;
        uint front = 0;
        visits[0] = NodeVisit(startSlot, MIsometry!float.identity());
        while (front < count) {
            NodeVisit visit = visits[front];
            front += 1;
            Ray localRay = transformRay(visit.inverse, nodeRay);
            const(Node)* node = graph.nodeAt(visit.slot);
            foreach (vertexIndex; 0 .. VERTEX_COUNT) {
                Vertex vertex = cast(Vertex) vertexIndex;
                const(Chunk)* chunk = &node.chunks[vertex];
                if (chunk.state == ChunkState.Populated && !(-localRay.position.vec.mip(vertexChunkBoundingSphereCenter(vertex).vec) > chunkThreshold)) {
                    MIsometry!float localToDual = vertexNodeToDual(vertex) * visit.inverse * positionLocal;
                    Ray chunkRay = transformRay(vertexNodeToDual(vertex), localRay);
                    ChunkCollisionHit chunkHit = chunkShapeCast(chunkShape(capsule, localToDual), &chunk.voxels, graph.layout, chunkRay, tanhDistance);
                    if (!isNan(chunkHit.stopDistance) && (isNan(hit.stopDistance) || chunkHit.stopDistance < hit.stopDistance)) {
                        MIsometry!float dualToLocal = localToDual.inverse();
                        hit.stopDistance = chunkHit.stopDistance;
                        hit.gap = chunkHit.gap;
                        hit.normal = dualToLocal * chunkHit.normal;
                        foreach (i; 0 .. chunkHit.surfaceCount) {
                            hit.surfaces[i] = dualToLocal * chunkHit.surfaces[i];
                        }
                        hit.surfaceCount = chunkHit.surfaceCount;
                        hit.lowestSection = chunkHit.lowestSection;
                        hit.chunk = ChunkId(graph.idAt(visit.slot), vertex);
                    }
                }
            }
            foreach (sideIndex; 0 .. SIDE_COUNT) {
                Side side = cast(Side) sideIndex;
                uint neighbor = graph.neighborSlot(visit.slot, side);
                if (neighbor != NO_SLOT && !containsSlot(visits[0 .. count], neighbor) && count < SHAPE_CAST_MAX_NODES) {
                    MIsometry!float neighborInverse = sideReflection(side) * visit.inverse;
                    if (!((neighborInverse * nodeRay.position.vec).data[3] > nodeThreshold)) {
                        visits[count] = NodeVisit(neighbor, neighborInverse);
                        count += 1;
                    }
                }
            }
        }
    }
    return hit;
}

bool capsuleOverlapsVoxel(Capsule capsule, const(Graph)* graph, NodeId positionNode, MIsometry!float positionLocal, ChunkId chunkId, Coords coords) {
    uint startSlot = graph.slotOf(positionNode);
    uint targetSlot = graph.slotOf(chunkId.node);
    bool overlaps = false;
    if (startSlot != NO_SLOT && targetSlot != NO_SLOT) {
        float nodeThreshold = coshf(capsule.radius + capsule.halfHeight + BOUNDING_SPHERE_RADIUS);
        MVector!float point = (positionLocal * MPoint!float.origin()).vec;
        NodeVisit[REGION_MAX_NODES] visits = void;
        uint count = 1;
        uint front = 0;
        visits[0] = NodeVisit(startSlot, MIsometry!float.identity());
        while (front < count) {
            NodeVisit visit = visits[front];
            front += 1;
            if (visit.slot == targetSlot) {
                MIsometry!float localToDual = vertexNodeToDual(chunkId.vertex) * visit.inverse * positionLocal;
                overlaps = capsuleIntersectsVoxel(chunkShape(capsule, localToDual), graph.layout, coords.data, localToDual * MPoint!float.origin());
            }
            foreach (sideIndex; 0 .. SIDE_COUNT) {
                Side side = cast(Side) sideIndex;
                uint neighbor = graph.neighborSlot(visit.slot, side);
                if (neighbor != NO_SLOT && !containsSlot(visits[0 .. count], neighbor) && count < REGION_MAX_NODES) {
                    MIsometry!float neighborInverse = sideReflection(side) * visit.inverse;
                    if (!((neighborInverse * point).data[3] > nodeThreshold)) {
                        visits[count] = NodeVisit(neighbor, neighborInverse);
                        count += 1;
                    }
                }
            }
        }
    }
    return overlaps;
}
