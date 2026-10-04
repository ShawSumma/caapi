module common.neighbors;

import common.coords : ChunkDirection, CoordAxis, CoordSign;
import common.dodeca : SIDE_COUNT, Side, VERTEX_COUNT, Vertex, adjacentVertices, canonicalSides;
import common.graph : Graph, NO_SLOT, ROOT_NODE;
import common.margins : CoordsWithMargins, boundaryCoordWithMargins, marginCoord, neighborAxisPermutation;
import common.material : Material;
import common.node : Chunk, ChunkSlot, ChunkState, Occupancy;

enum uint AXIS_COUNT = 3;
enum ubyte TEST_DIMENSION = 4;
enum ubyte TEST_EDGE_COORD = 2;

struct CellHop {
    CoordsWithMargins coords;
    ChunkSlot chunk;
    bool isPopulated;
}

ChunkSlot chunkNeighborSlot(ref const Graph graph, ChunkSlot chunk, ChunkDirection direction) {
    if (direction.sign == CoordSign.minus) {
        return ChunkSlot(graph.neighborSlot(chunk.slot, chunk.vertex.canonicalSides[direction.axis]), chunk.vertex);
    } else {
        return ChunkSlot(chunk.slot, chunk.vertex.adjacentVertices[direction.axis]);
    }
}

bool isOutsideInterior(ubyte dimension, ubyte coord) {
    return coord == 0 || coord == dimension + 1;
}

bool isInteriorCell(ubyte dimension, CoordsWithMargins coords) {
    uint axis = 0;
    while (axis < AXIS_COUNT && !isOutsideInterior(dimension, coords.data[axis])) {
        axis += 1;
    }
    return axis == AXIS_COUNT;
}

CoordSign marginSign(ubyte coord) {
    if (coord == 0) {
        return CoordSign.minus;
    } else {
        return CoordSign.plus;
    }
}

CellHop hopCell(ref const Graph graph, ChunkSlot chunk, CoordsWithMargins coords, size_t axis) {
    CoordSign sign = marginSign(coords.data[axis]);
    ChunkDirection direction = ChunkDirection(cast(CoordAxis) axis, sign);
    ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
    if (neighbor.slot == NO_SLOT) {
        return CellHop(CoordsWithMargins.init, neighbor, false);
    } else {
        CoordsWithMargins moved = coords;
        moved.data[axis] = boundaryCoordWithMargins(graph.layout.dimension, sign);
        CoordsWithMargins permuted = neighborAxisPermutation(chunk.vertex, direction).apply(moved);
        return CellHop(permuted, neighbor, graph.chunkAt(neighbor).state == ChunkState.populated);
    }
}

bool isOccupiedAcross(ref const Graph graph, ChunkSlot chunk, CoordsWithMargins coords, size_t axis) {
    return isOutsideInterior(graph.layout.dimension, coords.data[axis]) && graph.isHopOccupied(graph.hopCell(chunk, coords, axis));
}

bool isCellOccupied(ref const Graph graph, ChunkSlot chunk, CoordsWithMargins coords) {
    ubyte dimension = graph.layout.dimension;
    if (isInteriorCell(dimension, coords)) {
        return graph.chunkAt(chunk).voxels.get(coords.toIndex(dimension)) != Material.none;
    } else {
        uint axis = 0;
        while (axis < AXIS_COUNT && !graph.isOccupiedAcross(chunk, coords, axis)) {
            axis += 1;
        }
        return axis < AXIS_COUNT;
    }
}

bool isHopOccupied(ref const Graph graph, CellHop hop) {
    if (hop.isPopulated) {
        return graph.isCellOccupied(hop.chunk, hop.coords);
    } else {
        return hop.chunk.slot == NO_SLOT || isAssumedOccupied(graph.chunkAt(hop.chunk).predicted);
    }
}

bool isAssumedOccupied(Occupancy predicted) {
    return predicted != Occupancy.empty;
}

