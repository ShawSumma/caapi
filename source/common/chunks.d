module common.chunks;

import common.dodeca : Vertex, VERTEX_COUNT;

/// A table of chunks contained by a single node (1/20 of a node each)
struct Chunks(T) {
    T[VERTEX_COUNT] values;

    ref inout(T) opIndex(Vertex v) inout {
        return values[v];
    }
}
