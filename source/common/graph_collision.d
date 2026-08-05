module common.graph_collision;

import common.chunk_collision : ChunkCollisionHit, FACE_TIE_EPS;
import common.chunk_collision : SweptShape, chunkShapeCast;
import common.collision_math : Ray, transformRay;
import common.dodeca : BOUNDING_SPHERE_RADIUS, CHUNK_BOUNDING_SPHERE_RADIUS;
import common.dodeca : Side, Vertex, sideReflection;
import common.dodeca : vertexChunkBoundingSphereCenter, vertexNodeToDual;
import common.graph : Graph, NodeId, NO_SLOT;
import common.math : MIsometry, MPoint, MVector, atanh, cosh, isNaN;
import common.node : Chunk, ChunkId, ChunkState, Node;

struct GraphCollisionHit {
    float tanhDistance;
    MVector!float normal;
    ChunkId chunk;
    // Carried on the result rather than written back through a parameter.
    bool outOfBounds;
}

struct OutOfBounds {}

// True when every chunk within dist of the position exists and is populated.
// Unloaded world must read as impassable, or a moving body can outrun async
// generation and have terrain materialise around it.
bool regionPopulated(
    const ref Graph graph,
    NodeId posNode,
    MIsometry!float posLocal,
    float dist,
) {
    uint startSlot = graph.slotOf(posNode);
    if (startSlot == NO_SLOT) {
        return false;
    }

    float nodeThreshold = cosh(dist + BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS);
    float chunkThreshold = cosh(dist + CHUNK_BOUNDING_SPHERE_RADIUS);
    MVector!float posPoint = (posLocal * MPoint!float.origin()).vec;

    enum MAX_NODES = 64;
    uint[MAX_NODES] slots = void;
    MIsometry!float[MAX_NODES] invT = void;
    uint count = 1;
    uint front = 0;
    slots[0] = startSlot;
    invT[0] = MIsometry!float.identity();

    while (front < count) {
        uint slot = slots[front];
        MIsometry!float inv = invT[front];
        front = front + 1;

        MVector!float localPos = inv * posPoint;

        const(Node)* node = &graph.nodeAt(slot);
        foreach (vIdx; 0 .. 20) {
            Vertex vertex = cast(Vertex) vIdx;
            if (-localPos.mip(vertexChunkBoundingSphereCenter(vertex).vec) > chunkThreshold) {
                continue;
            }
            if (node.chunks.values[vertex].state != ChunkState.Populated) {
                return false;
            }
        }

        foreach (sideIdx; 0 .. 12) {
            Side side = cast(Side) sideIdx;
            uint neighbor = graph.neighborSlot(slot, side);
            MIsometry!float neighborInv = sideReflection(side) * inv;
            MVector!float p = neighborInv * posPoint;
            if (p.w > nodeThreshold) {
                continue;
            }
            if (neighbor == NO_SLOT) {
                // In-range node that doesn't even exist yet.
                return false;
            }
            bool seen = false;
            foreach (i; 0 .. count) {
                if (slots[i] == neighbor) {
                    seen = true;
                    break;
                }
            }
            if (seen || count >= MAX_NODES) {
                continue;
            }
            slots[count] = neighbor;
            invT[count] = neighborInv;
            count = count + 1;
        }
    }
    return true;
}

