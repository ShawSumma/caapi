module common.proto;

import common.graph : NodeId, ROOT_NODE;
import common.math : MIsometry;

struct Position {
    NodeId node;
    MIsometry!float local;
}

Position originPosition() {
    return Position(ROOT_NODE, MIsometry!float.identity());
}

struct CharacterInput {
    float[3] movement = [0, 0, 0];
    bool jump;
    bool fly;
    bool noClip;
}
