module common.worldgen.building;

import core.stdc.math : coshf;
import common.array : Array;
import common.dodeca : VERTEX_COUNT, Vertex, chunkToNode;
import common.graph : Graph, NodeId;
import common.material : Material;
import common.math : MIsometry, MPoint, MVector;
import common.node : ChunkLayout;
import common.position : Position;
import common.traversal : NearbyNode, NearbyScratch;
import common.units : Length;
import common.worldgen.generation : StructureKind, StructureWorld, Worldgen;
import common.worldgen.tower : ALONG_BRIDGE, BOX_HALF_CELLS, ColumnChunk, ColumnSpot, FOUNDATION_CELLS, LineRole, MAX_STRUCTURE_LINES, NodeStructure, STAIR_START, STORY_CELLS, StructureLine, StructurePlan, TOWER_PALETTES, TowerPalette, columnPoint, edgeCells, isDoor, isStairRun, isStairwell;

enum uint MAX_LINES_AT_VERTEX = 3;
enum int HALL_ROOF = 2 * STORY_CELLS;
enum int PARAPET_CELLS = 2;
enum int RAIL_CELLS = 2;
enum int HALL_WINDOW_OFFSET = 2;
enum int WINDOW_INSET = 1;
enum int WINDOW_WIDTH = 2;
enum int FIRST_BALCONY_STORY = 3;
enum int BALCONY_DEPTH = 2;
enum int BALCONY_WIDTH = 4;
enum ubyte TEST_DIMENSION = 12;
enum float TEST_RADIUS = 3.0f;
enum Length TEST_TOLERANCE = Length(0.01f);
immutable int[3][4] TEST_CELLS = [
    [0, 0, 0],
    [3, 1, 2],
    [11, 5, 0],
    [2, 11, 9],
];
immutable StructureKind[2] TEST_KINDS = [
    StructureKind.tower,
    StructureKind.crown,
];

enum Stamp : ubyte {
    none,
    empty,
    wall,
    floor,
    trim,
}

struct NodeCells {
    ubyte dimension;

    int cellsPerChunk() const {
        return dimension * dimension * dimension;
    }

    int cellCount() const {
        return VERTEX_COUNT * cellsPerChunk();
    }

    int cellIndex(Vertex vertex, int[3] cell) const {
        return vertex * cellsPerChunk() + (cell[0] * dimension + cell[1]) * dimension + cell[2];
    }
}

struct CrownCorner {
    bool isDoorOnAcrossPlane;
    bool isDoorOnAlongPlane;

    static CrownCorner fromLine(ref const StructureLine line, ref const StructurePlan plan) {
        return CrownCorner(line.acrossSide == plan.doorSide, line.alongSide == plan.doorSide);
    }
}

struct LinesAtVertex {
    ColumnChunk[MAX_LINES_AT_VERTEX] chunks;
    uint[MAX_LINES_AT_VERTEX] lines;
    uint count;

    static LinesAtVertex make(ref const StructurePlan plan, const(MIsometry!float)[] linesFromNode, Vertex vertex, ref const ChunkLayout layout) {
        LinesAtVertex found;
        foreach (line; 0 .. plan.count) {
            ColumnChunk chunk = ColumnChunk.fromVertex(plan.lines[line], linesFromNode[line], vertex, layout);
            if (chunk.isPresent) {
                assert(found.count < MAX_LINES_AT_VERTEX);
                found.chunks[found.count] = chunk;
                found.lines[found.count] = line;
                found.count += 1;
            }
        }
        return found;
    }

    Stamp stampAt(ref const StructurePlan plan, int[3] cell, ubyte dimension) const {
        Stamp stamp = Stamp.none;
        uint index = 0;
        while (index < count && stamp == Stamp.none) {
            stamp = lineStamp(plan, lines[index], chunks[index].columnOf(cell), dimension);
            index += 1;
        }
        return stamp;
    }
}

struct Building {
    Array!Stamp stamps;
    NodeCells cells;
    TowerPalette palette;

    static Building make(NodeStructure structure, ChunkLayout layout) {
        Building building = Building(Array!Stamp.init, NodeCells(layout.dimension), TOWER_PALETTES[structure.palette]);
        if (structure.isPresent()) {
            StructurePlan plan = StructurePlan.fromKind(structure.kind, layout);
            building.stamp(structure, plan, layout);
        }
        return building;
    }

