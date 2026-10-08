module common.worldgen.building;

import common.array : Array;
import common.dodeca : VERTEX_COUNT, Vertex;
import common.material : Material;
import common.worldgen.blueprint : Blueprint, CellBox, Paint, higherOf, lowerOf;
import common.worldgen.structure : ColumnChunk, NodeStructure, isOnTouch;

enum uint MAX_LINES_AT_VERTEX = 3;

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

struct ChunkLines {
    ColumnChunk[MAX_LINES_AT_VERTEX] columns;
    CellBox[MAX_LINES_AT_VERTEX] bounds;
    uint count;

    static ChunkLines make(ref const NodeStructure structure, ref const Blueprint blueprint, Vertex vertex) {
        ChunkLines found;
        foreach (touch; structure.touches[0 .. structure.count]) {
            if (isOnTouch(touch, blueprint.lines.ptr[touch.line], vertex)) {
                assert(found.count < MAX_LINES_AT_VERTEX);
                ColumnChunk column = ColumnChunk.fromTouch(touch, blueprint.lines.ptr[touch.line], vertex, blueprint.dimension);
                found.columns[found.count] = column;
                found.bounds[found.count] = boundsOf(column, blueprint.dimension);
                found.count += 1;
            }
        }
        return found;
    }
}

struct BrushUse {
    uint brush;
    uint chunk;
}

struct Building {
    Array!Paint paints;
    const(Material)* materials;
    NodeCells cells;

    static Building make(ref const NodeStructure structure, ref const Blueprint blueprint) {
        Building building = Building(Array!Paint.init, blueprint.materials.ptr, NodeCells(blueprint.dimension));
        if (structure.isPresent) {
            building.stamp(structure, blueprint);
        }
        return building;
    }

    void stamp(ref const NodeStructure structure, ref const Blueprint blueprint) {
        paints.resize(cells.cellCount());
        Array!BrushUse uses;
        foreach (index; 0 .. VERTEX_COUNT) {
            Vertex vertex = cast(Vertex) index;
            ChunkLines found = ChunkLines.make(structure, blueprint, vertex);
            uses.clear();
            foreach (brush, painting; blueprint.brushes.slice()) {
                foreach (chunk; 0 .. found.count) {
                    if (found.columns[chunk].line == painting.line && painting.box.overlaps(found.bounds[chunk])) {
                        uses.append(BrushUse(cast(uint) brush, chunk));
                    }
                }
            }
            if (uses.length > 0) {
                stampChunk(vertex, found, uses.slice(), blueprint);
            }
        }
        uses.release();
    }

    void stampChunk(Vertex vertex, ref const ChunkLines found, const(BrushUse)[] uses, ref const Blueprint blueprint) {
        int[3][MAX_LINES_AT_VERTEX] columns = void;
        foreach (x; 0 .. cells.dimension) {
            foreach (y; 0 .. cells.dimension) {
                foreach (z; 0 .. cells.dimension) {
                    int[3] cell = [x, y, z];
                    foreach (chunk; 0 .. found.count) {
                        columns[chunk] = found.columns[chunk].columnOf(cell);
                    }
                    Paint paint = Paint.init;
                    foreach (use; uses) {
                        if (blueprint.brushes.ptr[use.brush].covers(columns[use.chunk])) {
                            paint = blueprint.brushes.ptr[use.brush].paint;
                        }
                    }
                    paints.ptr[cells.cellIndex(vertex, cell)] = paint;
                }
            }
        }
    }

    void release() {
        paints.release();
    }

    Material materialAt(Vertex vertex, int[3] cell, Material existing) const {
        Paint paint = Paint.init;
        if (paints.length > 0) {
            paint = paints.ptr[cells.cellIndex(vertex, cell)];
        }
        if (paint.material == 0 || (paint.isIntoAirOnly && existing != Material.none)) {
            return existing;
        } else {
            return materials[paint.material - 1];
        }
    }
}

CellBox boundsOf(ref const ColumnChunk column, ubyte dimension) {
    int[3] first = column.columnOf([0, 0, 0]);
    int[3] last = column.columnOf([dimension - 1, dimension - 1, dimension - 1]);
    CellBox bounds = void;
    foreach (axis; 0 .. 3) {
        bounds.low[axis] = lowerOf(first[axis], last[axis]);
        bounds.high[axis] = higherOf(first[axis], last[axis]);
    }
    return bounds;
}
