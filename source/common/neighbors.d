module common.neighbors;

import base.array : Array;
import common.graph : Graph, NO_SLOT, ROOT_NODE;
import common.material : Material, isShownAgainst;
import common.node : Chunk, ChunkId, ChunkSlot, ChunkState, Occupancy, cellIndex;
import common.worldgen.generation : Worldgen;
import geometry.cube : AXIS_COUNT, Axis, AxisMap, DIRECTIONS, Direction, Sign, boundaryOf;
import geometry.honeycomb : CORNER_COUNT, Corner, FACE_COUNT, Face, across, axisMaps, faces;

// Cells are named from a chunk with coordinates that may reach one step past its border, from -1 to the dimension;
// a cell past the border belongs to the neighbor across it.

enum ubyte TEST_DIMENSION = 4;
enum int TEST_EDGE_CELL = 2;

struct CellHop {
    ChunkSlot chunk;
    int[3] cell;
    bool isPopulated;
}

ChunkId chunkNeighborId(ref const Graph graph, ChunkId chunk, Direction direction) {
    if (direction.sign == Sign.plus) {
        return ChunkId(chunk.node, chunk.corner.across[direction.axis]);
    } else {
        return ChunkId(graph.neighbor(chunk.node, chunk.corner.faces[direction.axis]), chunk.corner);
    }
}

ChunkSlot chunkNeighborSlot(ref const Graph graph, ChunkSlot chunk, Direction direction) {
    if (direction.sign == Sign.minus) {
        return ChunkSlot(graph.neighborSlot(chunk.slot, chunk.corner.faces[direction.axis]), chunk.corner);
    } else {
        return ChunkSlot(chunk.slot, chunk.corner.across[direction.axis]);
    }
}

// Across a minus border the neighbor is the same corner of the next node, mirrored onto the same axes; across a
// plus border it is another corner of the same node, whose axes come in another order.
AxisMap neighborAxisMap(Corner corner, Direction direction) {
    if (direction.sign == Sign.plus) {
        return corner.axisMaps[direction.axis];
    } else {
        return AxisMap.init;
    }
}

// Where a cell one step past the border along the axis lies in the neighbor's own coordinates.
int[3] acrossBorder(ubyte dimension, Corner corner, int[3] cell, Direction direction) {
    int[3] moved = cell;
    moved[direction.axis] = boundaryOf(dimension, direction.sign);
    return neighborAxisMap(corner, direction).apply(moved);
}

Direction borderCrossed(int[3] cell, size_t axis) {
    return Direction(cast(Axis) axis, cell[axis] < 0 ? Sign.minus : Sign.plus);
}

bool isOutside(ubyte dimension, int coordinate) {
    return coordinate < 0 || coordinate >= dimension;
}

bool isInside(ubyte dimension, int[3] cell) {
    return !isOutside(dimension, cell[0]) && !isOutside(dimension, cell[1]) && !isOutside(dimension, cell[2]);
}

size_t indexIn(ubyte dimension, int[3] cell) {
    return cellIndex(dimension, cell[0], cell[1], cell[2]);
}

CellHop hopCell(ref const Graph graph, ChunkSlot chunk, int[3] cell, size_t axis) {
    ubyte dimension = graph.layout.dimension;
    Direction direction = borderCrossed(cell, axis);
    ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
    if (neighbor.slot == NO_SLOT) {
        return CellHop(neighbor, cell, false);
    } else {
        return CellHop(neighbor, acrossBorder(dimension, chunk.corner, cell, direction), graph.chunks.at(neighbor).state == ChunkState.populated);
    }
}

// Past one border, the cell's material, or none when the neighbor holding it is not loaded.
Material materialNear(ref const Graph graph, ChunkSlot chunk, int[3] cell) {
    ubyte dimension = graph.layout.dimension;
    if (isInside(dimension, cell)) {
        return graph.chunks.at(chunk).voxels.at(indexIn(dimension, cell));
    } else {
        uint axis = 0;
        while (!isOutside(dimension, cell[axis])) {
            axis += 1;
        }
        CellHop hop = graph.hopCell(chunk, cell, axis);
        if (hop.isPopulated) {
            return graph.chunks.at(hop.chunk).voxels.at(indexIn(dimension, hop.cell));
        } else {
            return Material.none;
        }
    }
}

