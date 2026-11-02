module unit.neighbors;

import common.graph : Graph, ROOT_NODE;
import common.neighbors : CellHop, hopCell, isOutside, neighborAxisMap;
import common.node : ChunkSlot;
import common.worldgen.generation : Worldgen;
import geometry.cube : AXIS_COUNT, Axis, DIRECTIONS, beyondBoundary, boundaryOf;
import geometry.honeycomb : CORNER_COUNT, Corner, FACE_COUNT, Face;

enum ubyte DIMENSION = 4;
enum int EDGE_CELL = 2;

CellHop hopRemaining(ref const Graph graph, CellHop hop) {
    uint axis = AXIS_COUNT;
    while (axis > 0 && !isOutside(graph.layout.dimension, hop.cell[axis - 1])) {
        axis -= 1;
    }
    if (axis == 0) {
        return hop;
    } else {
        return graph.hopCell(hop.chunk, hop.cell, axis - 1);
    }
}

bool isSameCell(CellHop a, CellHop b) {
    return a.chunk == b.chunk && a.cell == b.cell;
}

unittest {
    Graph graph = Graph.make(DIMENSION, Worldgen.makeTerrain());
    uint root = graph.slotOf(ROOT_NODE);
    foreach (face; 0 .. FACE_COUNT) {
        uint neighbor = graph.ensureNeighborSlot(root, cast(Face) face);
        foreach (outer; 0 .. FACE_COUNT) {
            graph.ensureNeighborSlot(neighbor, cast(Face) outer);
        }
    }
    uint valenceFourEdges = 0;
    uint valenceFiveEdges = 0;
    foreach (cornerIndex; 0 .. CORNER_COUNT) {
        ChunkSlot chunk = ChunkSlot(root, cast(Corner) cornerIndex);
        foreach (a; 0 .. AXIS_COUNT) {
            foreach (b; a + 1 .. AXIS_COUNT) {
                foreach (signs; 0 .. 4u) {
                    int[3] edge = [EDGE_CELL, EDGE_CELL, EDGE_CELL];
                    edge[a] = -1;
                    if ((signs & 1) != 0) {
                        edge[a] = DIMENSION;
                    }
                    edge[b] = -1;
                    if ((signs & 2) != 0) {
                        edge[b] = DIMENSION;
                    }
                    CellHop viaA = graph.hopRemaining(graph.hopCell(chunk, edge, a));
                    CellHop viaB = graph.hopRemaining(graph.hopCell(chunk, edge, b));
                    if (signs == 3) {
                        assert(!isSameCell(viaA, viaB));
                        valenceFiveEdges += 1;
                    } else {
                        assert(isSameCell(viaA, viaB));
                        valenceFourEdges += 1;
                    }
                }
            }
        }
        foreach (direction; DIRECTIONS) {
            int[3] past = [EDGE_CELL, 1, 0];
            past[direction.axis] = beyondBoundary(DIMENSION, direction.sign);
            CellHop there = graph.hopCell(chunk, past, direction.axis);
            Axis back = neighborAxisMap(chunk.corner, direction).to[direction.axis];
            int[3] stepped = there.cell;
            stepped[back] = beyondBoundary(DIMENSION, direction.sign);
            CellHop home = graph.hopCell(there.chunk, stepped, back);
            int[3] expected = past;
            expected[direction.axis] = boundaryOf(DIMENSION, direction.sign);
            assert(home.chunk == chunk && home.cell == expected);
        }
    }
    assert(valenceFourEdges == CORNER_COUNT * AXIS_COUNT * 3);
    assert(valenceFiveEdges == CORNER_COUNT * AXIS_COUNT);
    graph.release();
}
