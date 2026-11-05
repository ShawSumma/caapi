module common.character.features;

import core.math : sqrt;
import core.stdc.math : coshf, fabsf, floorf;
import base.array : Array;
import base.maybe : Maybe;
import base.numbers : clamped, higherOf, isNan, lowerOf;
import base.units : Length, LocalBlock;
import base.vector3 : Vec3, cross, dot, magnitude, minus, plus, scaled;
import common.character.chart : Matrix3, chunkPointInNode, gridJacobian, inverted;
import common.graph : Graph;
import common.neighbors : chunkNeighborSlot, indexIn, isInside, materialNear;
import common.node : Chunk, ChunkLayout, ChunkSlot, ChunkState;
import common.position : Position;
import common.traversal : NodeVisit, VisitQueue;
import geometry.cube : Cell, DIRECTIONS, Direction, Sign;
import geometry.honeycomb : CORNER_COUNT, CUBE_RADIUS, Corner, FACE_COUNT, Face, NODE_RADIUS, cubeCenter, faces, mirror, nodeToCorner;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : Material;

enum uint FEATURE_MAX_NODES = 64;
enum int RANGE_MARGIN_CELLS = 1;
enum uint CELL_CORNERS = 8;
enum uint CELL_FACES = 6;
enum uint QUAD_CORNERS = 4;

struct Quad {
    Vec3!float[QUAD_CORNERS] corners;
    Vec3!float normal;

    float separation(Vec3!float point) const {
        return normal.dot(point.minus(corners[0]));
    }

    bool isAbove(Vec3!float point) const {
        uint index = 0;
        while (index < QUAD_CORNERS && normal.dot(corners[(index + 1) % QUAD_CORNERS].minus(corners[index]).cross(point.minus(corners[index]))) >= 0) {
            index += 1;
        }
        return index == QUAD_CORNERS;
    }

    float distanceTo(Vec3!float point) const {
        Vec3!float projected = point.minus(normal.scaled(separation(point)));
        if (isAbove(projected)) {
            return fabsf(separation(point));
        } else {
            float nearest = segmentDistance(corners[0], corners[1], point);
            foreach (index; 1 .. QUAD_CORNERS) {
                nearest = lowerOf(segmentDistance(corners[index], corners[(index + 1) % QUAD_CORNERS], point), nearest);
            }
            return nearest;
        }
    }
}

struct Edge {
    Vec3!float start;
    Vec3!float end;
}

struct Hexahedron {
    Vec3!float[CELL_CORNERS] corners;

    Vec3!float center() const {
        Vec3!float sum = Vec3!float(0, 0, 0);
        foreach (corner; corners) {
            sum = sum.plus(corner);
        }
        return sum.scaled(1.0f / CELL_CORNERS);
    }

    Quad face(size_t axis, int sign) const {
        size_t uAxis = (axis + 1) % 3;
        size_t vAxis = (axis + 2) % 3;
        uint base = sideBit(axis, sign);
        Quad result;
        result.corners[0] = corners[base];
        result.corners[1] = corners[base | (1u << uAxis)];
        result.corners[2] = corners[base | (1u << uAxis) | (1u << vAxis)];
        result.corners[3] = corners[base | (1u << vAxis)];
        Vec3!float normal = unit(result.corners[1].minus(result.corners[0]).cross(result.corners[3].minus(result.corners[0])));
        Vec3!float faceCenter = result.corners[0].plus(result.corners[2]).scaled(0.5f);
        if (normal.dot(faceCenter.minus(center())) < 0) {
            Vec3!float second = result.corners[1];
            result.corners[1] = result.corners[3];
            result.corners[3] = second;
            normal = normal.scaled(-1);
        }
        result.normal = normal;
        return result;
    }

    float distanceTo(Vec3!float point) const {
        float nearest = 0;
        uint outside = 0;
        foreach (axis; 0 .. 3) {
            foreach (side; 0 .. 2) {
                Quad candidate = face(axis, sideSign(side));
                if (candidate.separation(point) > 0) {
                    float distance = candidate.distanceTo(point);
                    if (outside == 0) {
                        nearest = distance;
                    }
                    outside += 1;
                    nearest = lowerOf(distance, nearest);
                }
            }
        }
        return nearest;
    }
}

struct LocalFrame {
    Motion!float toBody;

    Vec3!float klein(Point!float point) const {
        Vec4!float local = toBody * point.v;
        return Vec3!float(local.c[0] / local.c[3], local.c[1] / local.c[3], local.c[2] / local.c[3]);
    }

