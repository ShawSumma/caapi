module common.character.features;

import core.math : sqrt;
import core.stdc.math : coshf, floorf;
import base.array : Array;
import base.numbers : clamped, isNan;
import base.units : Length, LocalBlock;
import base.vector3 : cross, dot, magnitude, minus, plus, scaled;
import common.character.chart : chunkPointInNode, gridJacobian, inverted;
import common.graph : Graph, NO_SLOT;
import common.material : Material;
import common.neighbors : chunkNeighborSlot, indexIn, isInside, materialNear;
import common.node : Chunk, ChunkLayout, ChunkSlot, ChunkState;
import common.position : Position;
import common.traversal : NodeVisit, VisitQueue;
import geometry.cube : Cell, DIRECTIONS, Direction, Sign;
import geometry.honeycomb : CORNER_COUNT, CUBE_RADIUS, Corner, FACE_COUNT, Face, NODE_RADIUS, cubeCenter, faces, mirror, nodeToCorner;
import geometry.lorentz : Motion, Point, Vec4;

enum uint FEATURE_MAX_NODES = 64;
enum int RANGE_MARGIN_CELLS = 1;
enum uint CELL_CORNERS = 8;
enum uint CELL_FACES = 6;
enum uint QUAD_CORNERS = 4;
enum float TEST_TOLERANCE = 1e-5f;

struct Quad {
    float[3][QUAD_CORNERS] corners;
    float[3] normal;

    float separation(float[3] point) const {
        return normal.dot(point.minus(corners[0]));
    }

    bool isAbove(float[3] point) const {
        uint index = 0;
        while (index < QUAD_CORNERS && normal.dot(corners[(index + 1) % QUAD_CORNERS].minus(corners[index]).cross(point.minus(corners[index]))) >= 0) {
            index += 1;
        }
        return index == QUAD_CORNERS;
    }

    float distanceTo(float[3] point) const {
        float[3] projected = point.minus(normal.scaled(separation(point)));
        if (isAbove(projected)) {
            return absolute(separation(point));
        } else {
            float nearest = float.infinity;
            foreach (index; 0 .. QUAD_CORNERS) {
                float distance = segmentDistance(corners[index], corners[(index + 1) % QUAD_CORNERS], point);
                if (distance < nearest) {
                    nearest = distance;
                }
            }
            return nearest;
        }
    }
}

struct Edge {
    float[3] start;
    float[3] end;
}

struct Hexahedron {
    float[3][CELL_CORNERS] corners;

    float[3] center() const {
        float[3] sum = [0, 0, 0];
        foreach (corner; corners) {
            sum = sum.plus(corner);
        }
        return sum.scaled(1.0f / CELL_CORNERS);
    }

    Quad face(size_t axis, int sign) const {
        size_t uAxis = (axis + 1) % 3;
        size_t vAxis = (axis + 2) % 3;
        uint base = sideBit(axis, sign > 0);
        Quad result;
        result.corners[0] = corners[base];
        result.corners[1] = corners[base | (1u << uAxis)];
        result.corners[2] = corners[base | (1u << uAxis) | (1u << vAxis)];
        result.corners[3] = corners[base | (1u << vAxis)];
        float[3] normal = unit(result.corners[1].minus(result.corners[0]).cross(result.corners[3].minus(result.corners[0])));
        float[3] faceCenter = result.corners[0].plus(result.corners[2]).scaled(0.5f);
        if (normal.dot(faceCenter.minus(center())) < 0) {
            float[3] second = result.corners[1];
            result.corners[1] = result.corners[3];
            result.corners[3] = second;
            normal = normal.scaled(-1);
        }
        result.normal = normal;
        return result;
    }

    float distanceTo(float[3] point) const {
        float nearest = float.infinity;
        bool isInside = true;
        foreach (axis; 0 .. 3) {
            foreach (side; 0 .. 2) {
                Quad candidate = face(axis, sideSign(side));
                if (candidate.separation(point) > 0) {
                    isInside = false;
                    float distance = candidate.distanceTo(point);
                    if (distance < nearest) {
                        nearest = distance;
                    }
                }
            }
        }
        if (isInside) {
            return 0;
        } else {
            return nearest;
        }
    }
}

struct LocalFrame {
    Motion!float toBody;

    float[3] klein(Point!float point) const {
        Vec4!float local = toBody * point.v;
        return [local.c[0] / local.c[3], local.c[1] / local.c[3], local.c[2] / local.c[3]];
    }

