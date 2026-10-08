module common.worldgen.blueprint;

import common.array : Array;
import common.dodeca : SIDE_COUNT, Side, VERTEX_COUNT, Vertex;
import common.graph : Graph;
import common.hashmap : HashMap;
import common.material : Material;
import common.worldgen.structure : CanonicalSite, ClaimKey, ColumnSpot, LineTransform, PAINT_REACH, SiteFrame, SlotTouch, addPendingTouch, aroundEdge, canonicalOf, edgeCells, isEndless, seedTouch, walkedTouch;

enum size_t MAX_MATERIALS = ubyte.max;
enum ulong LINE_HASH_MULTIPLIER = 0x9E3779B97F4A7C15;

struct Paint {
    ubyte material;
    bool isIntoAirOnly;
}

struct CellBox {
    int[3] low;
    int[3] high;

    static CellBox make(int xLow, int xHigh, int yLow, int yHigh, int zLow, int zHigh) {
        return CellBox([xLow, yLow, zLow], [xHigh, yHigh, zHigh]);
    }

    bool contains(int[3] cell) const {
        return cell[0] >= low[0] && cell[0] <= high[0] && cell[1] >= low[1] && cell[1] <= high[1] && cell[2] >= low[2] && cell[2] <= high[2];
    }

    bool overlaps(ref const CellBox other) const {
        return low[0] <= other.high[0] && other.low[0] <= high[0] && low[1] <= other.high[1] && other.low[1] <= high[1] && low[2] <= other.high[2] && other.low[2] <= high[2];
    }
}

struct Rhythm {
    int period;
    int phase;
    int span;

    bool includes(int height) const {
        if (period == 0) {
            return true;
        } else {
            int offset = (height - phase) % period;
            if (offset < 0) {
                offset += period;
            }
            return offset < span;
        }
    }
}

enum Rhythm EVERY_HEIGHT = Rhythm(0, 0, 0);

struct Brush {
    CellBox box;
    Rhythm rhythm;
    uint order;
    Paint paint;

    bool covers(int[3] column) const {
        return box.contains(column) && rhythm.includes(column[2]);
    }
}

struct LineSpec {
    int lowest;
    int highest;
    uint node;
    Vertex lower;
    Side xSide;
    Side ySide;
}

struct LineKey {
    uint node;
    Vertex lower;
    Side xSide;
    Side ySide;

    static LineKey fromSpec(ref const LineSpec spec) {
        return LineKey(spec.node, spec.lower, spec.xSide, spec.ySide);
    }

    size_t toHash() const {
        return ((cast(size_t) node * VERTEX_COUNT + lower) * SIDE_COUNT + xSide) * SIDE_COUNT + ySide;
    }
}

struct LineEdge {
    uint line;
    int level;

    size_t toHash() const {
        return cast(size_t)(line * LINE_HASH_MULTIPLIER) ^ cast(uint) level;
    }
}

struct RouteStop {
    SiteFrame site;
    ColumnSpot spot;
}

struct SiteLine {
    SiteFrame site;
    LineTransform transform;
    uint line;
}

enum PaintResult : ubyte {
    painted,
    endless,
    behind,
}

struct Blueprint {
    Array!LineSpec lines;
    Array!(Array!Brush) brushes;
    Array!RouteStop route;
    Array!Material materials;
    HashMap!(LineKey, uint) lineIndex;
    HashMap!(LineEdge, bool) touchedEdges;
    HashMap!(ClaimKey, bool) claims;
    RouteStop entrance;
    uint brushCount;
    uint claimCount;
    ubyte dimension;
    bool hasEntrance;

    static Blueprint make(ubyte chunkDimension) {
        return Blueprint(Array!LineSpec.init, Array!(Array!Brush).init, Array!RouteStop.init, Array!Material.init, HashMap!(LineKey, uint).init, HashMap!(LineEdge, bool).init, HashMap!(ClaimKey, bool).init, RouteStop.init, 0, 0, chunkDimension, false);
    }

    uint lineOf(LineSpec spec) {
        LineKey key = LineKey.fromSpec(spec);
        const(uint)* found = lineIndex.find(key);
        if (found is null) {
            uint index = cast(uint) lines.length;
            lines.append(spec);
            brushes.append(Array!Brush.init);
            lineIndex.insert(key, index);
            return index;
        } else {
            return *found;
        }
    }

