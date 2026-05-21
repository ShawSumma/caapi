module client.sim;

import common.graph : Graph;
import common.graph_entities : GraphEntities;
import common.proto : Position, CharacterInput, EntityId;
import common.sim_config : SimConfig;
import common.world : Material;

struct ClientSim {
    Graph graph;
    GraphEntities graphEntities;
    SimConfig cfg;
    EntityId localCharacterId;
    Position localPosition;
    int step;

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

    void applySpawns() {
    }

    void applyStateDelta() {
    }

    CharacterInput buildCommand() {
        CharacterInput input;
        input.movement = movementInput;
        input.jump = jumpInput;
        input.noClip = noClipInput;
        return input;
    }

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
