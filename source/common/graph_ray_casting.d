module common.graph_ray_casting;

import core.stdc.math : atanhf, coshf, fminf;
import common.chunk_ray_casting : ChunkRayCastHit, chunkRayCast;
import common.collision_math : MAX_TANH_DISTANCE, Ray;
import common.dodeca : BOUNDING_SPHERE_RADIUS, CHUNK_BOUNDING_SPHERE_RADIUS, SIDE_COUNT, Side, VERTEX_COUNT, Vertex, chunkBoundingSphereCenter, nodeToDual, reflection;
import common.graph : Graph, NO_SLOT;
import common.graph_collision : NodeVisit, isVisited;
import common.math : MIsometry, isNan;
import common.node : Chunk, ChunkId, ChunkSlot, ChunkState;
import common.proto : Position;
import common.voxel_math : CoordAxis, CoordSign, Coords;

enum uint RAY_CAST_MAX_NODES = 512;

struct GraphCastHit {
    ChunkId chunk;
    float tanhDistance = float.nan;
    Coords voxelCoords;
    CoordAxis faceAxis;
    CoordSign faceSign;

    bool isHit() const {
        return !isNan(tanhDistance);
    }
}

GraphCastHit rayCast(const(Graph)* graph, Position position, Ray ray, float tanhDistance) {
    GraphCastHit hit;
    Ray nodeRay = ray.transformedBy(position.local);
    float reach = atanhf(fminf(tanhDistance, MAX_TANH_DISTANCE));
    float nodeThreshold = coshf(reach + BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS);
    float chunkThreshold = coshf(reach + CHUNK_BOUNDING_SPHERE_RADIUS);
    NodeVisit[RAY_CAST_MAX_NODES] visits = void;
    uint count = 1;
    uint front = 0;
    visits[0] = NodeVisit(graph.slotOf(position.node), MIsometry!float.identity());
    float best = tanhDistance;
    while (front < count) {
        NodeVisit visit = visits[front];
        front += 1;
        Ray localRay = nodeRay.transformedBy(visit.inverse);
        foreach (vertexIndex; 0 .. VERTEX_COUNT) {
            Vertex vertex = cast(Vertex) vertexIndex;
            const(Chunk)* chunk = graph.chunkAt(ChunkSlot(visit.slot, vertex));
            if (chunk.state == ChunkState.Populated && !(-localRay.position.vec.mip(vertex.chunkBoundingSphereCenter.vec) > chunkThreshold)) {
                ChunkRayCastHit chunkHit = chunkRayCast(&chunk.voxels, graph.layout, localRay.transformedBy(vertex.nodeToDual), best);
                if (chunkHit.isHit()) {
                    best = chunkHit.tanhDistance;
                    hit = GraphCastHit(ChunkId(graph.idAt(visit.slot), vertex), chunkHit.tanhDistance, chunkHit.voxelCoords, chunkHit.faceAxis, chunkHit.faceSign);
                }
            }
        }
        foreach (sideIndex; 0 .. SIDE_COUNT) {
            Side side = cast(Side) sideIndex;
            uint neighbor = graph.neighborSlot(visit.slot, side);
            MIsometry!float neighborInverse = side.reflection * visit.inverse;
            if (neighbor != NO_SLOT && !isVisited(visits[0 .. count], neighbor) && count < RAY_CAST_MAX_NODES &&!((neighborInverse * nodeRay.position.vec).data[3] > nodeThreshold)) {
                visits[count] = NodeVisit(neighbor, neighborInverse);
                count += 1;
            }
        }
    }
    return hit;
}
