module common.character.place;

import core.stdc.math : fabsf, floorf;
import common.character.warp : chunkPointInNode, deepestVertex, gridJacobian;
import common.coords : CELL_NEIGHBOR_OFFSETS, ChunkAxisPermutation, ChunkDirection, CoordAxis, CoordSign, Coords;
import common.dodeca : SIDE_COUNT, Side, VERTEX_COUNT, Vertex, canonicalSides, nodeToDual, reflection;
import common.graph : Graph, NO_SLOT, ROOT_NODE;
import common.margins : neighborAxisPermutation;
import common.material : Material;
import common.math : MIsometry, MPoint, MVector;
import common.neighbors : chunkNeighborSlot;
import common.node : Chunk, ChunkLayout, ChunkSlot, ChunkState;
import common.position : Position;
import common.vector3 : magnitude, minus, plus, scaled;
import common.worldgen.generation : NodeState, Worldgen;
import common.worldgen.plane : Plane;

enum float RISE_HYSTERESIS_FRACTION = 0.1f;
enum uint AXIS_COUNT = 3;
enum uint NEIGHBOR_COUNT = 6;
enum uint BOX_CORNERS = 8;
enum float UP_PROBE_DISTANCE = 0.1f;
enum float UP_PROBE_MIN_GAIN = 0.05f;
enum ubyte TEST_DIMENSION = 12;
enum float TEST_POINT_TOLERANCE = 1e-4f;

immutable CoordSign[2] TEST_SIGNS = [CoordSign.minus, CoordSign.plus];

immutable float[3][2] TEST_FACE_POINTS = [
    [3.3f, 7.6f, 0.0f],
    [11.2f, 0.4f, 5.5f],
];

struct GridFrame {
    ubyte[3] axes = [0, 1, 2];
    byte[3] signs = [1, 1, 1];

    float[3] toGrid(float[3] v) const {
        float[3] result;
        foreach (i; 0 .. AXIS_COUNT) {
            result[axes[i]] = signs[i] * v[i];
        }
        return result;
    }

    float[3] toBody(float[3] v) const {
        float[3] result;
        foreach (i; 0 .. AXIS_COUNT) {
            result[i] = signs[i] * v[axes[i]];
        }
        return result;
    }

    GridFrame crossed(ChunkDirection direction, ChunkAxisPermutation permutation) const {
        GridFrame result;
        foreach (i; 0 .. AXIS_COUNT) {
            result.axes[i] = permutation.axes[axes[i]];
            result.signs[i] = flippedIf(signs[i], axes[i] == direction.axis);
        }
        return result;
    }
}

byte flippedIf(byte sign, bool isFlipped) {
    if (isFlipped) {
        return cast(byte) -sign;
    } else {
        return sign;
    }
}

struct Place {
    float[3] grid;
    ChunkSlot chunk;
    GridFrame frame;

    static Place fromPosition(ref const Graph graph, Position position) {
        MPoint!float point = position.local * MPoint!float.origin();
        Vertex vertex = deepestVertex(graph.layout, point);
        MVector!float dual = vertex.nodeToDual * point.vec;
        float[3] grid;
        foreach (axis; 0 .. AXIS_COUNT) {
            grid[axis] = graph.layout.dualToGrid(dual.data[axis] / dual.data[3]);
        }
        return Place(grid, ChunkSlot(graph.slotOf(position.node), vertex), GridFrame.init);
    }

    Place moved(float[3] bodyDisplacement) const {
        return Place(grid.plus(frame.toGrid(bodyDisplacement)), chunk, frame);
    }

    float[3] offsetTo(Place other) const {
        return frame.toBody(other.grid.minus(grid));
    }

    MPoint!float pointInNode(ref const ChunkLayout layout) const {
        return chunkPointInNode(chunk.vertex, [layout.gridToChunk(grid[0]), layout.gridToChunk(grid[1]), layout.gridToChunk(grid[2])]);
    }

    float[3][3] jacobian(ref const ChunkLayout layout, MIsometry!float local) const {
        return gridJacobian(layout, chunk.vertex.nodeToDual * local);
    }
}

struct Relocated {
    Place place;
    MIsometry!float toNode;
}

CoordSign exitSign(float coord) {
    if (coord < 0) {
        return CoordSign.minus;
    } else {
        return CoordSign.plus;
    }
}

