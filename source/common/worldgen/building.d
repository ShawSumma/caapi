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
import common.worldgen.tower : BOX_HALF_CELLS, ColumnChunk, ColumnSpot, FOUNDATION_CELLS, NodeStructure, STAIR_START, STORY_CELLS, TOWER_PALETTES, TowerPalette, columnPoint, isDoor, isStairRun, isStairwell, towerTop;

enum ubyte TEST_DIMENSION = 12;
enum float TEST_RADIUS = 3.0f;
enum Length TEST_TOLERANCE = Length(0.01f);
immutable int[3][4] TEST_CELLS = [
    [0, 0, 0],
    [3, 1, 2],
    [11, 5, 0],
    [2, 11, 9],
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

struct Building {
    Array!Stamp stamps;
    NodeCells cells;
    TowerPalette palette;

    static Building make(NodeStructure structure, ChunkLayout layout) {
        Building building = Building(Array!Stamp.init, NodeCells(layout.dimension), TOWER_PALETTES[structure.palette]);
        if (structure.isPresent()) {
            building.stamp(structure.towerFromNode(), layout);
        }
        return building;
    }

    void stamp(MIsometry!float towerFromNode, ref const ChunkLayout layout) {
        stamps.resize(cells.cellCount());
        int top = towerTop(layout.dimension);
        foreach (index; 0 .. VERTEX_COUNT) {
            Vertex vertex = cast(Vertex) index;
            ColumnChunk chunk = ColumnChunk.fromVertex(towerFromNode, vertex, layout);
            if (chunk.isPresent) {
                foreach (x; 0 .. cells.dimension) {
                    foreach (y; 0 .. cells.dimension) {
                        foreach (z; 0 .. cells.dimension) {
                            int[3] cell = [x, y, z];
                            int[3] column = chunk.columnOf(cell);
                            stamps.ptr[cells.cellIndex(vertex, cell)] = columnStamp(column[0], column[1], column[2], top);
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

Stamp columnStamp(int across, int along, int height, int top) {
    bool isInBox = across >= -BOX_HALF_CELLS && across < BOX_HALF_CELLS && along >= -BOX_HALF_CELLS && along < BOX_HALF_CELLS;
    if (!isInBox || height < -FOUNDATION_CELLS || height > top + 1) {
        return Stamp.none;
    } else if (height < 0) {
        return Stamp.wall;
    } else if (isEdge(across) || isEdge(along)) {
        return wallStamp(across, along, height, top);
    } else {
        return interiorStamp(across, along, height, top);
    }
}

bool isEdge(int coordinate) {
    return coordinate == -BOX_HALF_CELLS || coordinate == BOX_HALF_CELLS - 1;
}

Stamp wallStamp(int across, int along, int height, int top) {
    if (height > top) {
        return merlonStamp(across, along);
    } else if ((isEdge(across) && isEdge(along)) || height % STORY_CELLS == 0) {
        return Stamp.trim;
    } else if (isDoor(across, along, height)) {
        return Stamp.empty;
    } else if (height % STORY_CELLS == STORY_CELLS / 2 && isWindowColumn(across, along)) {
        return Stamp.empty;
    } else {
        return Stamp.wall;
    }
}

Stamp merlonStamp(int across, int along) {
    if (((across + along) & 1) == 0) {
        return Stamp.trim;
    } else {
        return Stamp.empty;
    }
}

bool isWindowColumn(int across, int along) {
    int position = across;
    if (isEdge(across)) {
        position = along;
    }
    return (position & 1) == 0;
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

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.fromStructure(StructureWorld(NodeId.init, StructureKind.tower)));
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.worldgen.structure.base, MIsometry!float.identity()), TEST_RADIUS);
    uint columnChunks = 0;
    foreach (node; nearby) {
        NodeStructure structure = graph.ensureStructureAt(node.slot);
        foreach (index; 0 .. VERTEX_COUNT) {
            Vertex vertex = cast(Vertex) index;
            ColumnChunk chunk = ColumnChunk.fromVertex(structure.towerFromNode(), vertex, graph.layout);
            if (structure.isPresent() && chunk.isPresent) {
                columnChunks += 1;
                foreach (cell; TEST_CELLS) {
                    int[3] column = chunk.columnOf(cell);
                    float[3] chunkCenter = graph.layout.cellCenter(cell);
                    MPoint!float actual = (vertex.chunkToNode * MVector!float([chunkCenter[0], chunkCenter[1], chunkCenter[2], 1.0f])).normalizedPoint();
                    MPoint!float expected = (structure.frame * columnPoint(graph.layout, ColumnSpot(column[0] + 0.5f, column[1] + 0.5f, column[2] + 0.5f, true))).vec.normalizedPoint();
                    assert(-actual.mip(expected.vec) < coshf(TEST_TOLERANCE.value));
                }
            }
        }
    }
    assert(columnChunks >= 8);
    scratch.release();
    graph.release();
}