    void stamp(ref const NodeStructure structure, ref const StructurePlan plan, ref const ChunkLayout layout) {
        stamps.resize(cells.cellCount());
        MIsometry!float[MAX_STRUCTURE_LINES] linesFromNode;
        foreach (line; 0 .. plan.count) {
            linesFromNode[line] = structure.lineToNode(plan, line).inverse();
        }
        foreach (index; 0 .. VERTEX_COUNT) {
            Vertex vertex = cast(Vertex) index;
            LinesAtVertex found = LinesAtVertex.make(plan, linesFromNode[0 .. plan.count], vertex, layout);
            if (found.count > 0) {
                foreach (x; 0 .. cells.dimension) {
                    foreach (y; 0 .. cells.dimension) {
                        foreach (z; 0 .. cells.dimension) {
                            int[3] cell = [x, y, z];
                            stamps.ptr[cells.cellIndex(vertex, cell)] = found.stampAt(plan, cell, layout.dimension);
                        }
                    }
                }
            }
        }
    }

    void release() {
        stamps.release();
    }

    Material materialAt(Vertex vertex, int[3] cell, Material existing) const {
        Stamp stamp = Stamp.none;
        if (stamps.length > 0) {
            stamp = stamps.ptr[cells.cellIndex(vertex, cell)];
        }
        if (stamp == Stamp.empty) {
            return Material.none;
        } else if (stamp == Stamp.wall) {
            return palette.wall;
        } else if (stamp == Stamp.floor) {
            return palette.floor;
        } else if (stamp == Stamp.trim) {
            return palette.trim;
        } else {
            return existing;
        }
    }
}

Stamp lineStamp(ref const StructurePlan plan, uint line, int[3] column, ubyte dimension) {
    if (plan.lines[line].role == LineRole.bridge) {
        return bridgeStamp(column[0], column[1], column[2], dimension);
    } else if (plan.kind == StructureKind.crown) {
        return crownStamp(column[0], column[1], column[2], plan.top, CrownCorner.fromLine(plan.lines[line], plan), dimension);
    } else {
        return boxStamp(column[0], column[1], column[2], plan.top);
    }
}

Stamp boxStamp(int across, int along, int height, int top) {
    if (!isInBox(across, along) || height < -FOUNDATION_CELLS || height > top + 1) {
        return Stamp.none;
    } else if (height < 0) {
        return Stamp.wall;
    } else if (isRing(across, along)) {
        return towerWallStamp(across, along, height, top, isDoor(across, along, height));
    } else {
        return interiorStamp(across, along, height, top);
    }
}

Stamp crownStamp(int across, int along, int height, int top, CrownCorner corner, ubyte dimension) {
    bool isInsideHall = across >= 0 && along >= 0;
    if (height < -FOUNDATION_CELLS || height > top + 1) {
        return Stamp.none;
    } else if (!isInBox(across, along) && !(isInsideHall && height <= HALL_ROOF + PARAPET_CELLS)) {
        return balconyStamp(across, along, height, top);
    } else if (height < 0) {
        return Stamp.wall;
    } else if (!isInBox(across, along)) {
        return hallStamp(across, along, height, corner, dimension);
    } else if (isRing(across, along) && !(isInsideHall && height <= HALL_ROOF)) {
        return towerWallStamp(across, along, height, top, isCrownOpening(across, along, height, dimension));
    } else {
        return interiorStamp(across, along, height, top);
    }
}

bool isInBox(int across, int along) {
    return across >= -BOX_HALF_CELLS && across < BOX_HALF_CELLS && along >= -BOX_HALF_CELLS && along < BOX_HALF_CELLS;
}

bool isRing(int across, int along) {
    return isEdge(across) || isEdge(along);
}

bool isEdge(int coordinate) {
    return coordinate == -BOX_HALF_CELLS || coordinate == BOX_HALF_CELLS - 1;
}

Stamp towerWallStamp(int across, int along, int height, int top, bool isOpening) {
    if (height > top) {
        return merlonStamp(across, along);
    } else if ((isEdge(across) && isEdge(along)) || height % STORY_CELLS == 0) {
        return Stamp.trim;
    } else if (isOpening) {
        return Stamp.empty;
    } else if (height % STORY_CELLS == STORY_CELLS / 2 && isWindowPosition(facePosition(across, along))) {
        return Stamp.empty;
    } else {
        return Stamp.wall;
    }
}

