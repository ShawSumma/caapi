module common.chunk_neighbors;

import common.dodeca : SIDE_COUNT, Side, VERTEX_COUNT, Vertex, vertexAdjacentVertices, vertexCanonicalSides;
import common.graph : Graph, NO_SLOT, ROOT_NODE, createGraph;
import common.margins : CoordsWithMargins, boundaryCoordWithMargins, marginCoord, neighborAxisPermutation, permuteCoordsWithMargins;
import common.node : Chunk, ChunkSlot, ChunkState, Occupancy;
import common.voxel_math : ChunkDirection, CoordAxis, CoordSign;
import common.world : Material;

enum uint AXIS_COUNT = 3;
enum ubyte TEST_DIMENSION = 4;
enum ubyte TEST_EDGE_COORD = 2;

struct CellHop {
    CoordsWithMargins coords;
    ChunkSlot chunk;
    bool populated;
}

ChunkSlot chunkNeighborSlot(const(Graph)* graph, ChunkSlot chunk, ChunkDirection direction) {
    ChunkSlot result = ChunkSlot(chunk.slot, vertexAdjacentVertices(chunk.vertex)[direction.axis]);
    if (direction.sign == CoordSign.Minus) {
        result = ChunkSlot(graph.neighborSlot(chunk.slot, vertexCanonicalSides(chunk.vertex)[direction.axis]), chunk.vertex);
    }
    return result;
}

bool outsideInterior(ubyte dimension, ubyte coord) {
    return coord == 0 || coord == dimension + 1;
}

CellHop hopCell(const(Graph)* graph, ChunkSlot chunk, CoordsWithMargins coords, size_t axis) {
    ubyte dimension = graph.layout.dimension;
    CoordSign sign = CoordSign.Plus;
    if (coords.data[axis] == 0) {
        sign = CoordSign.Minus;
    }
    ChunkDirection direction = ChunkDirection(cast(CoordAxis) axis, sign);
    CellHop result;
    result.chunk = chunkNeighborSlot(graph, chunk, direction);
    if (result.chunk.slot != NO_SLOT) {
        CoordsWithMargins moved = coords;
        moved.data[axis] = boundaryCoordWithMargins(dimension, sign);
        result.coords = permuteCoordsWithMargins(neighborAxisPermutation(chunk.vertex, direction), moved);
        result.populated = graph.nodeAt(result.chunk.slot).chunks[result.chunk.vertex].state == ChunkState.Populated;
    }
    return result;
}

bool cellOccupied(const(Graph)* graph, ChunkSlot chunk, CoordsWithMargins coords) {
    ubyte dimension = graph.layout.dimension;
    bool result = false;
    bool interior = true;
    foreach (axis; 0 .. AXIS_COUNT) {
        if (outsideInterior(dimension, coords.data[axis])) {
            interior = false;
            CellHop hop = hopCell(graph, chunk, coords, axis);
            if (hop.populated) {
                result = result || cellOccupied(graph, hop.chunk, hop.coords);
            } else {
                result = result || hop.chunk.slot == NO_SLOT || assumedOccupied(graph.nodeAt(hop.chunk.slot).chunks[hop.chunk.vertex].predicted);
            }
        }
    }
    if (interior) {
        result = graph.nodeAt(chunk.slot).chunks[chunk.vertex].voxels.get(coords.toIndex(dimension)) != Material.Void;
    }
    return result;
}

bool assumedOccupied(Occupancy predicted) {
    return predicted != Occupancy.empty;
}

bool contradictsPrediction(const(Chunk)* chunk) {
    bool result = !chunk.voxels.isSolid();
    if (chunk.voxels.isSolid()) {
        result = (chunk.voxels.solidMaterial != Material.Void) != assumedOccupied(chunk.predicted);
    }
    return result;
}

void touchHolders(Graph* graph, ChunkSlot chunk, CoordsWithMargins coords) {
    ubyte dimension = graph.layout.dimension;
    bool interior = true;
    foreach (axis; 0 .. AXIS_COUNT) {
        if (outsideInterior(dimension, coords.data[axis])) {
            interior = false;
            CellHop hop = hopCell(graph, chunk, coords, axis);
            if (hop.populated) {
                touchHolders(graph, hop.chunk, hop.coords);
            }
        }
    }
    if (interior) {
        graph.markChanged(chunk);
    }
}

