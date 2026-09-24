module common.graph_ray_casting;

import core.stdc.math : atanhf, coshf;
import common.chunk_ray_casting : ChunkRayCastHit, chunkRayCast;
import common.collision_math : MAX_TANH_DISTANCE, Ray, transformRay;
import common.dodeca : BOUNDING_SPHERE_RADIUS, CHUNK_BOUNDING_SPHERE_RADIUS, SIDE_COUNT, Side, VERTEX_COUNT, Vertex, sideReflection, vertexChunkBoundingSphereCenter, vertexNodeToDual;
import common.graph : Graph, NO_SLOT, NodeId;
import common.graph_collision : containsSlot;
import common.math : MIsometry, isNan;
import common.node : Chunk, ChunkId, ChunkState, Node;
import common.voxel_math : CoordAxis, CoordSign, Coords;

enum uint RAY_CAST_MAX_NODES = 512;

struct GraphCastHit {
    ChunkId chunk;
    float tanhDistance;
    Coords voxelCoords;
    CoordAxis faceAxis;
    CoordSign faceSign;
}

GraphCastHit rayCast(const(Graph)* graph, NodeId positionNode, MIsometry!float positionLocal, Ray ray, float tanhDistance) {
    GraphCastHit hit;
    hit.tanhDistance = float.nan;
    uint startSlot = graph.slotOf(positionNode);
    if (startSlot != NO_SLOT) {
        Ray nodeRay = transformRay(positionLocal, ray);
        float capped = MAX_TANH_DISTANCE;
        if (tanhDistance < MAX_TANH_DISTANCE) {
            capped = tanhDistance;
        }
        float reach = atanhf(capped);
        float nodeThreshold = coshf(reach + BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS);
        float chunkThreshold = coshf(reach + CHUNK_BOUNDING_SPHERE_RADIUS);
        uint[RAY_CAST_MAX_NODES] slots = void;
        MIsometry!float[RAY_CAST_MAX_NODES] inverses = void;
        uint count = 1;
        uint front = 0;
        slots[0] = startSlot;
        inverses[0] = MIsometry!float.identity();
        float best = tanhDistance;
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
                    Ray chunkRay = transformRay(vertexNodeToDual(vertex), localRay);
                    ChunkRayCastHit chunkHit = chunkRayCast(&chunk.voxels, graph.layout, chunkRay, best);
                    if (!isNan(chunkHit.tanhDistance)) {
                        best = chunkHit.tanhDistance;
                        hit.tanhDistance = chunkHit.tanhDistance;
                        hit.chunk = ChunkId(graph.idAt(slot), vertex);
                        hit.voxelCoords = chunkHit.voxelCoords;
                        hit.faceAxis = chunkHit.faceAxis;
                        hit.faceSign = chunkHit.faceSign;
                    }
                }
            }
            foreach (sideIndex; 0 .. SIDE_COUNT) {
                Side side = cast(Side) sideIndex;
                uint neighbor = graph.neighborSlot(slot, side);
                if (neighbor != NO_SLOT && !containsSlot(slots[0 .. count], neighbor) && count < RAY_CAST_MAX_NODES) {
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