bool isPredictionContradicted(ref const Chunk chunk) {
    if (chunk.voxels.isSolid()) {
        return (chunk.voxels.solidMaterial != Material.none) != isAssumedOccupied(chunk.predicted);
    } else {
        return true;
    }
}

void touchHolders(ref Graph graph, ChunkSlot chunk, CoordsWithMargins coords) {
    ubyte dimension = graph.layout.dimension;
    if (isInteriorCell(dimension, coords)) {
        graph.markChanged(chunk);
    } else {
        foreach (axis; 0 .. AXIS_COUNT) {
            if (isOutsideInterior(dimension, coords.data[axis])) {
                CellHop hop = graph.hopCell(chunk, coords, axis);
                if (hop.isPopulated) {
                    graph.touchHolders(hop.chunk, hop.coords);
                }
            }
        }
    }
}

void touchChunksReading(ref Graph graph, ChunkSlot chunk, CoordsWithMargins cell) {
    ubyte dimension = graph.layout.dimension;
    ubyte[AXIS_COUNT] margins;
    uint boundaryAxes = 0;
    foreach (axis; 0 .. AXIS_COUNT) {
        if (cell.data[axis] == boundaryCoordWithMargins(dimension, CoordSign.minus)) {
            margins[axis] = marginCoord(dimension, CoordSign.minus);
            boundaryAxes |= 1u << axis;
        } else if (cell.data[axis] == boundaryCoordWithMargins(dimension, CoordSign.plus)) {
            margins[axis] = marginCoord(dimension, CoordSign.plus);
            boundaryAxes |= 1u << axis;
        }
    }
    foreach (subset; 1 .. 2 ^^ AXIS_COUNT) {
        if ((subset & boundaryAxes) == subset) {
            CoordsWithMargins pushed = cell;
            foreach (axis; 0 .. AXIS_COUNT) {
                if ((subset & (1u << axis)) != 0) {
                    pushed.data[axis] = margins[axis];
                }
            }
            graph.touchHolders(chunk, pushed);
        }
    }
}

void touchChunksAround(ref Graph graph, ChunkSlot chunk) {
    ubyte dimension = graph.layout.dimension;
    foreach (corner; 0 .. 2 ^^ AXIS_COUNT) {
        CoordsWithMargins cell;
        foreach (axis; 0 .. AXIS_COUNT) {
            if ((corner & (1u << axis)) != 0) {
                cell.data[axis] = boundaryCoordWithMargins(dimension, CoordSign.plus);
            } else {
                cell.data[axis] = boundaryCoordWithMargins(dimension, CoordSign.minus);
            }
        }
        graph.touchChunksReading(chunk, cell);
    }
}

CellHop hopRemaining(ref const Graph graph, CellHop hop) {
    uint axis = AXIS_COUNT;
    while (axis > 0 && !isOutsideInterior(graph.layout.dimension, hop.coords.data[axis - 1])) {
        axis -= 1;
    }
    if (axis == 0) {
        return hop;
    } else {
        return graph.hopCell(hop.chunk, hop.coords, axis - 1);
    }
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
                    CoordSign signA = signFromBit(signs & 1);
                    CoordSign signB = signFromBit(signs & 2);
                    CoordsWithMargins edge;
                    edge.data = [TEST_EDGE_COORD, TEST_EDGE_COORD, TEST_EDGE_COORD];
                    edge.data[a] = marginCoord(TEST_DIMENSION, signA);
                    edge.data[b] = marginCoord(TEST_DIMENSION, signB);
                    CellHop viaA = graph.hopRemaining(graph.hopCell(chunk, edge, a));
                    CellHop viaB = graph.hopRemaining(graph.hopCell(chunk, edge, b));
                    bool isSame = viaA.chunk == viaB.chunk && viaA.coords == viaB.coords;
                    if (signA == CoordSign.plus && signB == CoordSign.plus) {
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

CoordSign signFromBit(uint bit) {
    if (bit != 0) {
        return CoordSign.plus;
    } else {
        return CoordSign.minus;
    }
}