    Hexahedron cell(ref const ChunkLayout layout, Corner corner, int[3] cell) const {
        Hexahedron result;
        foreach (cellCorner; 0 .. CELL_CORNERS) {
            float[3] chunk;
            foreach (axis; 0 .. 3) {
                chunk[axis] = layout.gridToCube(cell[axis] + ((cellCorner >> axis) & 1));
            }
            result.corners[cellCorner] = klein(chunkPointInNode(corner, chunk));
        }
        return result;
    }
}

struct CellRange {
    int[3] low;
    int[3] high;

    bool isEmpty() const {
        return low[0] > high[0] || low[1] > high[1] || low[2] > high[2];
    }

    bool isTouching(Direction direction, ubyte dimension) const {
        if (direction.sign == Sign.plus) {
            return high[direction.axis] == dimension - 1;
        } else {
            return low[direction.axis] == 0;
        }
    }
}

struct Features {
    Array!Quad quads;
    Array!Edge edges;
    Array!(float[3]) corners;
    bool isLoaded;

    void release() {
        quads.release();
        edges.release();
        corners.release();
    }

    void collect(ref const Graph graph, Position body, Length reach) {
        quads.clear();
        edges.clear();
        corners.clear();
        isLoaded = true;
        visitCells(graph, body, reach, this);
    }

    void visitChunk(ref const Graph graph, LocalFrame frame, ChunkSlot slot, CellRange range) {
        ChunkCellsNear cells = ChunkCellsNear(&graph, slot, graph.chunks.at(slot));
        if (cells.chunk.state != ChunkState.populated || !graph.areNeighborsPopulated(slot, range)) {
            isLoaded = false;
        } else {
            foreach (x; range.low[0] .. range.high[0] + 1) {
                foreach (y; range.low[1] .. range.high[1] + 1) {
                    foreach (z; range.low[2] .. range.high[2] + 1) {
                        int[3] cell = [x, y, z];
                        if (cells.isSolid(cell, [0, 0, 0]) && cells.hasExposedFace(cell)) {
                            addCell(cells, frame.cell(graph.layout, slot.corner, cell), cell);
                        }
                    }
                }
            }
        }
    }

    void visitMissingNode(uint, Face) {
        isLoaded = false;
    }

    void addCell(ref const ChunkCellsNear cells, Hexahedron hexahedron, int[3] cell) {
        foreach (axis; 0 .. 3) {
            foreach (side; 0 .. 2) {
                int sign = sideSign(side);
                if (!cells.isSolid(cell, offsetAlong(axis, sign))) {
                    Quad quad = hexahedron.face(axis, sign);
                    quads.append(quad);
                    addBoundary(quad);
                }
            }
        }
    }

    void addBoundary(Quad quad) {
        foreach (index; 0 .. QUAD_CORNERS) {
            edges.append(Edge(quad.corners[index], quad.corners[(index + 1) % QUAD_CORNERS]));
            corners.append(quad.corners[index]);
        }
    }
}

struct CellOverlap {
    float[3][] centers;
    ChunkSlot target;
    Cell coords;
    float radius;
    bool isOverlapping;

    void visitMissingNode(uint, Face) {
    }

    void visitChunk(ref const Graph graph, LocalFrame frame, ChunkSlot slot, CellRange range) {
        int[3] cell = [coords.c[0], coords.c[1], coords.c[2]];
        bool isInRange = cell[0] >= range.low[0] && cell[0] <= range.high[0] && cell[1] >= range.low[1] && cell[1] <= range.high[1] && cell[2] >= range.low[2] && cell[2] <= range.high[2];
        if (slot == target && isInRange && !isOverlapping) {
            isOverlapping = isTouchingAny(frame.cell(graph.layout, slot.corner, cell), centers, radius);
        }
    }
}

struct BlockProbe {
    float[3] up;
    LocalBlock block;
    bool isFound;

    void visitMissingNode(uint, Face) {
    }

    void visitChunk(ref const Graph graph, LocalFrame frame, ChunkSlot slot, CellRange) {
        Motion!float toCorner = slot.corner.nodeToCorner * frame.toBody.inverse();
        float[3] grid = gridPoint(graph.layout, toCorner);
        if (!isFound && isInsideGrid(grid, graph.layout.dimension)) {
            float[3][3] absolutePerGrid = inverted(gridJacobian(graph.layout, toCorner));
            float height = 0;
            foreach (axis; 0 .. 3) {
                height += absolute(absolutePerGrid[0][axis] * up[0] + absolutePerGrid[1][axis] * up[1] + absolutePerGrid[2][axis] * up[2]);
            }
            block = LocalBlock(Length(height));
            isFound = true;
        }
    }
}

