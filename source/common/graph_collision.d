module common.graph_collision;

import core.stdc.math : atanhf, coshf;
import common.chunk_collision : ChunkCollisionHit, FACE_TIE_EPS, SweptShape, chunkShapeCast;
import common.collision_math : MAX_TANH_DISTANCE, Ray, transformRay;
import common.dodeca : BOUNDING_SPHERE_RADIUS, CHUNK_BOUNDING_SPHERE_RADIUS, SIDE_COUNT, Side, VERTEX_COUNT, Vertex, sideReflection, vertexChunkBoundingSphereCenter, vertexNodeToDual;
import common.graph : Graph, NO_SLOT, NodeId;
import common.math : MIsometry, MPoint, MVector, isNan;
import common.node : Chunk, ChunkId, ChunkState, Node;

enum uint REGION_MAX_NODES = 64;
enum uint SHAPE_CAST_MAX_NODES = 128;

struct GraphCollisionHit {
    MVector!float normal;
    ChunkId chunk;
    float tanhDistance;
}

bool containsSlot(const(uint)[] slots, uint slot) {
    bool found = false;
    foreach (candidate; slots) {
        if (candidate == slot) {
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
        uint[REGION_MAX_NODES] slots = void;
        MIsometry!float[REGION_MAX_NODES] inverses = void;
        uint count = 1;
        uint front = 0;
        slots[0] = startSlot;
        inverses[0] = MIsometry!float.identity();
        while (populated && front < count) {
            uint slot = slots[front];
            MIsometry!float inverse = inverses[front];
            front += 1;
            MVector!float localPoint = inverse * point;
            const(Node)* node = graph.nodeAt(slot);
            foreach (vertexIndex; 0 .. VERTEX_COUNT) {
                Vertex vertex = cast(Vertex) vertexIndex;
                if (!(-localPoint.mip(vertexChunkBoundingSphereCenter(vertex).vec) > chunkThreshold) && node.chunks[vertex].state != ChunkState.Populated) {
                    populated = false;
                }
            }
            foreach (sideIndex; 0 .. SIDE_COUNT) {
                if (populated) {
                    Side side = cast(Side) sideIndex;
                    uint neighbor = graph.neighborSlot(slot, side);
                    MIsometry!float neighborInverse = sideReflection(side) * inverse;
                    if (!((neighborInverse * point).data[3] > nodeThreshold)) {
                        if (neighbor == NO_SLOT) {
                            populated = false;
                        } else if (!containsSlot(slots[0 .. count], neighbor) && count < REGION_MAX_NODES) {
                            slots[count] = neighbor;
                            inverses[count] = neighborInverse;
                            count += 1;
                        }
                    }
                }
            }
        }
    }
    return populated;
}

GraphCollisionHit shapeCast(float colliderRadius, float colliderHalfHeight, float[3] upAxis, const(Graph)* graph, NodeId positionNode, MIsometry!float positionLocal, Ray ray, float tanhDistance) {
    GraphCollisionHit hit;
    hit.tanhDistance = float.nan;
    uint startSlot = graph.slotOf(positionNode);
    if (startSlot != NO_SLOT) {
        Ray nodeRay = transformRay(positionLocal, ray);
        MVector!float axisLocal = MVector!float(upAxis[0], upAxis[1], upAxis[2], 0);
        float capped = MAX_TANH_DISTANCE;
        if (tanhDistance < MAX_TANH_DISTANCE) {
            capped = tanhDistance;
        }
        float reach = atanhf(capped) + colliderRadius + colliderHalfHeight;
        float nodeThreshold = coshf(reach + BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS);
        float chunkThreshold = coshf(reach + CHUNK_BOUNDING_SPHERE_RADIUS);
        uint[SHAPE_CAST_MAX_NODES] slots = void;
        MIsometry!float[SHAPE_CAST_MAX_NODES] inverses = void;
        uint count = 1;
        uint front = 0;
        slots[0] = startSlot;
        inverses[0] = MIsometry!float.identity();
        float best = tanhDistance;
        bool bestIsFace = false;
        bool haveBest = false;
        while (front < count) {
            uint slot = slots[front];
            MIsometry!float inverse = inverses[front];
            front += 1;
            Ray localRay = transformRay(inverse, nodeRay);
            const(Node)* node = graph.nodeAt(slot);
            foreach (vertexIndex; 0 .. VERTEX_COUNT) {
                Vertex vertex = cast(Vertex) vertexIndex;
                const(Chunk)* chunk = &node.chunks[vertex];
                if (chunk.state == ChunkState.Populated && !(-localRay.position.vec.mip(vertexChunkBoundingSphereCenter(vertex).vec) > chunkThreshold)) {
                    MIsometry!float localToDual = vertexNodeToDual(vertex) * inverse * positionLocal;
                    Ray chunkRay = transformRay(vertexNodeToDual(vertex), localRay);
                    SweptShape shape = SweptShape(localToDual * axisLocal, colliderRadius, colliderHalfHeight);
                    ChunkCollisionHit chunkHit = chunkShapeCast(shape, &chunk.voxels, graph.layout, chunkRay, best + FACE_TIE_EPS);
                    if (!isNan(chunkHit.tanhDistance)) {
                        bool accept;
                        if (!haveBest) {
                            accept = chunkHit.tanhDistance < best;
                        } else if (chunkHit.isFace) {
                            accept = chunkHit.tanhDistance < best || (!bestIsFace && chunkHit.tanhDistance < best + FACE_TIE_EPS);
                        } else if (bestIsFace) {
                            accept = chunkHit.tanhDistance < best - FACE_TIE_EPS;
                        } else {
                            accept = chunkHit.tanhDistance < best;
                        }
                        if (accept) {
                            best = chunkHit.tanhDistance;
                            bestIsFace = chunkHit.isFace;
                            haveBest = true;
                            hit.tanhDistance = chunkHit.tanhDistance;
                            hit.normal = localToDual.inverse().mat * chunkHit.normal;
                            hit.chunk = ChunkId(graph.idAt(slot), vertex);
                        }
                    }
                }
            }
            foreach (sideIndex; 0 .. SIDE_COUNT) {
                Side side = cast(Side) sideIndex;
                uint neighbor = graph.neighborSlot(slot, side);
                if (neighbor != NO_SLOT && !containsSlot(slots[0 .. count], neighbor) && count < SHAPE_CAST_MAX_NODES) {
                    MIsometry!float neighborInverse = sideReflection(side) * inverse;
                    if (!((neighborInverse * nodeRay.position.vec).data[3] > nodeThreshold)) {
                        slots[count] = neighbor;
                        inverses[count] = neighborInverse;
                        count += 1;
                    }
                }
            }
        }
    }
    return hit;
}
