module server.sim;

import common.dodeca : Vertex;
import common.graph : Graph, NodeId;
import common.graph_entities : GraphEntities, Entity;
import common.node : Chunk, ChunkId, ChunkState, VoxelData;
import common.proto : Position, CharacterInput, EntityId;
import common.sim_config : SimConfig;
import common.traversal : ensureNearby;
import common.worldgen : ChunkParams, ChunkIncidentEnviroFactors, generateVoxels, Plane;

alias Step = int;

struct Sim {
    SimConfig cfg;
    Step step;
    Graph graph;
    GraphEntities graphEntities;
    EntityId[ulong] entityIds;

    static Sim create(SimConfig cfg) {
        Sim s;
        s.cfg = cfg;
        s.graph = Graph.create(cfg.chunkSize);
        return s;
    }

    void doStep() {
        step++;
    }

    void ensureNearbyGenerated(Position pos) {
        ensureNearby(graph, pos.node, pos.local, cfg.chunkGenerationDistance);

        foreach (vIdx; 0 .. 20) {
            Vertex vertex = cast(Vertex) vIdx;
            ChunkId chunk = ChunkId(pos.node, vertex);
            if (!graph.contains(pos.node)) {
                continue;
            }
            Chunk* c = &graph[pos.node].chunks.values[vertex];
            if (c.state != ChunkState.Fresh) {
                continue;
            }

            c.state = ChunkState.Generating;
            ChunkParams params = ChunkParams(
                cfg.chunkSize,
                vertex,
                ChunkIncidentEnviroFactors.init,
                Plane.init,
                false, false, 0
            );
            VoxelData voxelData = generateVoxels(params);
            c.state = ChunkState.Populated;
            c.voxels = voxelData;
        }
    }

    void command(Entity entity, CharacterInput input) {
    }
}