// Sweeps an upright cylinder along a ray, both in the caster's local frame,
// against voxels. It traverses every node the swept volume could reach so
// collision keeps working across node boundaries. upAxis is the cylinder axis
// in the caster's local frame.
GraphCollisionHit shapeCast(
    float colliderRadius,
    float colliderHalfHeight,
    float[3] upAxis,
    const ref Graph graph,
    NodeId posNode,
    MIsometry!float posLocal,
    const ref Ray ray,
    float tanhDistance,
) {
    GraphCollisionHit hit;
    hit.tanhDistance = float.nan;
    hit.outOfBounds = false;

    uint startSlot = graph.slotOf(posNode);
    if (startSlot == NO_SLOT) {
        return hit;
    }

    Ray nodeRay = transformRay(posLocal, ray);
    MVector!float axisLocal = MVector!float(upAxis[0], upAxis[1], upAxis[2], 0);

    float capped = 0.999f;
    if (tanhDistance < 0.999f) {
        capped = tanhDistance;
    }
    float reachDist = atanh(capped) + colliderRadius + colliderHalfHeight;
    float nodeThreshold = cosh(reachDist + BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS);
    float chunkThreshold = cosh(reachDist + CHUNK_BOUNDING_SPHERE_RADIUS);

    // BFS over nearby nodes; invT[i] maps start-node coords to node-i coords.
    // Collision sweeps are short, so this rarely visits more than a handful.
    enum MAX_NODES = 128;
    uint[MAX_NODES] slots = void;
    MIsometry!float[MAX_NODES] invT = void;
    uint count = 1;
    uint front = 0;
    slots[0] = startSlot;
    invT[0] = MIsometry!float.identity();

    float best = tanhDistance;
    bool bestIsFace = false;
    bool haveBest = false;

    while (front < count) {
        uint slot = slots[front];
        MIsometry!float inv = invT[front];
        front = front + 1;

        Ray localRay = transformRay(inv, nodeRay);
        MVector!float rayStartK = localRay.position.vec;

        const(Node)* node = &graph.nodeAt(slot);
        foreach (vIdx; 0 .. 20) {
            Vertex vertex = cast(Vertex) vIdx;
            const(Chunk)* c = &node.chunks.values[vertex];
            if (c.state != ChunkState.Populated) {
                continue;
            }
            if (-rayStartK.mip(vertexChunkBoundingSphereCenter(vertex).vec) > chunkThreshold) {
                continue;
            }

            // chunkShapeCast works in the chunk's dual frame; the hit normal
            // comes back through the full inverse so callers get it in the
            // caster's local frame. The limit is padded by the face tie so a
            // surface face in one chunk can still take over an edge contact
            // at the same distance in another (chunk seam lips).
            MIsometry!float localToDual = vertexNodeToDual(vertex) * inv * posLocal;
            Ray chunkRay = transformRay(vertexNodeToDual(vertex), localRay);
            SweptShape shape = SweptShape.cylinder(
                colliderRadius,
                colliderHalfHeight,
                localToDual * axisLocal,
            );
            ChunkCollisionHit chunkHit = chunkShapeCast(
                shape,
                c.voxels,
                graph.layout(),
                chunkRay,
                best + FACE_TIE_EPS,
            );
            if (isNaN(chunkHit.tanhDistance)) {
                continue;
            }

            bool accept;
            if (!haveBest) {
                accept = chunkHit.tanhDistance < best;
            } else if (chunkHit.isFace) {
                accept = chunkHit.tanhDistance < best
                    || (!bestIsFace && chunkHit.tanhDistance < best + FACE_TIE_EPS);
            } else {
                float faceMargin = 0;
                if (bestIsFace) {
                    faceMargin = FACE_TIE_EPS;
                }
                accept = chunkHit.tanhDistance < best - faceMargin;
            }
            if (!accept) {
                continue;
            }

            best = chunkHit.tanhDistance;
            bestIsFace = chunkHit.isFace;
            haveBest = true;
            hit.tanhDistance = chunkHit.tanhDistance;
            hit.normal = localToDual.inverse().mat * chunkHit.normal;
            hit.chunk = ChunkId(graph.idAt(slot), vertex);
        }

        foreach (sideIdx; 0 .. 12) {
            Side side = cast(Side) sideIdx;
            uint neighbor = graph.neighborSlot(slot, side);
            if (neighbor == NO_SLOT) {
                continue;
            }
            bool seen = false;
            foreach (i; 0 .. count) {
                if (slots[i] == neighbor) {
                    seen = true;
                    break;
                }
            }
            if (seen || count >= MAX_NODES) {
                continue;
            }
            MIsometry!float neighborInv = sideReflection(side) * inv;
            MVector!float p = neighborInv * nodeRay.position.vec;
            if (p.w > nodeThreshold) {
                continue;
            }
            slots[count] = neighbor;
            invT[count] = neighborInv;
            count = count + 1;
        }
    }

    return hit;
}