bool isOccupiedAcross(ref const Graph graph, ChunkSlot chunk, int[3] cell, size_t axis) {
    return isOutside(graph.layout.dimension, cell[axis]) && graph.isHopOccupied(graph.hopCell(chunk, cell, axis));
}

// Whether something fills a cell past any number of borders, assuming what a chunk's prediction says while it is not
// loaded. A cell past two borders is reached by crossing either first, which lands in different chunks where more than
// four of them meet an edge, so it counts as filled when any route finds it filled.
bool isCellOccupied(ref const Graph graph, ChunkSlot chunk, int[3] cell) {
    ubyte dimension = graph.layout.dimension;
    if (isInside(dimension, cell)) {
        return graph.chunks.at(chunk).voxels.at(indexIn(dimension, cell)) != Material.none;
    } else {
        uint axis = 0;
        while (axis < AXIS_COUNT && !graph.isOccupiedAcross(chunk, cell, axis)) {
            axis += 1;
        }
        return axis < AXIS_COUNT;
    }
}

bool isHopOccupied(ref const Graph graph, CellHop hop) {
    if (hop.isPopulated) {
        return graph.isCellOccupied(hop.chunk, hop.cell);
    } else {
        return hop.chunk.slot == NO_SLOT || isAssumedOccupied(graph.chunks.at(hop.chunk).predicted);
    }
}

bool isAssumedOccupied(Occupancy predicted) {
    return predicted != Occupancy.empty;
}

bool isPredictionContradicted(ref const Chunk chunk) {
    if (chunk.voxels.isUniform()) {
        return !chunk.voxels.isFilledWith(Material.none) != isAssumedOccupied(chunk.predicted);
    } else {
        return true;
    }
}

// A chunk draws the faces that border its see-through cells, its border included, so one filled with something opaque
// draws nothing, and one filled with something see-through only draws what its neighbors show against it.
bool needsMesh(ref const Graph graph, ChunkSlot chunk) {
    const(Chunk)* own = graph.chunks.at(chunk);
    if (own.state != ChunkState.populated || own.voxels.isOpaqueFill()) {
        return false;
    } else if (!own.voxels.isUniform()) {
        return true;
    } else {
        uint direction = 0;
        while (direction < DIRECTIONS.length && !graph.showsAgainst(chunk, DIRECTIONS[direction], own.voxels.fill)) {
            direction += 1;
        }
        return direction < DIRECTIONS.length;
    }
}

bool showsAgainst(ref const Graph graph, ChunkSlot chunk, Direction direction, Material fill) {
    ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
    if (neighbor.slot == NO_SLOT || graph.chunks.at(neighbor).state != ChunkState.populated) {
        return false;
    } else if (graph.chunks.at(neighbor).voxels.isUniform()) {
        return isShownAgainst(graph.chunks.at(neighbor).voxels.fill, fill);
    } else {
        return true;
    }
}

// Whether a loaded neighbor has an empty cell against this chunk's border, which would show what is inside it.
bool isBorderingVoid(ref const Graph graph, ChunkSlot chunk) {
    ubyte dimension = graph.layout.dimension;
    bool isFound = false;
    foreach (direction; DIRECTIONS) {
        ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
        if (!isFound && neighbor.slot != NO_SLOT && graph.chunks.at(neighbor).state == ChunkState.populated) {
            const(Chunk)* other = graph.chunks.at(neighbor);
            if (other.voxels.isUniform()) {
                isFound = other.voxels.isFilledWith(Material.none);
            } else {
                size_t u = (direction.axis + 1) % AXIS_COUNT;
                size_t v = (direction.axis + 2) % AXIS_COUNT;
                int[3] cell;
                cell[direction.axis] = direction.sign == Sign.plus ? dimension : -1;
                foreach (j; 0 .. dimension) {
                    foreach (i; 0 .. dimension) {
                        cell[u] = i;
                        cell[v] = j;
                        isFound = isFound || other.voxels.at(indexIn(dimension, acrossBorder(dimension, chunk.corner, cell, direction))) == Material.none;
                    }
                }
            }
        }
    }
    return isFound;
}

