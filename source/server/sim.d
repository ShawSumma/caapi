module server.sim;

import common.graph;
import common.graph_entities;
import common.math;
import common.node;
import common.proto;
import common.sim_config;
import common.traversal;
import common.worldgen;
import common.dodeca;
import common.world;

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
