module common.graph_ray_casting;

import std.math : isNaN;
import common.chunk_ray_casting : ChunkRayCastHit, chunkRayCast;
import common.collision_math : Ray;
import common.dodeca : Vertex;
import common.graph : Graph, NodeId;
import common.math : MIsometry;
import common.node : Chunk, ChunkId, ChunkState, Node, VoxelData;
import common.voxel_math : Coords, CoordAxis, CoordSign;

struct GraphCastHit {
    float tanhDistance;
    ChunkId chunk;
    Coords voxelCoords;
    CoordAxis faceAxis;
    CoordSign faceSign;
}

struct OutOfBounds {}

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

    foreach (vIdx; 0 .. 20) {
        Vertex vertex = cast(Vertex) vIdx;
        ChunkId chunk = ChunkId(posNode, vertex);
        const(VoxelData)* chunkData = getChunkVoxels(graph, chunk);
        if (chunkData is null) {
            continue;
        }

        ChunkRayCastHit chunkHit = chunkRayCast(*chunkData, graph.layout(), ray, tanhDistance);
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

const(VoxelData)* getChunkVoxels(const ref Graph graph, ChunkId chunk) {
    if (!graph.contains(chunk.node)) {
        return null;
    }
    const(Node)* n = &graph[chunk.node];
    const(Chunk)* c = &n.chunks.values[chunk.vertex];
    if (c.state != ChunkState.Populated) {
        return null;
    }
    return &c.voxels;
}
