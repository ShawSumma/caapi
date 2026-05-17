module client.sim;

import common.graph;
import common.graph_entities;
import common.math;
import common.proto;
import common.sim_config;
import common.world;
import common.node;
import common.dodeca;

/// Client-side game state
struct ClientSim {
    Graph graph;
    GraphEntities graphEntities;
    SimConfig cfg;
    EntityId localCharacterId;
    Position localPosition;
    int step;

    // Input state
    float[3] movementInput = [0, 0, 0];
    bool jumpInput;
    bool noClipInput;
    int selectedMaterial;

    static ClientSim create(SimConfig cfg, EntityId localChar) {
        ClientSim s;
        s.cfg = cfg;
        s.graph = Graph.create(cfg.chunkSize);
        s.localCharacterId = localChar;
        s.localPosition = Position.origin();
        return s;
    }

    /// Apply a spawns message from the server
    void applySpawns(/* Spawns data */) {
        // Apply new nodes, voxel data, block updates, etc.
    }

    /// Apply a state delta from the server
    void applyStateDelta(/* StateDelta data */) {
        // Update positions, character states
    }

    /// Build the command to send to the server
    CharacterInput buildCommand() {
        CharacterInput input;
        input.movement = movementInput;
        input.jump = jumpInput;
        input.noClip = noClipInput;
        return input;
    }

    /// Material palette for block placement
    static immutable Material[10] MATERIAL_PALETTE = [
        Material.WoodPlanks,
        Material.Grass,
        Material.Dirt,
        Material.Sand,
        Material.Snow,
        Material.WhiteBrick,
        Material.GreyBrick,
        Material.Basalt,
        Material.Water,
        Material.Lava,
    ];
}