// Collects the chunks holding a cell past any number of borders, through every route that reaches it.
void touchHolders(ref const Graph graph, ChunkSlot chunk, int[3] cell, ref Array!ChunkSlot holders) {
    ubyte dimension = graph.layout.dimension;
    if (isInside(dimension, cell)) {
        holders.append(chunk);
    } else {
        foreach (axis; 0 .. AXIS_COUNT) {
            if (isOutside(dimension, cell[axis])) {
                CellHop hop = graph.hopCell(chunk, cell, axis);
                if (hop.isPopulated) {
                    graph.touchHolders(hop.chunk, hop.cell, holders);
                }
            }
        }
    }
}

// Collects the chunks whose meshes read a cell on this chunk's border: those that hold it one step past their own
// border, for its faces, or past two or three, for the shading of nearby corners.
void touchChunksReading(ref const Graph graph, ChunkSlot chunk, int[3] cell, ref Array!ChunkSlot holders) {
    ubyte dimension = graph.layout.dimension;
    int[AXIS_COUNT] outward;
    uint borderAxes = 0;
    foreach (axis; 0 .. AXIS_COUNT) {
        if (cell[axis] == 0) {
            outward[axis] = -1;
            borderAxes |= 1u << axis;
        } else if (cell[axis] == dimension - 1) {
            outward[axis] = dimension;
            borderAxes |= 1u << axis;
        }
    }
    foreach (subset; 1 .. 2 ^^ AXIS_COUNT) {
        if ((subset & borderAxes) == subset) {
            int[3] pushed = cell;
            foreach (axis; 0 .. AXIS_COUNT) {
                if ((subset & (1u << axis)) != 0) {
                    pushed[axis] = outward[axis];
                }
            }
            graph.touchHolders(chunk, pushed, holders);
        }
    }
}

void touchChunksAround(ref const Graph graph, ChunkSlot chunk, ref Array!ChunkSlot holders) {
    int last = graph.layout.dimension - 1;
    foreach (corner; 0 .. 2 ^^ AXIS_COUNT) {
        int[3] cell;
        foreach (axis; 0 .. AXIS_COUNT) {
            cell[axis] = (corner & (1u << axis)) != 0 ? last : 0;
        }
        graph.touchChunksReading(chunk, cell, holders);
    }
}

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

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.makeTerrain());
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
                    bool isPlusA = (signs & 1) != 0;
                    bool isPlusB = (signs & 2) != 0;
                    int[3] edge = [TEST_EDGE_CELL, TEST_EDGE_CELL, TEST_EDGE_CELL];
                    edge[a] = isPlusA ? TEST_DIMENSION : -1;
                    edge[b] = isPlusB ? TEST_DIMENSION : -1;
                    CellHop viaA = graph.hopRemaining(graph.hopCell(chunk, edge, a));
                    CellHop viaB = graph.hopRemaining(graph.hopCell(chunk, edge, b));
                    bool isSame = viaA.chunk == viaB.chunk && viaA.cell == viaB.cell;
                    if (isPlusA && isPlusB) {
                        assert(!isSame);
                        valenceFiveEdges += 1;
                    } else {
                        assert(isSame);
                        valenceFourEdges += 1;
                    }
                }
            }
        }
        foreach (direction; DIRECTIONS) {
            int[3] past = [TEST_EDGE_CELL, 1, 0];
            past[direction.axis] = direction.sign == Sign.plus ? TEST_DIMENSION : -1;
            CellHop there = graph.hopCell(chunk, past, direction.axis);
            Axis back = neighborAxisMap(chunk.corner, direction).to[direction.axis];
            int[3] stepped = there.cell;
            stepped[back] = direction.sign == Sign.plus ? TEST_DIMENSION : -1;
            CellHop home = graph.hopCell(there.chunk, stepped, back);
            int[3] expected = past;
            expected[direction.axis] = boundaryOf(TEST_DIMENSION, direction.sign);
            assert(home.chunk == chunk && home.cell == expected);
        }
    }
    assert(valenceFourEdges == CORNER_COUNT * AXIS_COUNT * 3);
    assert(valenceFiveEdges == CORNER_COUNT * AXIS_COUNT);
    graph.release();
}
