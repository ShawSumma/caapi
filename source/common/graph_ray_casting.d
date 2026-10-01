module common.graph_ray_casting;

import core.stdc.math : atanhf, coshf;
import common.chunk_ray_casting : ChunkRayCastHit, chunkRayCast;
import common.collision_math : MAX_TANH_DISTANCE, Ray, transformRay;
import common.dodeca : BOUNDING_SPHERE_RADIUS, CHUNK_BOUNDING_SPHERE_RADIUS, SIDE_COUNT, Side, VERTEX_COUNT, Vertex, sideReflection, vertexChunkBoundingSphereCenter, vertexNodeToDual;
import common.graph : Graph, NO_SLOT, NodeId;
import common.graph_collision : NodeVisit, containsSlot;
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
        NodeVisit[RAY_CAST_MAX_NODES] visits = void;
        uint count = 1;
        uint front = 0;
        visits[0] = NodeVisit(startSlot, MIsometry!float.identity());
        float best = tanhDistance;
        while (front < count) {
            NodeVisit visit = visits[front];
            front += 1;
            Ray localRay = transformRay(visit.inverse, nodeRay);
            const(Node)* node = graph.nodeAt(visit.slot);
            foreach (vertexIndex; 0 .. VERTEX_COUNT) {
                Vertex vertex = cast(Vertex) vertexIndex;
                const(Chunk)* chunk = &node.chunks[vertex];
                if (chunk.state == ChunkState.Populated && !(-localRay.position.vec.mip(vertexChunkBoundingSphereCenter(vertex).vec) > chunkThreshold)) {
                    Ray chunkRay = transformRay(vertexNodeToDual(vertex), localRay);
                    ChunkRayCastHit chunkHit = chunkRayCast(&chunk.voxels, graph.layout, chunkRay, best);
                    if (!isNan(chunkHit.tanhDistance)) {
                        best = chunkHit.tanhDistance;
                        hit.tanhDistance = chunkHit.tanhDistance;
                        hit.chunk = ChunkId(graph.idAt(visit.slot), vertex);
                        hit.voxelCoords = chunkHit.voxelCoords;
                        hit.faceAxis = chunkHit.faceAxis;
                        hit.faceSign = chunkHit.faceSign;
                    }
                }
            }
            foreach (sideIndex; 0 .. SIDE_COUNT) {
                Side side = cast(Side) sideIndex;
                uint neighbor = graph.neighborSlot(visit.slot, side);
                if (neighbor != NO_SLOT && !containsSlot(visits[0 .. count], neighbor) && count < RAY_CAST_MAX_NODES) {
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