int mirrorCoord(ubyte dimension, CoordSign sign) {
    if (sign == CoordSign.plus) {
        return 2 * dimension;
    } else {
        return 0;
    }
}

T[3] permuted(T)(ChunkAxisPermutation permutation, T[3] v) {
    T[3] result;
    foreach (i; 0 .. AXIS_COUNT) {
        result[permutation.axes[i]] = v[i];
    }
    return result;
}

bool isOutsideChunk(float coord, ubyte dimension) {
    return coord < 0 || coord > dimension;
}

bool isExitAxis(ref const Graph graph, Place place, size_t axis) {
    return isOutsideChunk(place.grid[axis], graph.layout.dimension) && graph.chunkNeighborSlot(place.chunk, ChunkDirection(cast(CoordAxis) axis, exitSign(place.grid[axis]))).slot != NO_SLOT;
}

size_t exitAxis(ref const Graph graph, Place place) {
    size_t axis = 0;
    while (axis < AXIS_COUNT && !graph.isExitAxis(place, axis)) {
        axis += 1;
    }
    return axis;
}

Relocated crossed(ref const Graph graph, Relocated current, ChunkDirection direction) {
    Place place = current.place;
    ChunkAxisPermutation permutation = neighborAxisPermutation(place.chunk.vertex, direction);
    float[3] mirrored = place.grid;
    mirrored[direction.axis] = mirrorCoord(graph.layout.dimension, direction.sign) - mirrored[direction.axis];
    Place next = Place(permuted(permutation, mirrored), graph.chunkNeighborSlot(place.chunk, direction), place.frame.crossed(direction, permutation));
    if (direction.sign == CoordSign.minus) {
        return Relocated(next, place.chunk.vertex.canonicalSides[direction.axis].reflection * current.toNode);
    } else {
        return Relocated(next, current.toNode);
    }
}

Relocated relocated(ref const Graph graph, Place start) {
    Relocated current = Relocated(start, MIsometry!float.identity());
    size_t axis = graph.exitAxis(current.place);
    while (axis < AXIS_COUNT) {
        current = graph.crossed(current, ChunkDirection(cast(CoordAxis) axis, exitSign(current.place.grid[axis])));
        axis = graph.exitAxis(current.place);
    }
    return current;
}

bool isInsideCells(int[3] cell, ubyte dimension) {
    return cell[0] >= 0 && cell[0] < dimension && cell[1] >= 0 && cell[1] < dimension && cell[2] >= 0 && cell[2] < dimension;
}

Coords coordsOf(int[3] cell) {
    return Coords([cast(ubyte) cell[0], cast(ubyte) cell[1], cast(ubyte) cell[2]]);
}

bool isCellOutside(int coord, ubyte dimension) {
    return coord < 0 || coord >= dimension;
}

bool isOnPathAcross(P)(ref const Graph graph, ref const P predicate, ChunkSlot chunk, int[3] cell, size_t axis) {
    ubyte dimension = graph.layout.dimension;
    if (!isCellOutside(cell[axis], dimension)) {
        return false;
    } else {
        CoordSign sign = exitSign(cell[axis]);
        ChunkDirection direction = ChunkDirection(cast(CoordAxis) axis, sign);
        int[3] mirrored = cell;
        mirrored[axis] = mirrorCoord(dimension, sign) - 1 - mirrored[axis];
        return graph.isOnAnyPath(predicate, graph.chunkNeighborSlot(chunk, direction), permuted(neighborAxisPermutation(chunk.vertex, direction), mirrored));
    }
}

bool isOnAnyPath(P)(ref const Graph graph, ref const P predicate, ChunkSlot chunk, int[3] cell) {
    if (chunk.slot == NO_SLOT) {
        return P.IS_MISSING_MATCH;
    } else if (isInsideCells(cell, graph.layout.dimension)) {
        return predicate.isMatch(*graph.chunkAt(chunk), chunk, coordsOf(cell), graph.layout.dimension);
    } else {
        size_t axis = 0;
        while (axis < AXIS_COUNT && !graph.isOnPathAcross(predicate, chunk, cell, axis)) {
            axis += 1;
        }
        return axis < AXIS_COUNT;
    }
}

