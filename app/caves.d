module app.caves;

import base.array : Array;
import base.flags : Bits;
import base.maybe : Maybe;
import base.numbers : higherOf;
import base.vector3 : Vec3;
import common.graph : Graph;
import common.neighbors : CellHop, hopCell;
import common.node : Chunk, ChunkSlot, ChunkState, cellIndex;
import common.position : Position;
import common.worldgen.horospheres : ROOT, ensureUndersideAt, isBelowUnderside;
import common.worldgen.structure : edgeLength, edgeSitesOf;
import geometry.honeycomb : CORNER_COUNT, cornerToNode, cubeToNode;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : Material;

enum CaveBand UPPER_CAVES = CaveBand(0.5f, 1.9f);
enum CaveBand DEEP_CAVES = CaveBand(1.9f, 5.2f);
enum uint LEAST_CAVE_CELLS = 64;
enum string DRAIN_WOOD = "base:spruce-wood";

struct CaveCell {
    ChunkSlot chunk;
    Vec3!int cell;
}

struct CaveBand {
    float top;
    float bottom;
}

struct CaveCount {
    size_t spaces;
    size_t pockets;
    size_t cells;
    size_t largest;

    double largestShare() const {
        return cast(double) largest / higherOf(cells, cast(size_t) 1);
    }
}

size_t caveIndexOf(ref const Graph graph, CaveCell at) {
    ubyte dimension = graph.layout.dimension;
    return (cast(size_t) at.chunk.slot * CORNER_COUNT + at.chunk.corner) * dimension * dimension * dimension + cellIndex(dimension, at.cell.x, at.cell.y, at.cell.z);
}

bool isCaveAir(ref Graph graph, CaveCell at, CaveBand band) {
    const(Chunk)* chunk = graph.chunks.at(at.chunk);
    if (chunk.state != ChunkState.populated || !graph.nodeAt(at.chunk.slot).hasState) {
        return false;
    } else if (chunk.voxels.at(cellIndex(graph.layout.dimension, at.cell.x, at.cell.y, at.cell.z)) != Material.none) {
        return false;
    } else {
        Vec3!float cube = graph.layout.cellCenter(at.cell);
        Point!float inNode = (at.chunk.corner.cubeToNode * Vec4!float([cube.x, cube.y, cube.z, 1])).toPoint();
        float depth = -graph.stateAt(at.chunk.slot).surface.distanceTo(inNode);
        return depth > band.top && depth < band.bottom && !graph.isBelowUnderside(Position(graph.idAt(at.chunk.slot), Motion!float.shiftTo(inNode)));
    }
}

Maybe!CaveCell caveStep(ref Graph graph, CaveCell at, size_t axis, int step) {
    Vec3!int moved = at.cell;
    moved[axis] += step;
    if (moved[axis] >= 0 && moved[axis] < graph.layout.dimension) {
        return Maybe!CaveCell.of(CaveCell(at.chunk, moved));
    } else {
        CellHop hop = graph.hopCell(at.chunk, moved, axis);
        if (hop.isPopulated) {
            return Maybe!CaveCell.of(CaveCell(hop.chunk.value, hop.cell));
        } else {
            return Maybe!CaveCell.init;
        }
    }
}

size_t fillCave(ref Graph graph, CaveCell first, CaveBand band, ref Bits seen, ref Array!CaveCell queue) {
    queue.clear();
    queue.append(first);
    seen.set(caveIndexOf(graph, first));
    size_t next = 0;
    while (next < queue.length) {
        CaveCell at = queue.ptr[next];
        next += 1;
        foreach (axis; 0 .. 3) {
            foreach (step; [-1, 1]) {
                Maybe!CaveCell beside = caveStep(graph, at, axis, step);
                if (beside.exists && !seen.has(caveIndexOf(graph, beside.value)) && isCaveAir(graph, beside.value, band)) {
                    seen.set(caveIndexOf(graph, beside.value));
                    queue.append(beside.value);
                }
            }
        }
    }
    return queue.length;
}

enum uint DRAIN_DEPTH_BINS = 8;
enum float VERTICAL_SHARE = 0.02f;
enum float KEPT_MARGIN_EDGES = 0.5f;
enum float WOOD_DEPTH_EDGES = 1.5f;

struct DrainCount {
    size_t[DRAIN_DEPTH_BINS] vertical;
    size_t[DRAIN_DEPTH_BINS] straddling;
}