void touchChunksReading(Graph* graph, ChunkSlot chunk, CoordsWithMargins cell) {
    ubyte dimension = graph.layout.dimension;
    ubyte[AXIS_COUNT] margins;
    uint boundaryAxes = 0;
    foreach (axis; 0 .. AXIS_COUNT) {
        if (cell.data[axis] == boundaryCoordWithMargins(dimension, CoordSign.Minus)) {
            margins[axis] = marginCoord(dimension, CoordSign.Minus);
            boundaryAxes |= 1u << axis;
        } else if (cell.data[axis] == boundaryCoordWithMargins(dimension, CoordSign.Plus)) {
            margins[axis] = marginCoord(dimension, CoordSign.Plus);
            boundaryAxes |= 1u << axis;
        }
    }
    foreach (subset; 1 .. 1u << AXIS_COUNT) {
        if ((subset & boundaryAxes) == subset) {
            CoordsWithMargins pushed = cell;
            foreach (axis; 0 .. AXIS_COUNT) {
                if ((subset & (1u << axis)) != 0) {
                    pushed.data[axis] = margins[axis];
                }
            }
            touchHolders(graph, chunk, pushed);
        }
    }
}

void touchChunksAround(Graph* graph, ChunkSlot chunk) {
    ubyte dimension = graph.layout.dimension;
    foreach (corner; 0 .. 1u << AXIS_COUNT) {
        CoordsWithMargins cell;
        foreach (axis; 0 .. AXIS_COUNT) {
            cell.data[axis] = boundaryCoordWithMargins(dimension, CoordSign.Minus);
            if ((corner & (1u << axis)) != 0) {
                cell.data[axis] = boundaryCoordWithMargins(dimension, CoordSign.Plus);
            }
        }
        touchChunksReading(graph, chunk, cell);
    }
}

CellHop hopRemaining(const(Graph)* graph, CellHop hop) {
    CellHop result = hop;
    foreach (axis; 0 .. AXIS_COUNT) {
        if (outsideInterior(graph.layout.dimension, hop.coords.data[axis])) {
            result = hopCell(graph, hop.chunk, hop.coords, axis);
        }
    }
    return result;
}

unittest {
    Graph graph = createGraph(TEST_DIMENSION);
    uint root = graph.slotOf(ROOT_NODE);
    foreach (side; 0 .. SIDE_COUNT) {
        uint neighbor = graph.ensureNeighborSlot(root, cast(Side) side);
        foreach (outer; 0 .. SIDE_COUNT) {
            graph.ensureNeighborSlot(neighbor, cast(Side) outer);
        }
    }
    uint valenceFourEdges = 0;
    uint valenceFiveEdges = 0;
    foreach (vertexIndex; 0 .. VERTEX_COUNT) {
        ChunkSlot chunk = ChunkSlot(root, cast(Vertex) vertexIndex);
        foreach (a; 0 .. AXIS_COUNT) {
            foreach (b; a + 1 .. AXIS_COUNT) {
                foreach (signs; 0 .. 4u) {
                    CoordSign signA = CoordSign.Minus;
                    CoordSign signB = CoordSign.Minus;
                    if ((signs & 1) != 0) {
                        signA = CoordSign.Plus;
                    }
                    if ((signs & 2) != 0) {
                        signB = CoordSign.Plus;
                    }
                    CoordsWithMargins edge;
                    edge.data = [TEST_EDGE_COORD, TEST_EDGE_COORD, TEST_EDGE_COORD];
                    edge.data[a] = marginCoord(TEST_DIMENSION, signA);
                    edge.data[b] = marginCoord(TEST_DIMENSION, signB);
                    CellHop viaA = hopRemaining(&graph, hopCell(&graph, chunk, edge, a));
                    CellHop viaB = hopRemaining(&graph, hopCell(&graph, chunk, edge, b));
                    bool same = viaA.chunk == viaB.chunk && viaA.coords == viaB.coords;
                    if (signA == CoordSign.Plus && signB == CoordSign.Plus) {
                        assert(!same);
                        valenceFiveEdges += 1;
                    } else {
                        assert(same);
                        valenceFourEdges += 1;
                    }
                }
            }
        }
    }
    assert(valenceFourEdges == VERTEX_COUNT * AXIS_COUNT * 3);
    assert(valenceFiveEdges == VERTEX_COUNT * AXIS_COUNT);
    graph.release();
}
