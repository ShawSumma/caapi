module common.position;

import common.graph : NodeId, ROOT_NODE;
import geometry.lorentz : Motion;

struct Position {
    NodeId node;
    Motion!float local;

    static Position origin() {
        return Position(ROOT_NODE, Motion!float.identity());
    }
}
