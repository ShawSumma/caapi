module common.worldgen.building;

import core.stdc.stdlib : calloc, free, malloc;
import common.array : Array;
import common.dodeca : VERTEX_COUNT, Vertex;
import common.graph : Graph;
import common.material : Material;
import common.worldgen.blueprint : Brush, CellBox, LineSpec, Paint, higherOf, lowerOf;
import common.worldgen.structure : ColumnChunk, LineTouch, isOnTouch, isTouchInRange;

enum uint MAX_LINES_AT_VERTEX = 3;

struct NodeCells {
    ubyte dimension;

    int cellsPerChunk() const {
        return dimension * dimension * dimension;
    }

    int cellIndex(int[3] cell) const {
        return (cell[0] * dimension + cell[1]) * dimension + cell[2];
    }
}

struct PlanLine {
    LineSpec spec;
    LineTouch touch;
    uint first;
    uint count;
}

struct BuildingPlan {
    Array!PlanLine lines;
    Array!Brush brushes;
    Array!Material materials;
    ubyte dimension;

    static BuildingPlan make(ref const Graph graph, uint slot) {
        BuildingPlan plan = BuildingPlan(Array!PlanLine.init, Array!Brush.init, Array!Material.init, graph.layout.dimension);
        foreach (touch; graph.touchesAt(slot)) {
            LineSpec spec = graph.blueprint.lines.ptr[touch.line];
            if (isTouchInRange(touch, spec)) {
                const(Brush)[] painted = graph.blueprint.brushes.ptr[touch.line].slice();
                plan.lines.append(PlanLine(spec, touch, cast(uint) plan.brushes.length, cast(uint) painted.length));
                plan.brushes.appendAll(painted);
            }
        }
        plan.materials.appendAll(graph.blueprint.materials.slice());
        return plan;
    }

    void release() {
        lines.release();
        brushes.release();
        materials.release();
    }
}

struct ChunkLines {
    ColumnChunk[MAX_LINES_AT_VERTEX] columns;
    CellBox[MAX_LINES_AT_VERTEX] bounds;
    uint[MAX_LINES_AT_VERTEX] lines;
    uint count;

    static ChunkLines make(ref const BuildingPlan plan, Vertex vertex) {
        ChunkLines found;
        foreach (index, line; plan.lines.slice()) {
            if (isOnTouch(line.touch, line.spec, vertex)) {
                assert(found.count < MAX_LINES_AT_VERTEX);
                ColumnChunk column = ColumnChunk.fromTouch(line.touch, line.spec, vertex, plan.dimension);
                found.columns[found.count] = column;
                found.bounds[found.count] = boundsOf(column, plan.dimension);
                found.lines[found.count] = cast(uint) index;
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
    Paint** chunkPaints;
    Array!Material materials;
    NodeCells cells;

    static Building make(ref const BuildingPlan plan) {
        Building building;
        building.cells = NodeCells(plan.dimension);
        building.materials.appendAll(plan.materials.slice());
        building.stamp(plan);
        return building;
    }

    void stamp(ref const BuildingPlan plan) {
        Array!BrushUse uses;
        foreach (index; 0 .. VERTEX_COUNT) {
            Vertex vertex = cast(Vertex) index;
            ChunkLines found = ChunkLines.make(plan, vertex);
            uses.clear();
            foreach (chunk; 0 .. found.count) {
                PlanLine line = plan.lines.ptr[found.lines[chunk]];
                foreach (brush; line.first .. line.first + line.count) {
                    if (plan.brushes.ptr[brush].box.overlaps(found.bounds[chunk])) {
                        uses.append(BrushUse(brush, chunk));
                    }
                }
            }
            if (uses.length > 0) {
                sortByOrder(uses.slice(), plan.brushes.slice());
                stampChunk(vertex, found, uses.slice(), plan.brushes.slice());
            }
        }
        uses.release();
    }

    void stampChunk(Vertex vertex, ref const ChunkLines found, const(BrushUse)[] uses, const(Brush)[] brushes) {
        if (chunkPaints is null) {
            chunkPaints = cast(Paint**) calloc(VERTEX_COUNT, (Paint*).sizeof);
        }
        Paint* paints = cast(Paint*) malloc(cells.cellsPerChunk() * Paint.sizeof);
        chunkPaints[vertex] = paints;
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
                        if (brushes[use.brush].covers(columns[use.chunk])) {
                            paint = brushes[use.brush].paint;
                        }
                    }
                    paints[cells.cellIndex(cell)] = paint;
                }
            }
        }
    }

    size_t paintBytes() const {
        size_t bytes = 0;
        if (chunkPaints !is null) {
            foreach (paints; chunkPaints[0 .. VERTEX_COUNT]) {
                if (paints !is null) {
                    bytes += cells.cellsPerChunk() * Paint.sizeof;
                }
            }
        }
        return bytes;
    }

    void release() {
        if (chunkPaints !is null) {
            foreach (paints; chunkPaints[0 .. VERTEX_COUNT]) {
                free(paints);
            }
            free(chunkPaints);
            chunkPaints = null;
        }
        materials.release();
    }

    Material materialAt(Vertex vertex, int[3] cell, Material existing) const {
        Paint paint = Paint.init;
        if (chunkPaints !is null && chunkPaints[vertex] !is null) {
            paint = chunkPaints[vertex][cells.cellIndex(cell)];
        }
        if (paint.material == 0 || (paint.isIntoAirOnly && existing != Material.none)) {
            return existing;
        } else {
            return materials.ptr[paint.material - 1];
        }
    }
}

void sortByOrder(BrushUse[] uses, const(Brush)[] brushes) {
    foreach (index; 1 .. uses.length) {
        BrushUse held = uses[index];
        size_t slot = index;
        while (slot > 0 && brushes[uses[slot - 1].brush].order > brushes[held.brush].order) {
            uses[slot] = uses[slot - 1];
            slot -= 1;
        }
        uses[slot] = held;
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
