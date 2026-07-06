module common.graph_collision;

import std.math : atanh, cosh, isNaN;
import common.chunk_collision : ChunkCollisionHit, chunkSphereCast;
import common.collision_math : Ray, transformRay;
import common.dodeca : BOUNDING_SPHERE_RADIUS, CHUNK_BOUNDING_SPHERE_RADIUS,
    Side, Vertex, sideReflection, vertexChunkBoundingSphereCenter, vertexNodeToDual;
import common.graph : Graph, NodeId, NO_SLOT;
import common.math : MIsometry, MVector;
import common.node : Chunk, ChunkId, ChunkState, Node;

struct GraphCollisionHit {
    float tanhDistance;
    MVector!float normal;
    ChunkId chunk;
}

struct OutOfBounds {}

/// Sweeps a sphere along a ray (both in the caster's local frame) against
/// voxels, traversing every node the swept volume could reach so collision
/// keeps working across node boundaries.
GraphCollisionHit sphereCast(
    float colliderRadius,
    const ref Graph graph,
    NodeId posNode,
    MIsometry!float posLocal,
    const ref Ray ray,
    float tanhDistance,
    out bool outOfBounds
) {
    GraphCollisionHit hit;
    hit.tanhDistance = float.nan;
    outOfBounds = false;

    uint startSlot = graph.slotOf(posNode);
    if (startSlot == NO_SLOT) {
        return hit;
    }

    Ray nodeRay = transformRay(posLocal, ray);

    float capped = tanhDistance < 0.999f ? tanhDistance : 0.999f;
    float reachDist = atanh(capped) + colliderRadius;
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

    while (front < count) {
        uint slot = slots[front];
        MIsometry!float inv = invT[front];
        front++;

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

            // chunkSphereCast works in the chunk's dual frame; the hit normal
            // comes back through the full inverse so callers get it in the
            // caster's local frame.
            MIsometry!float localToDual = vertexNodeToDual(vertex) * inv * posLocal;
            Ray chunkRay = transformRay(vertexNodeToDual(vertex), localRay);
            ChunkCollisionHit chunkHit = chunkSphereCast(colliderRadius, c.voxels, graph.layout(), chunkRay, best);
            if (!isNaN(chunkHit.tanhDistance)) {
                best = chunkHit.tanhDistance;
                hit.tanhDistance = chunkHit.tanhDistance;
                hit.normal = localToDual.inverse().mat * chunkHit.normal;
                hit.chunk = ChunkId(graph.idAt(slot), vertex);
            }
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
            count++;
        }
    }

    return hit;
}