    ubyte paintOf(Material material) {
        uint index = 0;
        while (index < materials.length && materials.ptr[index] != material) {
            index += 1;
        }
        if (index == materials.length) {
            assert(materials.length < MAX_MATERIALS);
            materials.append(material);
        }
        return cast(ubyte)(index + 1);
    }

    bool isClaimed(ClaimKey key) const {
        return claims.find(key) !is null;
    }

    bool claim(ClaimKey key) {
        if (isClaimed(key)) {
            return false;
        } else {
            claims.insert(key, true);
            claimCount += 1;
            return true;
        }
    }

    void release() {
        foreach (ref painted; brushes.slice()) {
            painted.release();
        }
        lines.release();
        brushes.release();
        route.release();
        materials.release();
        lineIndex.release();
        touchedEdges.release();
        claims.release();
    }
}

struct BlueprintBuilder {
    Array!SiteLine known;
    Graph* graph;
    int paintLimit;
    bool isGrowing;
    bool isTiling;

    static BlueprintBuilder make(ref Graph target) {
        return BlueprintBuilder(Array!SiteLine.init, &target, 0, false, false);
    }

    void growFrom(uint key) {
        known.clear();
        paintLimit = cast(int) key - PAINT_REACH;
        isGrowing = true;
        isTiling = false;
    }

    void tile() {
        known.clear();
        isGrowing = true;
        isTiling = true;
    }

    bool isOpen(uint slot) const {
        if (isTiling) {
            return !graph.nodeAt(slot).hasStructure;
        } else {
            return cast(int) graph.nodeAt(slot).depth >= paintLimit;
        }
    }

    SiteLine lineOf(SiteFrame site) {
        uint index = 0;
        while (index < known.length && known.ptr[index].site != site) {
            index += 1;
        }
        if (index == known.length) {
            CanonicalSite canonical = (*graph).canonicalOf(site);
            known.append(SiteLine(site, canonical.transform, graph.blueprint.lineOf(canonical.line)));
        }
        return known.ptr[index];
    }

    PaintResult paint(SiteFrame site, CellBox box, Rhythm rhythm, Material material, bool isIntoAirOnly) {
        SiteLine found = lineOf(site);
        ubyte dimension = graph.layout.dimension;
        CellBox canonical = canonicalBox(box, found.transform, dimension);
        int lowEdge = edgeOf(canonical.low[2], dimension);
        int highEdge = edgeOf(canonical.high[2], dimension);
        bool isUnbounded = lowEdge == int.min || highEdge == int.max;
        if (isGrowing && isUnbounded) {
            return PaintResult.endless;
        } else if (isGrowing && !isAhead(found.line, lowEdge, highEdge)) {
            return PaintResult.behind;
        } else {
            record(found.line, lowEdge, highEdge, isUnbounded);
            Brush brush = Brush(canonical, canonicalRhythm(rhythm, found.transform, dimension), graph.blueprint.brushCount, Paint(graph.blueprint.paintOf(material), isIntoAirOnly));
            graph.blueprint.brushes.ptr[found.line].append(brush);
            graph.blueprint.brushCount += 1;
            return PaintResult.painted;
        }
    }

    bool isAhead(uint line, int lowEdge, int highEdge) {
        LineSpec spec = graph.blueprint.lines.ptr[line];
        SlotTouch edge = seedTouch(spec, line);
        bool isClear = true;
        int level = lowEdge;
        while (isClear && level <= highEdge) {
            edge = (*graph).walkedTouch(edge, spec, level);
            foreach (around; (*graph).aroundEdge(edge, spec)) {
                isClear = isClear && isOpen(around.slot);
            }
            level += 1;
        }
        return isClear;
    }

    void record(uint line, int lowEdge, int highEdge, bool isUnbounded) {
        LineSpec spec = graph.blueprint.lines.ptr[line];
        if (isUnbounded && !spec.isEndless()) {
            SlotTouch seed = seedTouch(spec, line);
            (*graph).addPendingTouch(seed.slot, seed.touch);
        } else if (!isUnbounded && !spec.isEndless()) {
            touchEdges(line, spec, lowEdge, highEdge);
        }
        LineSpec* stored = &graph.blueprint.lines.ptr[line];
        stored.lowest = lowerOf(spec.lowest, lowEdge);
        stored.highest = higherOf(spec.highest, highEdge);
    }