struct Blocking {
    enum bool IS_MISSING_MATCH = true;

    bool isMatch(ref const Chunk chunk, ChunkSlot slot, Coords coords, ubyte dimension) const {
        return chunk.state != ChunkState.populated || chunk.voxels.get(coords.toIndex(dimension)) != Material.none;
    }
}

struct Unloaded {
    enum bool IS_MISSING_MATCH = true;

    bool isMatch(ref const Chunk chunk, ChunkSlot slot, Coords coords, ubyte dimension) const {
        return chunk.state != ChunkState.populated;
    }
}

struct SameCell {
    enum bool IS_MISSING_MATCH = false;
    ChunkSlot target;
    Coords coords;

    bool isMatch(ref const Chunk chunk, ChunkSlot slot, Coords cell, ubyte dimension) const {
        return slot == target && cell == coords;
    }
}

bool isCellBlocked(ref const Graph graph, ChunkSlot chunk, int[3] cell) {
    Blocking blocking;
    return graph.isOnAnyPath(blocking, chunk, cell);
}

struct ChartCell {
    float[3] center;
    bool isFound;
}

ChartCell nearestChartCell(ref const Graph graph, Place place, ChunkSlot target, Coords coords, int radius) {
    SameCell same = SameCell(target, coords);
    int[3] base = cellAt(place.grid);
    ChartCell best = ChartCell([0, 0, 0], false);
    float bestDistance = float.infinity;
    foreach (dz; -radius .. radius + 1) {
        foreach (dy; -radius .. radius + 1) {
            foreach (dx; -radius .. radius + 1) {
                int[3] cell = [base[0] + dx, base[1] + dy, base[2] + dz];
                float[3] center = [cell[0] + 0.5f, cell[1] + 0.5f, cell[2] + 0.5f];
                float[3] offset = center.minus(place.grid);
                float distance = offset[0] * offset[0] + offset[1] * offset[1] + offset[2] * offset[2];
                if (distance < bestDistance && graph.isOnAnyPath(same, place.chunk, cell)) {
                    best = ChartCell(center, true);
                    bestDistance = distance;
                }
            }
        }
    }
    return best;
}

int[3] cellAt(float[3] grid) {
    return [cast(int) floorf(grid[0]), cast(int) floorf(grid[1]), cast(int) floorf(grid[2])];
}

int[3] boxCorner(float[3] grid, float reach, uint corner) {
    float[3] point;
    foreach (axis; 0 .. AXIS_COUNT) {
        if ((corner & (1u << axis)) != 0) {
            point[axis] = grid[axis] + reach;
        } else {
            point[axis] = grid[axis] - reach;
        }
    }
    return cellAt(point);
}

bool isRegionLoaded(ref const Graph graph, Place place, float reach) {
    Unloaded unloaded;
    uint corner = 0;
    while (corner < BOX_CORNERS && !graph.isOnAnyPath(unloaded, place.chunk, boxCorner(place.grid, reach, corner))) {
        corner += 1;
    }
    return corner == BOX_CORNERS;
}

float[3] relativeUp(ref const Graph graph, Position position) {
    float[3] gradient = (position.local.inverse() * graph.nodeState(position.node).surface.scaledNormal).xyz();
    return gradient.scaled(1.0f / gradient.magnitude);
}

size_t dominantAxis(float[3] v) {
    size_t best = 0;
    foreach (axis; 1 .. AXIS_COUNT) {
        if (fabsf(v[axis]) > fabsf(v[best])) {
            best = axis;
        }
    }
    return best;
}

struct Rises {
    float[NEIGHBOR_COUNT] values;
    Place cell;
    bool isKnown;

    uint highest() const {
        uint best = 0;
        foreach (direction; 1 .. NEIGHBOR_COUNT) {
            if (values[direction] > values[best]) {
                best = direction;
            }
        }
        return best;
    }

    float[3] bodyDirection(uint direction) const {
        int[3] offset = CELL_NEIGHBOR_OFFSETS[direction];
        return cell.frame.toBody([offset[0], offset[1], offset[2]]);
    }
}

int clampedCell(float coord, ubyte dimension) {
    int cell = cast(int) floorf(coord);
    if (cell < 0) {
        return 0;
    } else if (cell >= dimension) {
        return dimension - 1;
    } else {
        return cell;
    }
}

