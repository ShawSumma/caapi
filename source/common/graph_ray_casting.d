module common.graph_ray_casting;

import common.chunk_ray_casting : ChunkRayCastHit, chunkRayCast;
import common.collision_math : Ray, transformRay;
import common.dodeca : BOUNDING_SPHERE_RADIUS, CHUNK_BOUNDING_SPHERE_RADIUS;
import common.dodeca : Side, Vertex, sideReflection;
import common.dodeca : vertexChunkBoundingSphereCenter, vertexNodeToDual;
import common.graph : Graph, NodeId, NO_SLOT;
import common.math : MIsometry, MVector, atanh, cosh, isNaN;
import common.node : Chunk, ChunkId, ChunkState, Node, VoxelData;
import common.voxel_math : Coords, CoordAxis, CoordSign;

struct GraphCastHit {
    float tanhDistance;
    ChunkId chunk;
    Coords voxelCoords;
    CoordAxis faceAxis;
    CoordSign faceSign;
    // Carried on the result rather than written back through a parameter.
    bool outOfBounds;
}

struct OutOfBounds {}

// Casts a ray, given in the caster's local frame, against voxels. It traverses
// every node whose bounding sphere the ray segment could reach, so blocks just
// across a node boundary are as hittable as ones in the caster's own node.
GraphCastHit rayCast(
    const ref Graph graph,
    NodeId posNode,
    MIsometry!float posLocal,
    const ref Ray ray,
    float tanhDistance,
) {
    GraphCastHit hit;
    hit.tanhDistance = float.nan;
    hit.outOfBounds = false;

    uint startSlot = graph.slotOf(posNode);
    if (startSlot == NO_SLOT) {
        return hit;
    }

    Ray nodeRay = transformRay(posLocal, ray);

    // How far (in real hyperbolic distance) the segment can reach; used to
    // prune nodes and chunks whose bounding spheres it cannot touch.
    float capped = 0.999f;
    if (tanhDistance < 0.999f) {
        capped = tanhDistance;
    }
    float reachDist = atanh(capped);
    float nodeThreshold = cosh(reachDist + BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS);
    float chunkThreshold = cosh(reachDist + CHUNK_BOUNDING_SPHERE_RADIUS);

    // BFS over nearby nodes; invT[i] maps start-node coords to node-i coords.
    enum MAX_NODES = 512;
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

            Ray chunkRay = transformRay(vertexNodeToDual(vertex), localRay);
            ChunkRayCastHit chunkHit = chunkRayCast(c.voxels, graph.layout(), chunkRay, best);
            if (!isNaN(chunkHit.tanhDistance)) {
                best = chunkHit.tanhDistance;
                hit.tanhDistance = chunkHit.tanhDistance;
                hit.chunk = ChunkId(graph.idAt(slot), vertex);
                hit.voxelCoords = chunkHit.voxelCoords;
                hit.faceAxis = chunkHit.faceAxis;
                hit.faceSign = chunkHit.faceSign;
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
            count = count + 1;
        }
    }

    return hit;
}
