module client.worldgen_driver;

import common.dodeca : Vertex, VERTEX_COUNT, CHUNK_BOUNDING_SPHERE_RADIUS,
    vertexChunkBoundingSphereCenter;
import common.graph : Graph, NodeId;
import common.math : MPoint, MIsometry;
import common.node : ChunkId, ChunkState, VoxelData;
import common.traversal : NearbyNode;
import common.worldgen : ChunkParams, ChunkIncidentEnviroFactors, generateVoxels;
import common.margins : fixMargins;
import common.voxel_math : ChunkDirection, CoordSign;

/// Drives world generation for chunks near the player.
struct WorldgenDriver {
    private VoxelData[ChunkId] preloadedVoxelData;

    static WorldgenDriver create() {
        WorldgenDriver w;
        return w;
    }

    enum MAX_GENERATE_PER_FRAME = 8;

    void drive(
        const(NearbyNode)[] nearby,
        MIsometry!float camLocal,
        float distance,
        ref Graph graph,
        ubyte chunkSize,
    ) {
        import std.math : cosh;
        float threshold = cosh(distance + CHUNK_BOUNDING_SPHERE_RADIUS);
        auto startP = camLocal * MPoint!float.origin();
        uint generated = 0;

        foreach (ref nn; nearby) {
            foreach (vIdx; 0 .. VERTEX_COUNT) {
                auto vertex = cast(Vertex) vIdx;
                auto chunkId = ChunkId(nn.id, vertex);
                auto c = &graph[nn.id].chunks.values[vertex];
                if (c.state != ChunkState.Fresh) {
                    continue;
                }

                auto chunkCenter = nn.transform * vertexChunkBoundingSphereCenter(vertex);
                if (-startP.mip(chunkCenter.vec) > threshold) {
                    continue;
                }

                if (auto voxelData = chunkId in preloadedVoxelData) {
                    c.state = ChunkState.Populated;
                    c.voxels = *voxelData;
                    preloadedVoxelData.remove(chunkId);
                } else {
                    if (generated >= MAX_GENERATE_PER_FRAME) {
                        continue;
                    }
                    auto params = ChunkParams.create(graph, chunkId);
                    auto voxels = generateVoxels(params);
                    populateChunk(graph, chunkId, voxels, chunkSize);
                    generated++;
                }
            }
        }
    }

    void applyVoxelData(ChunkId chunkId, VoxelData voxelData) {
        preloadedVoxelData[chunkId] = voxelData;
    }
}

/// Populate a chunk and fix margins with already-populated neighbors.
private void populateChunk(ref Graph graph, ChunkId chunk, VoxelData voxels, ubyte dimension) {
    foreach (dir; ChunkDirection.ALL) {
        auto neighborChunk = getChunkNeighbor(graph, chunk, dir.axis, dir.sign);
        if (neighborChunk.node == NodeId.init) {
            continue;
        }
        if (!graph.contains(neighborChunk.node)) {
            continue;
        }
        auto neighborC = &graph[neighborChunk.node].chunks.values[neighborChunk.vertex];
        if (neighborC.state != ChunkState.Populated) {
            continue;
        }
        fixMargins(dimension, chunk.vertex, voxels, dir, neighborC.voxels);
        neighborC.generation++;
    }
    auto c = &graph[chunk.node].chunks.values[chunk.vertex];
    c.state = ChunkState.Populated;
    c.voxels = voxels;
    c.generation++;
}

/// Get the neighboring chunk in a given direction.
private ChunkId getChunkNeighbor(ref Graph graph, ChunkId chunk, ubyte coordAxis, CoordSign coordSign) {
    import common.dodeca : vertexCanonicalSides, vertexAdjacentVertices;
    if (coordSign == CoordSign.Plus) {
        return ChunkId(chunk.node, vertexAdjacentVertices(chunk.vertex)[coordAxis]);
    } else {
        auto neighborNode = graph.neighbor(chunk.node, vertexCanonicalSides(chunk.vertex)[coordAxis]);
        if (neighborNode == NodeId.init) {
            return ChunkId(NodeId.init, chunk.vertex);
        }
        return ChunkId(neighborNode, chunk.vertex);
    }
}
