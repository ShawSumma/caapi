module common.graph_collision;

import std.math : isNaN;
import common.chunk_collision : ChunkCollisionHit, chunkSphereCast;
import common.collision_math : Ray;
import common.dodeca : Vertex;
import common.graph : Graph, NodeId;
import common.math : MIsometry, MVector;
import common.node : Chunk, ChunkId, ChunkState;

struct GraphCollisionHit {
    float tanhDistance;
    MVector!float normal;
    ChunkId chunk;
}

struct OutOfBounds {}

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

    foreach (vIdx; 0 .. 20) {
        Vertex vertex = cast(Vertex) vIdx;
        ChunkId chunk = ChunkId(posNode, vertex);

        if (!graph.contains(posNode)) {
            continue;
        }
        const(Chunk)* c = &graph[posNode].chunks.values[vertex];
        if (c.state != ChunkState.Populated) {
            continue;
        }

        ChunkCollisionHit chunkHit = chunkSphereCast(colliderRadius, c.voxels, graph.layout(), ray, tanhDistance);
        if (!isNaN(chunkHit.tanhDistance)) {
            tanhDistance = chunkHit.tanhDistance;
            hit.tanhDistance = chunkHit.tanhDistance;
            hit.normal = chunkHit.normal;
            hit.chunk = chunk;
        }
    }

    return hit;
}
