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

    /// Advance the simulation by one step
    void doStep() {
        step++;
    }

    /// Ensure the graph is populated near a position
    void ensureNearbyGenerated(Position pos) {
        ensureNearby(graph, pos.node, pos.local, cfg.chunkGenerationDistance);

        // Generate voxels for unpopulated chunks
        foreach (vIdx; 0 .. VERTEX_COUNT) {
            auto vertex = cast(Vertex) vIdx;
            auto chunk = ChunkId(pos.node, vertex);
            if (!graph.contains(pos.node)) continue;
            auto c = &graph[pos.node].chunks.values[vertex];
            if (c.state != ChunkState.Fresh) continue;

            // Mark as generating then populate
            c.state = ChunkState.Generating;
            auto params = ChunkParams(
                cfg.chunkSize,
                vertex,
                ChunkIncidentEnviroFactors.init,
                (float[8]).init,
                false, false, 0
            );
            auto voxelData = generateVoxels(params);
            c.state = ChunkState.Populated;
            c.voxels = voxelData;
        }
    }

    /// Process a character's input command
    void command(Entity entity, CharacterInput input) {
        // Apply movement - simplified
    }
}
