module common.graph_ray_casting;

import common.chunk_ray_casting;
import common.collision_math;
import common.graph;
import common.math;
import common.node;
import common.voxel_math;
import std.math : isNaN;
import common.dodeca : Vertex, VERTEX_COUNT;

struct GraphCastHit {
    float tanhDistance;
    ChunkId chunk;
    Coords voxelCoords;
    CoordAxis faceAxis;
    CoordSign faceSign;
}

struct OutOfBounds {}

/// Performs ray casting against the voxels in the graph.
/// Returns null hit (tanhDistance == NaN) on miss, throws nothing.
/// Sets outOfBounds if not enough chunks are generated.
GraphCastHit rayCast(
    const ref Graph graph,
    NodeId posNode,
    MIsometry!float posLocal,
    const ref Ray ray,
    float tanhDistance,
    out bool outOfBounds
) {

    GraphCastHit hit;
    hit.tanhDistance = float.nan;
    outOfBounds = false;

    // TODO: Implement RayTraverser for proper multi-chunk traversal
    // For now, simplified single-chunk cast

    foreach (vIdx; 0 .. VERTEX_COUNT) {
        auto vertex = cast(Vertex) vIdx;
        auto chunk = ChunkId(posNode, vertex);
        auto chunkData = getChunkVoxels(graph, chunk);
        if (chunkData is null) continue;

        auto chunkHit = chunkRayCast(*chunkData, graph.layout(), ray, tanhDistance);
        if (!isNaN(chunkHit.tanhDistance)) {
            tanhDistance = chunkHit.tanhDistance;
            hit.tanhDistance = chunkHit.tanhDistance;
            hit.chunk = chunk;
            hit.voxelCoords = chunkHit.voxelCoords;
            hit.faceAxis = chunkHit.faceAxis;
            hit.faceSign = chunkHit.faceSign;
        }
    }

    return hit;
}

private const(VoxelData)* getChunkVoxels(const ref Graph graph, ChunkId chunk) {
    if (!graph.contains(chunk.node)) return null;
    auto n = &graph[chunk.node];
    auto c = &n.chunks.values[chunk.vertex];
    if (c.state != ChunkState.Populated) return null;
    return &c.voxels;
}
