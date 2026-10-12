module common.worldgen.blueprint;

import common.array : Array;
import common.dodeca : SIDE_COUNT, Side, VERTEX_COUNT, Vertex;
import common.graph : Graph, NodeId;
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
    NodeId node;
    Vertex lower;
    Side xSide;
    Side ySide;

    size_t toHash() const {
        return node.toHash() ^ ((cast(size_t) lower * SIDE_COUNT + xSide) * SIDE_COUNT + ySide);
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

// One tile call's brushes carry consecutive orders, so a tile can be dropped from its lines and painted again later:
// tiles decide everything from site hashes, and the touches they recorded stay.
struct TileRecord {
    Array!uint lines;
    NodeId face;
    double lastUse = 0;
    uint firstOrder;
    uint endOrder;
    bool isDropped;
}

struct SiteLine {
    SiteFrame site;
    LineTransform transform;
    uint line;
    LevelRange open;
    LevelRange touched;
}

struct LevelRange {
    int low = int.max;
    int high = int.min;

    bool contains(int first, int last) const {
        return first >= low && last <= high;
    }

    void include(int first, int last) {
        if (first <= high + 1L && last >= low - 1L) {
            low = lowerOf(low, first);
            high = higherOf(high, last);
        } else {
            low = first;
            high = last;
        }
    }
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
    Array!TileRecord tiles;
    HashMap!(LineKey, uint) lineIndex;
    HashMap!(LineEdge, bool) touchedEdges;
    HashMap!(ClaimKey, bool) claims;
    RouteStop entrance;
    double travel = 0;
    uint brushCount;
    uint claimCount;
    uint restoredTiles;
    ubyte dimension;
    bool hasEntrance;

    static Blueprint make(ubyte chunkDimension) {
        Blueprint blueprint;
        blueprint.dimension = chunkDimension;
        return blueprint;
    }

    // The stored node is only read while painting, and painting finds the line's node again, so the slot is refreshed
    // here instead of keeping the node alive for as long as the line exists.
    uint lineOf(LineSpec spec, NodeId node) {
        LineKey key = LineKey(node, spec.lower, spec.xSide, spec.ySide);
        const(uint)* found = lineIndex.find(key);
        if (found is null) {
            uint index = cast(uint) lines.length;
            lines.append(spec);
            brushes.append(Array!Brush.init);
            lineIndex.insert(key, index);
            return index;
        } else {
            lines.ptr[*found].node = spec.node;
            return *found;
        }
    }

    uint addTile(NodeId face) {
        tiles.append(TileRecord(Array!uint.init, face, travel, 0, 0, false));
        return cast(uint)(tiles.length - 1);
    }

    void dropTile(uint tile) {
        TileRecord* record = &tiles.ptr[tile];
        foreach (line; record.lines.slice()) {
            Array!Brush* painted = &brushes.ptr[line];
            size_t kept = 0;
            foreach (brush; painted.slice()) {
                if (brush.order < record.firstOrder || brush.order >= record.endOrder) {
                    painted.ptr[kept] = brush;
                    kept += 1;
                }
            }
            painted.length = kept;
            painted.shrink();
        }
        record.lines.release();
        record.isDropped = true;
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
        foreach (ref tile; tiles.slice()) {
            tile.lines.release();
        }
        lines.release();
        brushes.release();
        route.release();
        materials.release();
        tiles.release();
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

    static BlueprintBuilder make(ref Graph target) {
        return BlueprintBuilder(Array!SiteLine.init, &target, 0, false);
    }

    void growFrom(uint key) {
        known.clear();
        paintLimit = cast(int) key - PAINT_REACH;
        isGrowing = true;
    }

    bool isOpen(uint slot) const {
        return cast(int) graph.nodeAt(slot).depth >= paintLimit;
    }

    SiteLine* lineOf(SiteFrame site) {
        uint index = 0;
        while (index < known.length && known.ptr[index].site != site) {
            index += 1;
        }
        if (index == known.length) {
            CanonicalSite canonical = (*graph).canonicalOf(site);
            known.append(SiteLine(site, canonical.transform, graph.blueprint.lineOf(canonical.line, graph.idAt(canonical.line.node))));
        }
        return &known.ptr[index];
    }

    PaintResult paint(SiteFrame site, CellBox box, Rhythm rhythm, Material material, bool isIntoAirOnly) {
        SiteLine* found = lineOf(site);
        ubyte dimension = graph.layout.dimension;
        CellBox canonical = canonicalBox(box, found.transform, dimension);
        int lowEdge = edgeOf(canonical.low[2], dimension);
        int highEdge = edgeOf(canonical.high[2], dimension);
        bool isUnbounded = lowEdge == int.min || highEdge == int.max;
        if (isGrowing && isUnbounded) {
            return PaintResult.endless;
        } else if (isGrowing && !isAhead(*found, lowEdge, highEdge)) {
            return PaintResult.behind;
        } else {
            record(*found, lowEdge, highEdge, isUnbounded);
            Brush brush = Brush(canonical, canonicalRhythm(rhythm, found.transform, dimension), graph.blueprint.brushCount, Paint(graph.blueprint.paintOf(material), isIntoAirOnly));
            graph.blueprint.brushes.ptr[found.line].append(brush);
            graph.blueprint.brushCount += 1;
            return PaintResult.painted;
        }
    }

    // Nodes only gain structure between calls, so levels found open stay open for the rest of a tile or growth step.
    bool isAhead(ref SiteLine found, int lowEdge, int highEdge) {
        if (found.open.contains(lowEdge, highEdge)) {
            return true;
        } else {
            LineSpec spec = graph.blueprint.lines.ptr[found.line];
            SlotTouch edge = seedTouch(spec, found.line);
            bool isClear = true;
            int level = lowEdge;
            while (isClear && level <= highEdge) {
                edge = (*graph).walkedTouch(edge, spec, level);
                foreach (around; (*graph).aroundEdge(edge, spec)) {
                    isClear = isClear && isOpen(around.slot);
                }
                level += 1;
            }
            if (isClear) {
                found.open.include(lowEdge, highEdge);
            }
            return isClear;
        }
    }

    void record(ref SiteLine found, int lowEdge, int highEdge, bool isUnbounded) {
        uint line = found.line;
        LineSpec spec = graph.blueprint.lines.ptr[line];
        if (isUnbounded && !spec.isEndless()) {
            SlotTouch seed = seedTouch(spec, line);
            (*graph).addPendingTouch(seed.slot, seed.touch);
        } else if (!isUnbounded && !spec.isEndless() && !found.touched.contains(lowEdge, highEdge)) {
            touchEdges(line, spec, lowEdge, highEdge);
            found.touched.include(lowEdge, highEdge);
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
        graph.reference(site.node);
    }

    void enter(SiteFrame site, ColumnSpot spot) {
        if (!graph.blueprint.hasEntrance) {
            graph.blueprint.entrance = RouteStop(site, spot);
            graph.blueprint.hasEntrance = true;
            graph.reference(site.node);
        }
    }

    bool claim(ClaimKey key) {
        immutable bool isNewlyClaimed = graph.blueprint.claim(key);
        if (isNewlyClaimed) {
            graph.reference(key.slot);
        }
        return isNewlyClaimed;
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