int facePosition(int across, int along) {
    if (isEdge(across)) {
        return along;
    } else {
        return across;
    }
}

bool isWindowPosition(int position) {
    int fromStart = position + BOX_HALF_CELLS - 1;
    int fromEnd = 2 * BOX_HALF_CELLS - 3 - fromStart;
    return isInWindow(fromStart) || isInWindow(fromEnd);
}

bool isInWindow(int offset) {
    return offset >= WINDOW_INSET && offset < WINDOW_INSET + WINDOW_WIDTH;
}

Stamp merlonStamp(int across, int along) {
    if (((across + along) & 1) == 0) {
        return Stamp.trim;
    } else {
        return Stamp.empty;
    }
}

Stamp interiorStamp(int across, int along, int height, int top) {
    int story = height / STORY_CELLS;
    int layer = height % STORY_CELLS;
    if (height > top) {
        return Stamp.empty;
    } else if (layer == 0 && story > 0 && isStairwell(story - 1, across, along)) {
        return Stamp.empty;
    } else if (layer == 0) {
        return Stamp.floor;
    } else if (isStairRun(story, across, along) && layer <= across - STAIR_START + 1) {
        return Stamp.floor;
    } else {
        return Stamp.empty;
    }
}

Stamp hallStamp(int across, int along, int height, CrownCorner corner, ubyte dimension) {
    bool isOuter = across == 0 || along == 0;
    int position = across;
    bool isDoorFace = corner.isDoorOnAlongPlane;
    if (across == 0) {
        position = along;
        isDoorFace = corner.isDoorOnAcrossPlane;
    }
    if (height > HALL_ROOF) {
        return outerOr(isOuter, Stamp.trim, Stamp.none);
    } else if (height == HALL_ROOF) {
        return outerOr(isOuter, Stamp.trim, Stamp.floor);
    } else if (!isOuter && height % STORY_CELLS == 0) {
        return Stamp.floor;
    } else if (!isOuter) {
        return Stamp.empty;
    } else if (height % STORY_CELLS == 0) {
        return Stamp.trim;
    } else if (isDoorFace && position == dimension - 1 && height < STORY_CELLS) {
        return Stamp.empty;
    } else if (height % STORY_CELLS == STORY_CELLS / 2 && isHallWindowPosition(position)) {
        return Stamp.empty;
    } else {
        return Stamp.wall;
    }
}

Stamp outerOr(bool isOuter, Stamp outer, Stamp inner) {
    if (isOuter) {
        return outer;
    } else {
        return inner;
    }
}

bool isHallWindowPosition(int position) {
    int offset = position - BOX_HALF_CELLS - HALL_WINDOW_OFFSET;
    return offset >= 0 && offset < WINDOW_WIDTH;
}

bool isCrownOpening(int across, int along, int height, ubyte dimension) {
    int story = height / STORY_CELLS;
    return isTerraceDoor(across, along, story) || isBridgeDoor(across, along, story, dimension) || isBalconyDoor(across, along, story);
}

bool isTerraceDoor(int across, int along, int story) {
    bool isOnAcrossFace = across == BOX_HALF_CELLS - 1 && (along == 1 || along == 2);
    bool isOnAlongFace = along == BOX_HALF_CELLS - 1 && (across == 1 || across == 2);
    return story == HALL_ROOF / STORY_CELLS && (isOnAcrossFace || isOnAlongFace);
}

bool isBridgeDoor(int across, int along, int story, ubyte dimension) {
    bool isOnAcrossFace = across == BOX_HALF_CELLS - 1 && (along == -1 || along == 0);
    bool isOnAlongFace = along == BOX_HALF_CELLS - 1 && (across == -1 || across == 0);
    return story == edgeCells(dimension) / STORY_CELLS && (isOnAcrossFace || isOnAlongFace);
}

bool isBalconyDoor(int across, int along, int story) {
    BalconySpan span = BalconySpan.fromStory(story);
    if (story < FIRST_BALCONY_STORY) {
        return false;
    } else if (span.isOnAcrossFace) {
        return across == -BOX_HALF_CELLS && along > span.low && along < span.high;
    } else {
        return along == -BOX_HALF_CELLS && across > span.low && across < span.high;
    }
}

struct BalconySpan {
    int low;
    int high;
    bool isOnAcrossFace;

    static BalconySpan fromStory(int story) {
        if (story % 2 == 1) {
            return BalconySpan(-2, -2 + BALCONY_WIDTH - 1, true);
        } else {
            return BalconySpan(-1, -1 + BALCONY_WIDTH - 1, false);
        }
    }
}

