module common.position;

import common.graph : NodeId, ROOT_NODE;
import common.math : MIsometry;

struct Position {
    NodeId node;
    MIsometry!float local;

    static Position origin() {
        return Position(ROOT_NODE, MIsometry!float.identity());
    }
}