float[3] gridPoint(ref const ChunkLayout layout, Motion!float toCorner) {
    Vec4!float at = (toCorner * Point!float.origin()).v;
    return [layout.kleinToGrid(at.c[0] / at.c[3]), layout.kleinToGrid(at.c[1] / at.c[3]), layout.kleinToGrid(at.c[2] / at.c[3])];
}

bool isInsideGrid(float[3] grid, ubyte dimension) {
    return grid[0] >= 0 && grid[0] < dimension && grid[1] >= 0 && grid[1] < dimension && grid[2] >= 0 && grid[2] < dimension;
}

struct NodeSide {
    uint slot;
    Face side;
}

struct RequiredChunks {
    Array!ChunkSlot chunks;
    Array!NodeSide missing;

    void clear() {
        chunks.clear();
        missing.clear();
    }

    void release() {
        chunks.release();
        missing.release();
    }

    void visitMissingNode(uint slot, Face side) {
        missing.append(NodeSide(slot, side));
    }

    void visitChunk(ref const Graph graph, LocalFrame, ChunkSlot slot, CellRange range) {
        chunks.append(slot);
        foreach (direction; DIRECTIONS) {
            if (range.isTouching(direction, graph.layout.dimension)) {
                ChunkSlot neighbor = graph.chunkNeighborSlot(slot, direction);
                if (neighbor.slot == NO_SLOT) {
                    missing.append(NodeSide(slot.slot, slot.corner.faces[direction.axis]));
                } else {
                    chunks.append(neighbor);
                }
            }
        }
    }
}

void visitCells(V)(ref const Graph graph, Position body, Length reach, ref V visitor) {
    Vec4!float point = (body.local * Point!float.origin()).v;
    Motion!float bodyInverse = body.local.inverse();
    float nodeThreshold = coshf(reach.value + NODE_RADIUS + CUBE_RADIUS);
    float chunkThreshold = coshf(reach.value + CUBE_RADIUS);
    VisitQueue!FEATURE_MAX_NODES queue = VisitQueue!FEATURE_MAX_NODES.fromSlot(graph.slotOf(body.node));
    while (queue.hasNext()) {
        NodeVisit visit = queue.current();
        Vec4!float local = visit.inverse * point;
        LocalFrame frame = LocalFrame(bodyInverse * visit.inverse.inverse());
        foreach (index; 0 .. CORNER_COUNT) {
            Corner corner = cast(Corner) index;
            if (!(-local.minkowski(corner.cubeCenter.v) > chunkThreshold)) {
                CellRange range = cellRange(graph.layout, corner, local, reach);
                if (!range.isEmpty()) {
                    visitor.visitChunk(graph, frame, ChunkSlot(visit.slot, corner), range);
                }
            }
        }
        foreach (index; 0 .. FACE_COUNT) {
            Face side = cast(Face) index;
            if (graph.neighborSlot(visit.slot, side) == NO_SLOT && !((side.mirror * visit.inverse * point).c[3] > nodeThreshold)) {
                visitor.visitMissingNode(visit.slot, side);
            }
        }
        queue.expand(graph, visit, point, nodeThreshold);
    }
}

CellRange cellRange(ref const ChunkLayout layout, Corner corner, Vec4!float local, Length reach) {
    Motion!float toCorner = corner.nodeToCorner * Motion!float.shiftTo(Point!float(local));
    float[3] grid = gridPoint(layout, toCorner);
    float[3][3] jacobian = gridJacobian(layout, toCorner);
    CellRange range;
    foreach (axis; 0 .. 3) {
        float extent = jacobian[axis][0] * jacobian[axis][0] + jacobian[axis][1] * jacobian[axis][1] + jacobian[axis][2] * jacobian[axis][2];
        float span = sqrt(extent) * reach.value;
        if (isNan(grid[axis]) || isNan(span)) {
            range.low[axis] = 0;
            range.high[axis] = -1;
        } else {
            range.low[axis] = clampedCell(grid[axis] - span, layout.dimension) - RANGE_MARGIN_CELLS;
            range.high[axis] = clampedCell(grid[axis] + span, layout.dimension) + RANGE_MARGIN_CELLS;
            if (range.low[axis] < 0) {
                range.low[axis] = 0;
            }
            if (range.high[axis] > layout.dimension - 1) {
                range.high[axis] = layout.dimension - 1;
            }
        }
    }
    return range;
}