Stamp balconyStamp(int across, int along, int height, int top) {
    if (height < FIRST_BALCONY_STORY * STORY_CELLS || height / STORY_CELLS * STORY_CELLS >= top) {
        return Stamp.none;
    } else {
        int layer = height % STORY_CELLS;
        BalconySpan span = BalconySpan.fromStory(height / STORY_CELLS);
        int away = -BOX_HALF_CELLS - 1 - along;
        int side = across;
        if (span.isOnAcrossFace) {
            away = -BOX_HALF_CELLS - 1 - across;
            side = along;
        }
        bool isEdgeOfBalcony = away == BALCONY_DEPTH - 1 || side == span.low || side == span.high;
        if (away < 0 || away >= BALCONY_DEPTH || side < span.low || side > span.high) {
            return Stamp.none;
        } else if (layer == 0) {
            return Stamp.floor;
        } else if (layer <= RAIL_CELLS && isEdgeOfBalcony) {
            return Stamp.trim;
        } else {
            return Stamp.none;
        }
    }
}

Stamp bridgeStamp(int across, int along, int height, ubyte dimension) {
    int apex = edgeCells(dimension);
    if (height < BOX_HALF_CELLS || height > apex + RAIL_CELLS) {
        return Stamp.none;
    } else if (along == 0 && (across == -1 || across == 0) && height <= apex) {
        return Stamp.floor;
    } else if (along >= 1 && along <= RAIL_CELLS && (across == -2 || across == 1)) {
        return Stamp.trim;
    } else {
        return Stamp.none;
    }
}

unittest {
    foreach (kind; TEST_KINDS) {
        Graph graph = Graph.make(TEST_DIMENSION, Worldgen.fromStructure(StructureWorld(NodeId.init, kind)));
        StructurePlan plan = StructurePlan.fromKind(kind, graph.layout);
        NearbyScratch scratch;
        NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.worldgen.structure.base, MIsometry!float.identity()), TEST_RADIUS);
        uint columnChunks = 0;
        foreach (node; nearby) {
            NodeStructure structure = graph.ensureStructureAt(node.slot);
            foreach (line; 0 .. plan.count) {
                MIsometry!float lineToNode = structure.lineToNode(plan, line);
                foreach (index; 0 .. VERTEX_COUNT) {
                    Vertex vertex = cast(Vertex) index;
                    ColumnChunk chunk = ColumnChunk.fromVertex(plan.lines[line], lineToNode.inverse(), vertex, graph.layout);
                    if (chunk.isPresent) {
                        assert(structure.isPresent());
                        columnChunks += 1;
                        foreach (cell; TEST_CELLS) {
                            int[3] column = chunk.columnOf(cell);
                            float[3] chunkCenter = graph.layout.cellCenter(cell);
                            MPoint!float actual = (vertex.chunkToNode * MVector!float([chunkCenter[0], chunkCenter[1], chunkCenter[2], 1.0f])).normalizedPoint();
                            MPoint!float expected = (lineToNode * columnPoint(graph.layout, ColumnSpot(column[0] + 0.5f, column[1] + 0.5f, column[2] + 0.5f, true))).vec.normalizedPoint();
                            assert(-actual.mip(expected.vec) < coshf(TEST_TOLERANCE.value));
                        }
                    }
                }
            }
        }
        assert(columnChunks >= 8 * plan.count);
        scratch.release();
        graph.release();
    }
}

unittest {
    ChunkLayout layout = ChunkLayout.make(TEST_DIMENSION);
    StructurePlan plan = StructurePlan.fromKind(StructureKind.crown, layout);
    ColumnSpot apexCell = ColumnSpot(-0.5f, 0.5f, edgeCells(TEST_DIMENSION) + 0.5f, true);
    StructureLine first = plan.lines[plan.bridgeOf(0, ALONG_BRIDGE)];
    StructureLine last = plan.lines[plan.bridgeOf(plan.archTower, plan.isArchAlongAtEnd)];
    MPoint!float fromFirst = first.placement * columnPoint(layout, apexCell);
    MPoint!float fromLast = last.placement * columnPoint(layout, apexCell);
    assert(-fromFirst.mip(fromLast.vec) < coshf(TEST_TOLERANCE.value));
    assert(plan.towerCount == 5 && plan.count == 15);
}
