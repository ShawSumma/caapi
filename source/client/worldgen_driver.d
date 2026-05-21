module client.worldgen_driver;

import std.math : cosh;
import common.dodeca : Vertex, CHUNK_BOUNDING_SPHERE_RADIUS,
    vertexChunkBoundingSphereCenter, vertexCanonicalSides, vertexAdjacentVertices;
import common.graph : Graph, NodeId;
import common.math : MPoint, MIsometry;
import common.node : Chunk, ChunkId, ChunkState, VoxelData;
import common.traversal : NearbyNode;
import common.worldgen : ChunkParams, ChunkIncidentEnviroFactors, generateVoxels;
import common.margins : fixMargins;
import common.voxel_math : ChunkDirection, CoordSign;

struct WorldgenDriver {
    VoxelData[ChunkId] preloadedVoxelData;

    static WorldgenDriver create() {
        WorldgenDriver w;
        return w;
    }

    int maxGeneratePerFrame = 8;

    void drive(
        const(NearbyNode)[] nearby,
        MIsometry!float camLocal,
        float distance,
        ref Graph graph,
        ubyte chunkSize,
    ) {
        float threshold = cosh(distance + CHUNK_BOUNDING_SPHERE_RADIUS);
        MPoint!float startP = camLocal * MPoint!float.origin();
        uint generated = 0;

        foreach (ref const NearbyNode nn; nearby) {
            foreach (int vIdx; 0 .. Vertex.max + 1) {
                Vertex vertex = cast(Vertex) vIdx;
                ChunkId chunkId = ChunkId(nn.id, vertex);
                Chunk* c = &graph[nn.id].chunks.values[vertex];
                if (c.state != ChunkState.Fresh) {
                    continue;
                }

                MPoint!float chunkCenter = nn.transform * vertexChunkBoundingSphereCenter(vertex);
                if (-startP.mip(chunkCenter.vec) > threshold) {
                    continue;
                }

                VoxelData* voxelData = chunkId in preloadedVoxelData;
                if (voxelData !is null) {
                    c.state = ChunkState.Populated;
                    c.voxels = *voxelData;
                    preloadedVoxelData.remove(chunkId);
                }
                else {
                    if (generated >= maxGeneratePerFrame) {
                        continue;
                    }
                    ChunkParams params = ChunkParams.create(graph, chunkId);
                    VoxelData voxels = generateVoxels(params);
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

void populateChunk(ref Graph graph, ChunkId chunk, VoxelData voxels, ubyte dimension) {
    foreach (ChunkDirection dir; ChunkDirection.ALL) {
        ChunkId neighborChunk = getChunkNeighbor(graph, chunk, dir.axis, dir.sign);
        if (neighborChunk.node == NodeId.init) {
            continue;
        }
        if (!graph.contains(neighborChunk.node)) {
            continue;
        }
        Chunk* neighborC = &graph[neighborChunk.node].chunks.values[neighborChunk.vertex];
        if (neighborC.state != ChunkState.Populated) {
            continue;
        }
        fixMargins(dimension, chunk.vertex, voxels, dir, neighborC.voxels);
        neighborC.generation++;
    }
    Chunk* c = &graph[chunk.node].chunks.values[chunk.vertex];
    c.state = ChunkState.Populated;
    c.voxels = voxels;
    c.generation++;
}

ChunkId getChunkNeighbor(ref Graph graph, ChunkId chunk, ubyte coordAxis, CoordSign coordSign) {
    if (coordSign == CoordSign.Plus) {
        return ChunkId(chunk.node, vertexAdjacentVertices(chunk.vertex)[coordAxis]);
    }
    else {
        NodeId neighborNode = graph.neighbor(chunk.node, vertexCanonicalSides(chunk.vertex)[coordAxis]);
        if (neighborNode == NodeId.init) {
            return ChunkId(NodeId.init, chunk.vertex);
        }
        return ChunkId(neighborNode, chunk.vertex);
    }
}
