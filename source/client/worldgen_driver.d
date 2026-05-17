module client.worldgen_driver;

import common.dodeca : Vertex, VERTEX_COUNT, CHUNK_BOUNDING_SPHERE_RADIUS;
import common.graph : Graph, NodeId;
import common.math : MIsometry, MPoint;
import common.node : ChunkId, ChunkState, VoxelData;
import common.proto : Position;
import common.traversal : ensureNearby, NearbyNode, nearbyNodes;
import common.worldgen : ChunkParams, ChunkIncidentEnviroFactors, generateVoxels;

/// Drives world generation for chunks near the player.
struct WorldgenDriver {
    private VoxelData[ChunkId] preloadedVoxelData;

    static WorldgenDriver create() {
        WorldgenDriver w;
        return w;
    }

    void drive(Position view, float chunkGenerationDistance, ref Graph graph, ubyte chunkSize) {
        if (!graph.contains(view.node)) {
            return;
        }

        ensureNearby(graph, view.node, view.local, chunkGenerationDistance);

        foreach (vIdx; 0 .. VERTEX_COUNT) {
            auto vertex = cast(Vertex) vIdx;
            auto chunkId = ChunkId(view.node, vertex);
            auto c = &graph[view.node].chunks.values[vertex];
            if (c.state != ChunkState.Fresh) {
                continue;
            }

            if (auto voxelData = chunkId in preloadedVoxelData) {
                c.state = ChunkState.Populated;
                c.voxels = *voxelData;
                preloadedVoxelData.remove(chunkId);
            } else {
                auto params = ChunkParams(
                    chunkSize, vertex,
                    ChunkIncidentEnviroFactors.init,
                    (float[8]).init,
                    false, false, 0
                );
                c.state = ChunkState.Populated;
                c.voxels = generateVoxels(params);
            }
        }
    }

    void applyVoxelData(ChunkId chunkId, VoxelData voxelData) {
        preloadedVoxelData[chunkId] = voxelData;
    }
}