    Hexahedron cell(ref const ChunkLayout layout, Corner corner, Vec3!int cell) const {
        Hexahedron result;
        foreach (cellCorner; 0 .. CELL_CORNERS) {
            Vec3!float chunk;
            foreach (axis; 0 .. 3) {
                chunk[axis] = layout.gridToCube(cell[axis] + ((cellCorner >> axis) & 1));
            }
            result.corners[cellCorner] = klein(chunkPointInNode(corner, chunk));
        }
        return result;
    }
}

struct CellRange {
    Vec3!int low;
    Vec3!int high;

    bool isEmpty() const {
        return low.x > high.x || low.y > high.y || low.z > high.z;
    }

    bool contains(Vec3!int cell) const {
        return cell.x >= low.x && cell.x <= high.x && cell.y >= low.y && cell.y <= high.y && cell.z >= low.z && cell.z <= high.z;
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
    Array!(Vec3!float) corners;
    uint unloaded;

    bool isLoaded() const {
        return unloaded == 0;
    }

    void release() {
        quads.release();
        edges.release();
        corners.release();
    }

    void collect(ref const Graph graph, Position body, Length reach) {
        quads.clear();
        edges.clear();
        corners.clear();
        unloaded = 0;
        visitCells(graph, body, reach, this);
    }

    void visitChunk(ref const Graph graph, LocalFrame frame, ChunkSlot slot, CellRange range) {
        ChunkCellsNear cells = ChunkCellsNear(&graph, slot, graph.chunks.at(slot));
        if (cells.chunk.state != ChunkState.populated || !graph.areNeighborsPopulated(slot, range)) {
            unloaded += 1;
        } else {
            foreach (x; range.low.x .. range.high.x + 1) {
                foreach (y; range.low.y .. range.high.y + 1) {
                    foreach (z; range.low.z .. range.high.z + 1) {
                        Vec3!int cell = Vec3!int(x, y, z);
                        if (cells.isSolid(cell, Vec3!int(0, 0, 0)) && cells.hasExposedFace(cell)) {
                            addCell(cells, frame.cell(graph.layout, slot.corner, cell), cell);
                        }
                    }
                }
            }
        }
    }

    void visitMissingNode(uint, Face) {
        unloaded += 1;
    }

    void addCell(ref const ChunkCellsNear cells, Hexahedron hexahedron, Vec3!int cell) {
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
    Vec3!float[] centers;
    ChunkSlot target;
    Cell coords;
    float radius;
    uint overlaps;

    void visitMissingNode(uint, Face) {
    }

    void visitChunk(ref const Graph graph, LocalFrame frame, ChunkSlot slot, CellRange range) {
        Vec3!int cell = coords.as!int();
        if (slot == target && range.contains(cell) && overlaps == 0 && isTouchingAny(frame.cell(graph.layout, slot.corner, cell), centers, radius)) {
            overlaps += 1;
        }
    }
}

struct BlockProbe {
    Vec3!float up;
    Maybe!LocalBlock block;

    void visitMissingNode(uint, Face) {
    }

    void visitChunk(ref const Graph graph, LocalFrame frame, ChunkSlot slot, CellRange) {
        Motion!float toCorner = slot.corner.nodeToCorner * frame.toBody.inverse();
        Vec3!float grid = gridPoint(graph.layout, toCorner);
        if (!block.exists && isInsideGrid(grid, graph.layout.dimension)) {
            Matrix3 absolutePerGrid = inverted(gridJacobian(graph.layout, toCorner));
            float height = 0;
            foreach (axis; 0 .. 3) {
                height += fabsf(absolutePerGrid.x[axis] * up.x + absolutePerGrid.y[axis] * up.y + absolutePerGrid.z[axis] * up.z);
            }
            block = Maybe!LocalBlock.of(LocalBlock(Length(height)));
        }
    }
}

Vec3!float gridPoint(ref const ChunkLayout layout, Motion!float toCorner) {
    Vec4!float at = (toCorner * Point!float.origin()).v;
    return Vec3!float(layout.kleinToGrid(at.c[0] / at.c[3]), layout.kleinToGrid(at.c[1] / at.c[3]), layout.kleinToGrid(at.c[2] / at.c[3]));
}

bool isInsideGrid(Vec3!float grid, ubyte dimension) {
    return grid.x >= 0 && grid.x < dimension && grid.y >= 0 && grid.y < dimension && grid.z >= 0 && grid.z < dimension;
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
                Maybe!ChunkSlot neighbor = graph.chunkNeighborSlot(slot, direction);
                if (neighbor.exists) {
                    chunks.append(neighbor.value);
                } else {
                    missing.append(NodeSide(slot.slot, slot.corner.faces[direction.axis]));
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
    VisitQueue!FEATURE_MAX_NODES queue = VisitQueue!FEATURE_MAX_NODES.fromSlot(graph.slotOf(body.node).value);
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
            if (!graph.neighborSlot(visit.slot, side).exists && !((side.mirror * visit.inverse * point).c[3] > nodeThreshold)) {
                visitor.visitMissingNode(visit.slot, side);
            }
        }
        queue.expand(graph, visit, point, nodeThreshold);
    }
}

CellRange cellRange(ref const ChunkLayout layout, Corner corner, Vec4!float local, Length reach) {
    Motion!float toCorner = corner.nodeToCorner * Motion!float.shiftTo(Point!float(local));
    Vec3!float grid = gridPoint(layout, toCorner);
    Matrix3 jacobian = gridJacobian(layout, toCorner);
    CellRange range;
    foreach (axis; 0 .. 3) {
        float extent = jacobian[axis].dot(jacobian[axis]);
        float span = sqrt(extent) * reach.value;
        if (isNan(grid[axis]) || isNan(span)) {
            range.low[axis] = 0;
            range.high[axis] = -1;
        } else {
            range.low[axis] = higherOf(clampedCell(grid[axis] - span, layout.dimension) - RANGE_MARGIN_CELLS, 0);
            range.high[axis] = lowerOf(clampedCell(grid[axis] + span, layout.dimension) + RANGE_MARGIN_CELLS, layout.dimension - 1);
        }
    }
    return range;
}

int clampedCell(float grid, ubyte dimension) {
    return cast(int) floorf(clamped!float(grid, -RANGE_MARGIN_CELLS - 1, dimension + RANGE_MARGIN_CELLS));
}

bool areNeighborsPopulated(ref const Graph graph, ChunkSlot slot, CellRange range) {
    uint index = 0;
    while (index < DIRECTIONS.length && !(range.isTouching(DIRECTIONS[index], graph.layout.dimension) && !graph.isNeighborPopulated(slot, DIRECTIONS[index]))) {
        index += 1;
    }
    return index == DIRECTIONS.length;
}

bool isNeighborPopulated(ref const Graph graph, ChunkSlot slot, Direction direction) {
    Maybe!ChunkSlot neighbor = graph.chunkNeighborSlot(slot, direction);
    return neighbor.exists && graph.chunks.at(neighbor.value).state == ChunkState.populated;
}

struct ChunkCellsNear {
    const(Graph)* graph;
    ChunkSlot slot;
    const(Chunk)* chunk;