    void touchEdges(uint line, ref const LineSpec spec, int lowEdge, int highEdge) {
        SlotTouch edge = seedTouch(spec, line);
        foreach (level; lowEdge .. highEdge + 1) {
            LineEdge key = LineEdge(line, level);
            if (graph.blueprint.touchedEdges.find(key) is null) {
                graph.blueprint.touchedEdges.insert(key, true);
                edge = (*graph).walkedTouch(edge, spec, level);
                foreach (around; (*graph).aroundEdge(edge, spec)) {
                    (*graph).addPendingTouch(around.slot, around.touch);
                }
            }
        }
    }

    void stop(SiteFrame site, ColumnSpot spot) {
        graph.blueprint.route.append(RouteStop(site, spot));
    }

    void enter(SiteFrame site, ColumnSpot spot) {
        if (!graph.blueprint.hasEntrance) {
            graph.blueprint.entrance = RouteStop(site, spot);
            graph.blueprint.hasEntrance = true;
        }
    }

    void release() {
        known.release();
    }
}

CellBox canonicalBox(CellBox local, LineTransform transform, ubyte dimension) {
    int[2] x = signedRange(local.low[0], local.high[0], transform.xSign);
    int[2] y = signedRange(local.low[1], local.high[1], transform.ySign);
    int[2] z = heightRange(local.low[2], local.high[2], transform, dimension);
    if (transform.isSwapped) {
        return CellBox.make(y[0], y[1], x[0], x[1], z[0], z[1]);
    } else {
        return CellBox.make(x[0], x[1], y[0], y[1], z[0], z[1]);
    }
}

int[2] signedRange(int low, int high, int sign) {
    if (sign > 0) {
        return [low, high];
    } else {
        return [-1 - high, -1 - low];
    }
}

int[2] heightRange(int low, int high, LineTransform transform, ubyte dimension) {
    int offset = transform.offsetLevels * edgeCells(dimension);
    if (transform.zSign > 0) {
        return [movedHeight(low, offset), movedHeight(high, offset)];
    } else {
        return [mirroredHeight(high, offset), mirroredHeight(low, offset)];
    }
}

int movedHeight(int height, int offset) {
    if (height == int.min || height == int.max) {
        return height;
    } else {
        return height + offset;
    }
}

int mirroredHeight(int height, int offset) {
    if (height == int.min) {
        return int.max;
    } else if (height == int.max) {
        return int.min;
    } else {
        return offset - 1 - height;
    }
}

Rhythm canonicalRhythm(Rhythm local, LineTransform transform, ubyte dimension) {
    int offset = transform.offsetLevels * edgeCells(dimension);
    if (local.period == 0) {
        return local;
    } else if (transform.zSign > 0) {
        return Rhythm(local.period, local.phase + offset, local.span);
    } else {
        return Rhythm(local.period, offset - local.phase - local.span, local.span);
    }
}

int edgeOf(int height, ubyte dimension) {
    if (height == int.min || height == int.max) {
        return height;
    } else {
        return floorDivision(height, edgeCells(dimension));
    }
}

int floorDivision(int value, int divisor) {
    int quotient = value / divisor;
    if (value % divisor != 0 && value < 0) {
        quotient -= 1;
    }
    return quotient;
}

int lowerOf(int a, int b) {
    if (a < b) {
        return a;
    } else {
        return b;
    }
}

int higherOf(int a, int b) {
    if (a > b) {
        return a;
    } else {
        return b;
    }
}

unittest {
    assert(edgeOf(-3, 12) == -1 && edgeOf(0, 12) == 0);
    assert(edgeOf(23, 12) == 0 && edgeOf(24, 12) == 1);
    assert(edgeOf(-24, 12) == -1 && edgeOf(-25, 12) == -2);
    assert(edgeOf(int.min, 12) == int.min && edgeOf(int.max, 12) == int.max);
    LineTransform mirrored = LineTransform(2, 1, 1, -1, false);
    Rhythm local = Rhythm(8, 1, 3);
    Rhythm moved = canonicalRhythm(local, mirrored, 12);
    foreach (height; -20 .. 20) {
        assert(local.includes(height) == moved.includes(2 * 24 - 1 - height));
    }
}
