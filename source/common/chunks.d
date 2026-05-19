module common.chunks;

import common.dodeca : Vertex;

struct Chunks(T) {
    T[20] values;

    ref inout(T) opIndex(Vertex v) inout {
        return values[v];
    }
}
