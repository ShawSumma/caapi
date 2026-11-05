module common.neighbors;

import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import base.vector3 : Vec3;
import common.graph : Graph, NodeId;
import common.material : isShownAgainst;
import common.node : Chunk, ChunkId, ChunkSlot, ChunkState, Occupancy, cellIndex;
import geometry.cube : AXIS_COUNT, Axis, AxisMap, DIRECTIONS, Direction, Sign, beyondBoundary, boundaryOf;
import geometry.honeycomb : Corner, across, axisMaps, faces;
import plugins.api.api : Material;

struct CellHop {
    Maybe!ChunkSlot chunk;
    Vec3!int cell;
    ChunkState state;

    bool isPopulated() const {
        return state == ChunkState.populated;
    }
}

Maybe!ChunkId chunkNeighborId(ref const Graph graph, ChunkId chunk, Direction direction) {
    if (direction.sign == Sign.plus) {
        return Maybe!ChunkId.of(ChunkId(chunk.node, chunk.corner.across[direction.axis]));
    } else {
        Maybe!NodeId neighbor = graph.neighbor(chunk.node, chunk.corner.faces[direction.axis]);
        if (neighbor.exists) {
            return Maybe!ChunkId.of(ChunkId(neighbor.value, chunk.corner));
        } else {
            return Maybe!ChunkId.init;
        }
    }
}

Maybe!ChunkSlot chunkNeighborSlot(ref const Graph graph, ChunkSlot chunk, Direction direction) {
    if (direction.sign == Sign.plus) {
        return Maybe!ChunkSlot.of(ChunkSlot(chunk.slot, chunk.corner.across[direction.axis]));
    } else {
        MaybeIndex!uint neighbor = graph.neighborSlot(chunk.slot, chunk.corner.faces[direction.axis]);
        if (neighbor.exists) {
            return Maybe!ChunkSlot.of(ChunkSlot(neighbor.value, chunk.corner));
        } else {
            return Maybe!ChunkSlot.init;
        }
    }
}

AxisMap neighborAxisMap(Corner corner, Direction direction) {
    if (direction.sign == Sign.plus) {
        return corner.axisMaps[direction.axis];
    } else {
        return AxisMap.init;
    }
}

Vec3!int acrossBorder(ubyte dimension, Corner corner, Vec3!int cell, Direction direction) {
    Vec3!int moved = cell;
    moved[direction.axis] = boundaryOf(dimension, direction.sign);
    return neighborAxisMap(corner, direction).apply(moved);
}

Direction borderCrossed(Vec3!int cell, size_t axis) {
    if (cell[axis] < 0) {
        return Direction(cast(Axis) axis, Sign.minus);
    } else {
        return Direction(cast(Axis) axis, Sign.plus);
    }
}

bool isOutside(ubyte dimension, int coordinate) {
    return coordinate < 0 || coordinate >= dimension;
}

bool isInside(ubyte dimension, Vec3!int cell) {
    return !isOutside(dimension, cell.x) && !isOutside(dimension, cell.y) && !isOutside(dimension, cell.z);
}

size_t indexIn(ubyte dimension, Vec3!int cell) {
    return cellIndex(dimension, cell.x, cell.y, cell.z);
}

CellHop hopCell(ref const Graph graph, ChunkSlot chunk, Vec3!int cell, size_t axis) {
    ubyte dimension = graph.layout.dimension;
    Direction direction = borderCrossed(cell, axis);
    Maybe!ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
    if (neighbor.exists) {
        return CellHop(neighbor, acrossBorder(dimension, chunk.corner, cell, direction), graph.chunks.at(neighbor.value).state);
    } else {
        return CellHop(neighbor, cell, ChunkState.fresh);
    }
}

Material materialNear(ref const Graph graph, ChunkSlot chunk, Vec3!int cell) {
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
            return graph.chunks.at(hop.chunk.value).voxels.at(indexIn(dimension, hop.cell));
        } else {
            return Material.none;
        }
    }
}