Rises risesAt(ref const Graph graph, Place place) {
    Place at = graph.relocated(place).place;
    Rises rises = Rises([0, 0, 0, 0, 0, 0], at, graph.nodeAt(at.chunk.slot).hasState);
    if (rises.isKnown) {
        ubyte dimension = graph.layout.dimension;
        int[3] cell = [clampedCell(at.grid[0], dimension), clampedCell(at.grid[1], dimension), clampedCell(at.grid[2], dimension)];
        Plane surface = graph.nodeAt(at.chunk.slot).state.surface;
        float here = surface.distanceToCell(at.chunk.vertex, graph.layout, cell);
        foreach (direction; 0 .. NEIGHBOR_COUNT) {
            int[3] offset = CELL_NEIGHBOR_OFFSETS[direction];
            rises.values[direction] = surface.distanceToCell(at.chunk.vertex, graph.layout, [cell[0] + offset[0], cell[1] + offset[1], cell[2] + offset[2]]) - here;
        }
    }
    return rises;
}

uint directionOf(float[3] gridVector) {
    size_t axis = dominantAxis(gridVector);
    if (gridVector[axis] > 0) {
        return cast(uint)(2 * axis + 1);
    } else {
        return cast(uint)(2 * axis);
    }
}

float[3] gravityUp(ref const Graph graph, Place place, float[3] bodyUp, float footDepth) {
    Rises rises = graph.risesAt(place.moved(bodyUp.scaled(-footDepth)));
    uint best = rises.highest();
    uint current = directionOf(rises.cell.frame.toGrid(bodyUp));
    if (!rises.isKnown) {
        return bodyUp;
    } else if (rises.values[best] - rises.values[current] > RISE_HYSTERESIS_FRACTION * rises.values[best]) {
        return rises.bodyDirection(best);
    } else {
        return rises.bodyDirection(current);
    }
}

float[3] initialUp(ref const Graph graph, Place place) {
    Rises rises = graph.risesAt(place);
    return rises.bodyDirection(rises.highest());
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.makeTerrain());
    graph.ensureNodeState(ROOT_NODE);
    Position start = Position.origin();
    float[3] up = graph.relativeUp(start);
    const(NodeState)* state = graph.nodeState(ROOT_NODE);
    float startDistance = state.surface.distanceTo(start.local * MPoint!float.origin());
    MIsometry!float raised = start.local * MIsometry!float.fromDisplacement(up.scaled(UP_PROBE_DISTANCE));
    float endDistance = state.surface.distanceTo(raised * MPoint!float.origin());
    assert(endDistance > startDistance + UP_PROBE_MIN_GAIN);
    graph.release();
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.makeTerrain());
    uint root = graph.slotOf(ROOT_NODE);
    foreach (side; 0 .. SIDE_COUNT) {
        graph.ensureNeighborSlot(root, cast(Side) side);
    }
    foreach (vertexIndex; 0 .. VERTEX_COUNT) {
        foreach (axis; 0 .. AXIS_COUNT) {
            foreach (sign; TEST_SIGNS) {
                foreach (facePoint; TEST_FACE_POINTS) {
                    float[3] grid = facePoint;
                    grid[axis] = mirrorCoord(TEST_DIMENSION, sign) / 2;
                    Place place = Place(grid, ChunkSlot(root, cast(Vertex) vertexIndex), GridFrame.init);
                    Relocated across = graph.crossed(Relocated(place, MIsometry!float.identity()), ChunkDirection(cast(CoordAxis) axis, sign));
                    MPoint!float before = place.pointInNode(graph.layout);
                    MPoint!float after = across.toNode.inverse() * across.place.pointInNode(graph.layout);
                    foreach (k; 0 .. 4) {
                        assert(fabsf(before.vec.data[k] - after.vec.data[k]) < TEST_POINT_TOLERANCE);
                    }
                    float[3] outward = [0, 0, 0];
                    outward[axis] = sign;
                    float[3] inward = across.place.frame.toGrid(place.frame.toBody(outward));
                    size_t mapped = dominantAxis(inward);
                    assert(across.place.grid[mapped] == grid[axis]);
                    assert(inward[mapped] == -sign);
                }
            }
        }
    }
    graph.release();
}
