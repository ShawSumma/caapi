module common.raycast.graph;

import core.stdc.math : atanhf, coshf;
import base.numbers : isNan, lowerOf;
import common.graph : Graph;
import common.node : Chunk, ChunkId, ChunkSlot, ChunkState;
import common.position : Position;
import common.raycast.chunk : ChunkRayCastHit, castThroughChunk;
import common.traversal : NodeVisit, VisitQueue;
import geometry.cube : Axis, Cell, Sign;
import geometry.honeycomb : CORNER_COUNT, CUBE_RADIUS, Corner, NODE_RADIUS, cubeCenter, nodeToCorner;
import geometry.ray : MAX_TANH_DISTANCE, Ray;

enum uint RAY_CAST_MAX_NODES = 512;

struct GraphCastHit {
    ChunkId chunk;
    float tanhDistance = float.nan;
    Cell voxelCoords;
    Axis faceAxis;
    Sign faceSign;

    bool isHit() const {
        return !isNan(tanhDistance);
    }
}

GraphCastHit rayCast(ref const Graph graph, Position position, Ray ray, float tanhDistance) {
    GraphCastHit hit;
    Ray nodeRay = ray.movedBy(position.local);
    float reach = atanhf(lowerOf(tanhDistance, MAX_TANH_DISTANCE));
    float nodeThreshold = coshf(reach + NODE_RADIUS + CUBE_RADIUS);
    float chunkThreshold = coshf(reach + CUBE_RADIUS);
    VisitQueue!RAY_CAST_MAX_NODES queue = VisitQueue!RAY_CAST_MAX_NODES.fromSlot(graph.slotOf(position.node));
    float best = tanhDistance;
    while (queue.hasNext()) {
        NodeVisit visit = queue.current();
        Ray localRay = nodeRay.movedBy(visit.inverse);
        foreach (index; 0 .. CORNER_COUNT) {
            Corner corner = cast(Corner) index;
            const(Chunk)* chunk = graph.chunks.at(ChunkSlot(visit.slot, corner));
            if (chunk.state == ChunkState.populated && !(localRay.start.coshDistance(corner.cubeCenter) > chunkThreshold)) {
                ChunkRayCastHit chunkHit = castThroughChunk(chunk.voxels, graph.layout, localRay.movedBy(corner.nodeToCorner), best);
                if (chunkHit.isHit()) {
                    best = chunkHit.tanhDistance;
                    hit = GraphCastHit(ChunkId(graph.idAt(visit.slot), corner), chunkHit.tanhDistance, chunkHit.voxelCoords, chunkHit.faceAxis, chunkHit.faceSign);
                }
            }
        }
        queue.expand(graph, visit, nodeRay.start.v, nodeThreshold);
    }
    return hit;
}