int clampedCell(float grid, ubyte dimension) {
    return cast(int) floorf(clamped(grid, -RANGE_MARGIN_CELLS - 1, dimension + RANGE_MARGIN_CELLS));
}

bool areNeighborsPopulated(ref const Graph graph, ChunkSlot slot, CellRange range) {
    uint index = 0;
    while (index < DIRECTIONS.length && !(range.isTouching(DIRECTIONS[index], graph.layout.dimension) && !graph.isNeighborPopulated(slot, DIRECTIONS[index]))) {
        index += 1;
    }
    return index == DIRECTIONS.length;
}

bool isNeighborPopulated(ref const Graph graph, ChunkSlot slot, Direction direction) {
    ChunkSlot neighbor = graph.chunkNeighborSlot(slot, direction);
    return neighbor.slot != NO_SLOT && graph.chunks.at(neighbor).state == ChunkState.populated;
}

// A chunk's cells and the ones just past its faces, which only the graph knows.
struct ChunkCellsNear {
    const(Graph)* graph;
    ChunkSlot slot;
    const(Chunk)* chunk;

    bool isSolid(int[3] cell, int[3] offset) const {
        int[3] at = [cell[0] + offset[0], cell[1] + offset[1], cell[2] + offset[2]];
        ubyte dimension = graph.layout.dimension;
        if (isInside(dimension, at)) {
            return chunk.voxels.at(indexIn(dimension, at)) != Material.none;
        } else {
            return (*graph).materialNear(slot, at) != Material.none;
        }
    }

    bool hasExposedFace(int[3] cell) const {
        uint face = 0;
        while (face < CELL_FACES && isSolid(cell, offsetAlong(face / 2, sideSign(face % 2)))) {
            face += 1;
        }
        return face < CELL_FACES;
    }
}

bool isTouchingAny(Hexahedron hexahedron, const(float[3])[] centers, float radius) {
    size_t index = 0;
    while (index < centers.length && !(hexahedron.distanceTo(centers[index]) < radius)) {
        index += 1;
    }
    return index < centers.length;
}

int[3] offsetAlong(size_t axis, int sign) {
    int[3] offset = [0, 0, 0];
    offset[axis] = sign;
    return offset;
}

uint sideBit(size_t axis, bool isHigh) {
    if (isHigh) {
        return 1u << axis;
    } else {
        return 0;
    }
}

int sideSign(int side) {
    if (side == 1) {
        return 1;
    } else {
        return -1;
    }
}

float absolute(float value) {
    if (value < 0) {
        return -value;
    } else {
        return value;
    }
}

float[3] unit(float[3] v) {
    return v.scaled(1.0f / v.magnitude);
}

float segmentDistance(float[3] start, float[3] end, float[3] point) {
    float[3] along = end.minus(start);
    float t = clamped(point.minus(start).dot(along) / along.dot(along), 0, 1);
    return point.minus(start.plus(along.scaled(t))).magnitude;
}

unittest {
    Hexahedron cube;
    foreach (corner; 0 .. CELL_CORNERS) {
        cube.corners[corner] = [cast(float)(corner & 1), cast(float)((corner >> 1) & 1), cast(float)((corner >> 2) & 1)];
    }
    Quad top = cube.face(1, 1);
    assert(top.normal[1] > 1 - TEST_TOLERANCE);
    float[3] above = [0.5f, 2.0f, 0.5f];
    assert(top.isAbove(above));
    float[3] aside = [1.5f, 2.0f, 0.5f];
    assert(!top.isAbove(aside));
    Quad bottom = cube.face(1, -1);
    assert(bottom.normal[1] < -1 + TEST_TOLERANCE);
    float[3] inside = [0.5f, 0.5f, 0.5f];
    assert(cube.distanceTo(inside) == 0);
    assert(absolute(cube.distanceTo(above) - 1) < TEST_TOLERANCE);
    float[3] diagonal = [2.0f, 2.0f, 0.5f];
    assert(absolute(cube.distanceTo(diagonal) - sqrt(2.0f)) < TEST_TOLERANCE);
}
