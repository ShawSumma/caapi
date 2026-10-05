module common.raycast.graph;

import core.stdc.math : atanhf, coshf, fminf;
import common.coords : CoordAxis, CoordSign, Coords;
import common.dodeca : BOUNDING_SPHERE_RADIUS, CHUNK_BOUNDING_SPHERE_RADIUS, VERTEX_COUNT, Vertex, chunkBoundingSphereCenter, nodeToDual;
import common.graph : Graph;
import common.math : isNan;
import common.node : Chunk, ChunkId, ChunkSlot, ChunkState;
import common.position : Position;
import common.ray : MAX_TANH_DISTANCE, Ray;
import common.raycast.chunk : ChunkRayCastHit, chunkRayCast;
import common.traversal : NodeVisit, VisitQueue;

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

GraphCastHit rayCast(ref const Graph graph, Position position, Ray ray, float tanhDistance) {
    GraphCastHit hit;
    Ray nodeRay = ray.transformedBy(position.local);
    float reach = atanhf(fminf(tanhDistance, MAX_TANH_DISTANCE));
    float nodeThreshold = coshf(reach + BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS);
    float chunkThreshold = coshf(reach + CHUNK_BOUNDING_SPHERE_RADIUS);
    VisitQueue!RAY_CAST_MAX_NODES queue = VisitQueue!RAY_CAST_MAX_NODES.fromSlot(graph.slotOf(position.node));
    float best = tanhDistance;
    while (queue.hasNext()) {
        NodeVisit visit = queue.current();
        Ray localRay = nodeRay.transformedBy(visit.inverse);
        foreach (vertexIndex; 0 .. VERTEX_COUNT) {
            Vertex vertex = cast(Vertex) vertexIndex;
            const(Chunk)* chunk = graph.chunkAt(ChunkSlot(visit.slot, vertex));
            if (chunk.state == ChunkState.populated && !(-localRay.position.vec.mip(vertex.chunkBoundingSphereCenter.vec) > chunkThreshold)) {
                ChunkRayCastHit chunkHit = chunkRayCast(chunk.voxels, graph.layout, localRay.transformedBy(vertex.nodeToDual), best);
                if (chunkHit.isHit()) {
                    best = chunkHit.tanhDistance;
                    hit = GraphCastHit(ChunkId(graph.idAt(visit.slot), vertex), chunkHit.tanhDistance, chunkHit.voxelCoords, chunkHit.faceAxis, chunkHit.faceSign);
                }
            }
        }
        queue.expand(graph, visit, nodeRay.position.vec, nodeThreshold);
    }
    return hit;
}
