module common.chunk_neighbors;

import common.dodeca : SIDE_COUNT, Side, VERTEX_COUNT, Vertex, adjacentVertices, canonicalSides;
import common.graph : Graph, NO_SLOT, ROOT_NODE;
import common.margins : CoordsWithMargins, boundaryCoordWithMargins, marginCoord, neighborAxisPermutation;
import common.node : Chunk, ChunkSlot, ChunkState, Occupancy;
import common.voxel_math : ChunkDirection, CoordAxis, CoordSign;
import common.world : Material;

enum uint AXIS_COUNT = 3;
enum ubyte TEST_DIMENSION = 4;
enum ubyte TEST_EDGE_COORD = 2;

struct CellHop {
    CoordsWithMargins coords;
    ChunkSlot chunk;
    bool isPopulated;
}

ChunkSlot chunkNeighborSlot(const(Graph)* graph, ChunkSlot chunk, ChunkDirection direction) {
    if (direction.sign == CoordSign.Minus) {
        return ChunkSlot(graph.neighborSlot(chunk.slot, chunk.vertex.canonicalSides[direction.axis]), chunk.vertex);
    } else {
        return ChunkSlot(chunk.slot, chunk.vertex.adjacentVertices[direction.axis]);
    }
}

bool isOutsideInterior(ubyte dimension, ubyte coord) {
    return coord == 0 || coord == dimension + 1;
}

bool isInteriorCell(ubyte dimension, CoordsWithMargins coords) {
    foreach (axis; 0 .. AXIS_COUNT) {
        if (isOutsideInterior(dimension, coords.data[axis])) {
            return false;
        }
    }
    return true;
}

CoordSign marginSign(ubyte coord) {
    if (coord == 0) {
        return CoordSign.Minus;
    } else {
        return CoordSign.Plus;
    }
}

CellHop hopCell(const(Graph)* graph, ChunkSlot chunk, CoordsWithMargins coords, size_t axis) {
    CoordSign sign = marginSign(coords.data[axis]);
    ChunkDirection direction = ChunkDirection(cast(CoordAxis) axis, sign);
    ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
    if (neighbor.slot == NO_SLOT) {
        return CellHop(CoordsWithMargins.init, neighbor, false);
    } else {
        CoordsWithMargins moved = coords;
        moved.data[axis] = boundaryCoordWithMargins(graph.layout.dimension, sign);
        CoordsWithMargins permuted = neighborAxisPermutation(chunk.vertex, direction).apply(moved);
        return CellHop(permuted, neighbor, graph.chunkAt(neighbor).state == ChunkState.Populated);
    }
}

bool isCellOccupied(const(Graph)* graph, ChunkSlot chunk, CoordsWithMargins coords) {
    ubyte dimension = graph.layout.dimension;
    if (isInteriorCell(dimension, coords)) {
        return graph.chunkAt(chunk).voxels.get(coords.toIndex(dimension)) != Material.Void;
    } else {
        foreach (axis; 0 .. AXIS_COUNT) {
            if (isOutsideInterior(dimension, coords.data[axis]) && isHopOccupied(graph, hopCell(graph, chunk, coords, axis))) {
                return true;
            }
        }
        return false;
    }
}

bool isHopOccupied(const(Graph)* graph, CellHop hop) {
    if (hop.isPopulated) {
        return isCellOccupied(graph, hop.chunk, hop.coords);
    } else {
        return hop.chunk.slot == NO_SLOT || isAssumedOccupied(graph.chunkAt(hop.chunk).predicted);
    }
}

bool isAssumedOccupied(Occupancy predicted) {
    return predicted != Occupancy.empty;
}

bool isPredictionContradicted(const(Chunk)* chunk) {
    if (chunk.voxels.isSolid()) {
        return (chunk.voxels.solidMaterial != Material.Void) != isAssumedOccupied(chunk.predicted);
    } else {
        return true;
    }
}

void touchHolders(Graph* graph, ChunkSlot chunk, CoordsWithMargins coords) {
    ubyte dimension = graph.layout.dimension;
    if (isInteriorCell(dimension, coords)) {
        graph.markChanged(chunk);
    } else {
        foreach (axis; 0 .. AXIS_COUNT) {
            if (isOutsideInterior(dimension, coords.data[axis])) {
                CellHop hop = hopCell(graph, chunk, coords, axis);
                if (hop.isPopulated) {
                    touchHolders(graph, hop.chunk, hop.coords);
                }
            }
        }
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
            if ((corner & (1u << axis)) != 0) {
                cell.data[axis] = boundaryCoordWithMargins(dimension, CoordSign.Plus);
            } else {
                cell.data[axis] = boundaryCoordWithMargins(dimension, CoordSign.Minus);
            }
        }
        touchChunksReading(graph, chunk, cell);
    }
}

CellHop hopRemaining(const(Graph)* graph, CellHop hop) {
    foreach_reverse (axis; 0 .. AXIS_COUNT) {
        if (isOutsideInterior(graph.layout.dimension, hop.coords.data[axis])) {
            return hopCell(graph, hop.chunk, hop.coords, axis);
        }
    }
    return hop;
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION);
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
                    immutable bool isSame = viaA.chunk == viaB.chunk && viaA.coords == viaB.coords;
                    if (signA == CoordSign.Plus && signB == CoordSign.Plus) {
                        assert(!isSame);
                        valenceFiveEdges += 1;
                    } else {
                        assert(isSame);
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