DrainCount countDrainEdges(ref Graph graph) {
    float edge = edgeLength(graph.layout).value;
    DrainCount count;
    foreach (slot; 0 .. graph.slotCount) {
        if (graph.nodeAt(slot).hasState) {
            foreach (site; graph.view.edgeSitesOf(slot)) {
                Point!float near = site.corner.cornerToNode * Point!float.origin();
                Point!float far = site.nextCorner().cornerToNode * Point!float.origin();
                float nearDepth = -graph.stateAt(slot).surface.distanceTo(near);
                float farDepth = -graph.stateAt(slot).surface.distanceTo(far);
                float rise = nearDepth - farDepth;
                if (rise < 0) {
                    rise = -rise;
                }
                if (rise > (1 - VERTICAL_SHARE) * edge && rise < (1 + VERTICAL_SHARE) * edge) {
                    Point!float upper = near;
                    float upperDepth = nearDepth;
                    float lowerDepth = farDepth;
                    if (farDepth < nearDepth) {
                        upper = far;
                        upperDepth = farDepth;
                        lowerDepth = nearDepth;
                    }
                    if (upperDepth > 0) {
                        uint bin = cast(uint)(upperDepth / edge);
                        if (bin >= DRAIN_DEPTH_BINS) {
                            bin = DRAIN_DEPTH_BINS - 1;
                        }
                        count.vertical[bin] += 1;
                        float underside = graph.view.ensureUndersideAt(ROOT, Position(graph.idAt(slot), Motion!float.shiftTo(upper)));
                        if (upperDepth <= underside - KEPT_MARGIN_EDGES * edge && lowerDepth > underside) {
                            count.straddling[bin] += 1;
                        }
                    }
                }
            }
        }
    }
    return count;
}

struct UndersideCount {
    size_t open;
    size_t wanted;
}

UndersideCount countBelowUnderside(ref Graph graph, Material wanted) {
    ubyte dimension = graph.layout.dimension;
    float edge = edgeLength(graph.layout).value;
    UndersideCount count;
    foreach (index; 0 .. cast(size_t) graph.slotCount * CORNER_COUNT) {
        ChunkSlot slot = ChunkSlot.fromIndex(index);
        if (graph.chunks.at(slot).state == ChunkState.populated && graph.nodeAt(slot.slot).hasState) {
            foreach (x; 0 .. dimension) {
                foreach (y; 0 .. dimension) {
                    foreach (z; 0 .. dimension) {
                        Material held = graph.chunks.at(slot).voxels.at(cellIndex(dimension, x, y, z));
                        if (held == Material.none || held == wanted) {
                            Vec3!float cube = graph.layout.cellCenter(Vec3!int(x, y, z));
                            Point!float inNode = (slot.corner.cubeToNode * Vec4!float([cube.x, cube.y, cube.z, 1])).toPoint();
                            float depth = -graph.stateAt(slot.slot).surface.distanceTo(inNode);
                            if (held == wanted && depth > WOOD_DEPTH_EDGES * edge) {
                                count.wanted += 1;
                            } else if (held == Material.none && graph.isBelowUnderside(Position(graph.idAt(slot.slot), Motion!float.shiftTo(inNode)))) {
                                count.open += 1;
                            }
                        }
                    }
                }
            }
        }
    }
    return count;
}

CaveCount countCaves(ref Graph graph, CaveBand edges) {
    ubyte dimension = graph.layout.dimension;
    float edge = edgeLength(graph.layout).value;
    CaveBand band = CaveBand(edges.top * edge, edges.bottom * edge);
    Bits seen;
    seen.cover(cast(size_t) graph.slotCount * CORNER_COUNT * dimension * dimension * dimension);
    Array!CaveCell queue;
    CaveCount count;
    foreach (index; 0 .. cast(size_t) graph.slotCount * CORNER_COUNT) {
        ChunkSlot slot = ChunkSlot.fromIndex(index);
        if (graph.chunks.at(slot).state == ChunkState.populated && !graph.chunks.at(slot).voxels.isUniform()) {
            foreach (x; 0 .. dimension) {
                foreach (y; 0 .. dimension) {
                    foreach (z; 0 .. dimension) {
                        CaveCell at = CaveCell(slot, Vec3!int(x, y, z));
                        if (!seen.has(caveIndexOf(graph, at)) && isCaveAir(graph, at, band)) {
                            size_t size = fillCave(graph, at, band, seen, queue);
                            if (size >= LEAST_CAVE_CELLS) {
                                count.spaces += 1;
                                count.cells += size;
                                count.largest = higherOf(count.largest, size);
                            } else {
                                count.pockets += 1;
                            }
                        }
                    }
                }
            }
        }
    }
    queue.release();
    seen.release();
    return count;
}
