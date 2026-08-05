module common.proto;

import common.graph : NodeId;
import common.math : MIsometry;
import common.node : ChunkId;
import common.voxel_math : Coords;
import common.world : Material;

alias EntityId = ulong;
alias Step = int;

struct Position {
    NodeId node;
    MIsometry!float local;

    static Position origin() {
        Position p;
        p.node = NodeId.ROOT;
        p.local = MIsometry!float.identity();
        return p;
    }
}

struct BlockUpdate {
    ChunkId chunkId;
    Coords coords;
    Material newMaterial;
    EntityId consumedEntity;
}

struct CharacterInput {
    float[3] movement = [0, 0, 0];
    bool jump;
    // No gravity, but still collides.
    bool fly;
    // No gravity and no collision.
    bool noClip;
}

struct CharacterState {
    float[3] velocity = [0, 0, 0];
    bool onGround;
}