bool isOccupiedAcross(ref const Graph graph, ChunkSlot chunk, Vec3!int cell, size_t axis) {
    return isOutside(graph.layout.dimension, cell[axis]) && graph.isHopOccupied(graph.hopCell(chunk, cell, axis));
}

bool isCellOccupied(ref const Graph graph, ChunkSlot chunk, Vec3!int cell) {
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
        return graph.isCellOccupied(hop.chunk.value, hop.cell);
    } else {
        return !hop.chunk.exists || isAssumedOccupied(graph.chunks.at(hop.chunk.value).predicted);
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
    Maybe!ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
    if (!neighbor.exists || graph.chunks.at(neighbor.value).state != ChunkState.populated) {
        return false;
    } else if (graph.chunks.at(neighbor.value).voxels.isUniform()) {
        return isShownAgainst(graph.chunks.at(neighbor.value).voxels.fill, fill);
    } else {
        return true;
    }
}

bool isBorderingVoid(ref const Graph graph, ChunkSlot chunk) {
    foreach (direction; DIRECTIONS) {
        Maybe!ChunkSlot neighbor = graph.chunkNeighborSlot(chunk, direction);
        if (neighbor.exists && graph.chunks.at(neighbor.value).state == ChunkState.populated && graph.showsVoidAcross(chunk, direction, graph.chunks.at(neighbor.value))) {
            return true;
        }
    }
    return false;
}

bool showsVoidAcross(ref const Graph graph, ChunkSlot chunk, Direction direction, const(Chunk)* other) {
    if (other.voxels.isUniform()) {
        return other.voxels.isFilledWith(Material.none);
    } else {
        ubyte dimension = graph.layout.dimension;
        size_t u = (direction.axis + 1) % AXIS_COUNT;
        size_t v = (direction.axis + 2) % AXIS_COUNT;
        Vec3!int cell;
        cell[direction.axis] = beyondBoundary(dimension, direction.sign);
        foreach (j; 0 .. dimension) {
            foreach (i; 0 .. dimension) {
                cell[u] = i;
                cell[v] = j;
                if (other.voxels.at(indexIn(dimension, acrossBorder(dimension, chunk.corner, cell, direction))) == Material.none) {
                    return true;
                }
            }
        }
        return false;
    }
}

void touchHolders(ref const Graph graph, ChunkSlot chunk, Vec3!int cell, ref Array!ChunkSlot holders) {
    ubyte dimension = graph.layout.dimension;
    if (isInside(dimension, cell)) {
        holders.append(chunk);
    } else {
        foreach (axis; 0 .. AXIS_COUNT) {
            if (isOutside(dimension, cell[axis])) {
                CellHop hop = graph.hopCell(chunk, cell, axis);
                if (hop.isPopulated) {
                    graph.touchHolders(hop.chunk.value, hop.cell, holders);
                }
            }
        }
    }
}

void touchChunksReading(ref const Graph graph, ChunkSlot chunk, Vec3!int cell, ref Array!ChunkSlot holders) {
    ubyte dimension = graph.layout.dimension;
    Vec3!int outward;
    uint borderAxes = 0;
    foreach (axis; 0 .. AXIS_COUNT) {
        if (cell[axis] == 0) {
            outward[axis] = beyondBoundary(dimension, Sign.minus);
            borderAxes |= 1u << axis;
        } else if (cell[axis] == dimension - 1) {
            outward[axis] = beyondBoundary(dimension, Sign.plus);
            borderAxes |= 1u << axis;
        }
    }
    foreach (subset; 1 .. 2 ^^ AXIS_COUNT) {
        if ((subset & borderAxes) == subset) {
            Vec3!int pushed = cell;
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
        Vec3!int cell;
        foreach (axis; 0 .. AXIS_COUNT) {
            if ((corner & (1u << axis)) != 0) {
                cell[axis] = last;
            }
        }
        graph.touchChunksReading(chunk, cell, holders);
    }
}