    bool isSolid(Vec3!int cell, Vec3!int offset) const {
        Vec3!int at = Vec3!int(cell.x + offset.x, cell.y + offset.y, cell.z + offset.z);
        ubyte dimension = graph.layout.dimension;
        if (isInside(dimension, at)) {
            return chunk.voxels.at(indexIn(dimension, at)) != Material.none;
        } else {
            return (*graph).materialNear(slot, at) != Material.none;
        }
    }

    bool hasExposedFace(Vec3!int cell) const {
        uint face = 0;
        while (face < CELL_FACES && isSolid(cell, offsetAlong(face / 2, sideSign(face % 2)))) {
            face += 1;
        }
        return face < CELL_FACES;
    }
}

bool isTouchingAny(Hexahedron hexahedron, const(Vec3!float)[] centers, float radius) {
    size_t index = 0;
    while (index < centers.length && !(hexahedron.distanceTo(centers[index]) < radius)) {
        index += 1;
    }
    return index < centers.length;
}

Vec3!int offsetAlong(size_t axis, int sign) {
    Vec3!int offset = Vec3!int(0, 0, 0);
    offset[axis] = sign;
    return offset;
}

uint sideBit(size_t axis, int sign) {
    if (sign > 0) {
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

Vec3!float unit(Vec3!float v) {
    return v.scaled(1.0f / v.magnitude);
}

float segmentDistance(Vec3!float start, Vec3!float end, Vec3!float point) {
    Vec3!float along = end.minus(start);
    float t = clamped(point.minus(start).dot(along) / along.dot(along), 0.0f, 1.0f);
    return point.minus(start.plus(along.scaled(t))).magnitude;
}
