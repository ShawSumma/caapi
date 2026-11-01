module common.worldgen.blueprint;

import base.array : Array;
import base.hashmap : FIBONACCI_MULTIPLIER, HashMap;
import base.numbers : higherOf, lowerOf;
import base.splitmix : SplitMix;
import common.graph : Graph, NodeId;
import common.material : MATERIAL_COUNT;
import common.worldgen.strokes : Stroke, StrokeRun;
import common.worldgen.structure : CanonicalSite, ClaimKey, EDGE_NODES, ColumnSpot, LineTransform, PAINT_REACH, SiteFrame, SlotTouch, addPendingTouch, aroundEdge, canonicalOf, edgeCells, isEndless, seedTouch, walkedTouch;
import geometry.honeycomb : Corner, FACE_COUNT, Face;
import plugins.api.api : Look, Material;

enum uint PLACED_RECORD = uint.max;
enum uint KEPT_USERS = uint.max;
enum ulong PLACED_RANK = 0;
enum ulong TILE_RANK_BIT = 1;
enum ubyte TEST_DIMENSION = 12;

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

struct BrushRank {
    ulong tile;
    uint index;

    bool isBefore(BrushRank other) const {
        return tile < other.tile || (tile == other.tile && index < other.index);
    }
}

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
    Corner lower;
    Face xSide;
    Face ySide;
}

struct LineKey {
    NodeId node;
    Corner lower;
    Face xSide;
    Face ySide;

    size_t toHash() const {
        return node.toHash() ^ ((cast(size_t) lower * FACE_COUNT + xSide) * FACE_COUNT + ySide);
    }
}

struct LineEdge {
    uint line;
    int level;

    size_t toHash() const {
        return cast(size_t)(line * FIBONACCI_MULTIPLIER) ^ cast(uint) level;
    }
}

struct RouteStop {
    SiteFrame site;
    ColumnSpot spot;
}

struct LineRun {
    uint line;
    uint first;
    uint count;
}

struct Painted {
    Array!Brush brushes;
    Array!LineRun runs;
    Array!Stroke strokes;
    Array!StrokeRun strokeRuns;
    Array!NodeId reached;

    void release() {
        brushes.release();
        runs.release();
        strokes.release();
        strokeRuns.release();
        reached.release();
    }
}

struct RunRef {
    uint record;
    uint run;
    int lowEdge;
    int highEdge;
}

enum TileState : ubyte {
    live,
    dropped,
    free,
}

struct TileEdge {
    LineEdge edge;
    NodeId[EDGE_NODES] nodes;
}

struct TileRecord {
    Painted painted;
    Array!TileEdge edges;
    NodeId face;
    uint horosphere;
    uint listIndex;
    ubyte feature;
    TileState state;

    bool isDropped() const {
        return state == TileState.dropped;
    }
}

struct EdgeRecord {
    NodeId[EDGE_NODES] nodes;
    uint users;
}

struct LineState {
    NodeId node;
    uint edges;
    uint touchers;
    bool isKept;
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
    Array!LineState lineStates;
    Array!uint freeLines;
    Array!(Array!RunRef) runsOn;
    Array!uint linePins;
    Painted placed;
    Array!TileRecord tiles;
    Array!uint liveTiles;
    Array!uint liveUses;
    Array!uint droppedTiles;
    Array!uint freeTiles;
    Array!RouteStop route;
    Array!Material materials;
    ubyte[MATERIAL_COUNT] paints;
    HashMap!(LineKey, uint) lineIndex;
    HashMap!(LineEdge, EdgeRecord) touchedEdges;
    HashMap!(ClaimKey, bool) claims;
    RouteStop entrance;
    Look look;
    float fog = float.infinity;
    uint sweep;
    uint madeLive;
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

    uint lineOf(LineSpec spec, NodeId node) {
        LineKey key = LineKey(node, spec.lower, spec.xSide, spec.ySide);
        const(uint)* found = lineIndex.find(key);
        if (found !is null) {
            lines.ptr[*found].node = spec.node;
            return *found;
        } else if (freeLines.length > 0) {
            freeLines.length -= 1;
            uint index = freeLines.ptr[freeLines.length];
            lines.ptr[index] = spec;
            lineStates.ptr[index] = LineState(node);
            lineIndex.insert(key, index);
            return index;
        } else {
            uint index = cast(uint) lines.length;
            lines.append(spec);
            lineStates.append(LineState(node));
            runsOn.append(Array!RunRef.init);
            linePins.append(0);
            lineIndex.insert(key, index);
            return index;
        }
    }

    void keepLine(uint line) {
        lineStates.ptr[line].isKept = true;
    }

    void forgetLineIfUnused(uint line) {
        LineState* state = &lineStates.ptr[line];
        if (!state.isKept && state.edges == 0 && state.touchers == 0 && linePins.ptr[line] == 0 && runsOn.ptr[line].length == 0) {
            LineSpec spec = lines.ptr[line];
            lineIndex.remove(LineKey(state.node, spec.lower, spec.xSide, spec.ySide));
            runsOn.ptr[line].release();
            lines.ptr[line] = LineSpec.init;
            *state = LineState.init;
            freeLines.append(line);
        }
    }

    bool isEdgeTouched(LineEdge edge) const {
        return touchedEdges.find(edge) !is null;
    }

    void touchEdge(LineEdge edge, NodeId[EDGE_NODES] nodes) {
        touchedEdges.insert(edge, EdgeRecord(nodes, 0));
        lineStates.ptr[edge.line].edges += 1;
    }

    NodeId[EDGE_NODES] useEdge(LineEdge edge) {
        EdgeRecord* found = touchedEdges.find(edge);
        if (found.users != KEPT_USERS) {
            found.users += 1;
        }
        return found.nodes;
    }

    void keepEdge(LineEdge edge) {
        touchedEdges.find(edge).users = KEPT_USERS;
    }

    bool releaseEdge(LineEdge edge) {
        EdgeRecord* found = touchedEdges.find(edge);
        if (found.users != KEPT_USERS) {
            found.users -= 1;
        }
        return found.users == 0;
    }

    uint[3] edgeUses() const {
        uint[3] uses;
        foreach (ref const edge, ref const record; touchedEdges) {
            if (record.users == KEPT_USERS) {
                uses[0] += 1;
            } else if (record.users > 0) {
                uses[1] += 1;
            } else {
                uses[2] += 1;
            }
        }
        return uses;
    }

    size_t edgeCount() const {
        size_t count = 0;
        foreach (state; lineStates.slice()) {
            count += state.edges;
        }
        return count;
    }

    void forgetEdge(LineEdge edge) {
        touchedEdges.remove(edge);
        lineStates.ptr[edge.line].edges -= 1;
        forgetLineIfUnused(edge.line);
    }

    uint addTile(NodeId face, ubyte feature, uint horosphere) {
        TileRecord made = TileRecord(Painted.init, Array!TileEdge.init, face, horosphere, 0, feature, TileState.live);
        uint tile = cast(uint) tiles.length;
        if (freeTiles.length > 0) {
            freeTiles.length -= 1;
            tile = freeTiles.ptr[freeTiles.length];
            tiles.ptr[tile] = made;
        } else {
            tiles.append(made);
        }
        addLive(tile);
        return tile;
    }

    void reviveTile(uint tile) {
        TileRecord* record = &tiles.ptr[tile];
        if (record.isDropped) {
            unlist(droppedTiles, tile);
            record.state = TileState.live;
            addLive(tile);
        }
    }

    void useTile(uint tile) {
        if (tiles.ptr[tile].state == TileState.live) {
            liveUses.ptr[tiles.ptr[tile].listIndex] = sweep;
        }
    }

    void addLive(uint tile) {
        enlist(liveTiles, tile);
        liveUses.append(sweep);
        madeLive += 1;
    }

    void removeLive(uint tile) {
        uint at = tiles.ptr[tile].listIndex;
        liveUses.ptr[at] = liveUses.ptr[liveUses.length - 1];
        liveUses.length -= 1;
        unlist(liveTiles, tile);
    }

    void freeTile(uint tile) {
        unlist(droppedTiles, tile);
        tiles.ptr[tile].edges.release();
        tiles.ptr[tile] = TileRecord.init;
        tiles.ptr[tile].state = TileState.free;
        freeTiles.append(tile);
    }

    void enlist(ref Array!uint list, uint tile) {
        tiles.ptr[tile].listIndex = cast(uint) list.length;
        list.append(tile);
    }

    void unlist(ref Array!uint list, uint tile) {
        uint at = tiles.ptr[tile].listIndex;
        uint last = list.ptr[list.length - 1];
        list.ptr[at] = last;
        tiles.ptr[last].listIndex = at;
        list.length -= 1;
    }

    ref inout(Painted) paintedBy(uint record) inout return {
        if (record == PLACED_RECORD) {
            return placed;
        } else {
            return tiles.ptr[record].painted;
        }
    }

    uint takeOrders(uint count) {
        uint first = brushCount;
        brushCount += count;
        return first;
    }

    uint addStroke(uint record, NodeId node, Stroke stroke) {
        Painted* painted = &paintedBy(record);
        if (painted.strokeRuns.length == 0 || painted.strokeRuns.ptr[painted.strokeRuns.length - 1].node != node) {
            painted.strokeRuns.append(StrokeRun(node, cast(uint) painted.strokes.length, 0));
        }
        painted.strokeRuns.ptr[painted.strokeRuns.length - 1].count += 1;
        painted.strokes.append(stroke);
        return cast(uint)(painted.strokeRuns.length - 1);
    }

    void addBrush(uint record, uint line, Brush brush) {
        Painted* painted = &paintedBy(record);
        int lowEdge = edgeOf(brush.box.low[2], dimension);
        int highEdge = edgeOf(brush.box.high[2], dimension);
        uint run = cast(uint) painted.runs.length - 1;
        if (painted.runs.length == 0 || painted.runs.ptr[run].line != line) {
            painted.runs.append(LineRun(line, cast(uint) painted.brushes.length, 0));
            run = cast(uint) painted.runs.length - 1;
            runsOn.ptr[line].append(RunRef(record, run, lowEdge, highEdge));
        } else {
            Array!RunRef* listed = &runsOn.ptr[line];
            size_t at = listed.length - 1;
            while (listed.ptr[at].record != record || listed.ptr[at].run != run) {
                at -= 1;
            }
            listed.ptr[at].lowEdge = lowerOf(listed.ptr[at].lowEdge, lowEdge);
            listed.ptr[at].highEdge = higherOf(listed.ptr[at].highEdge, highEdge);
        }
        painted.runs.ptr[run].count += 1;
        painted.brushes.append(brush);
    }

    void dropTile(uint tile) {
        TileRecord* record = &tiles.ptr[tile];
        foreach (index, run; record.painted.runs.slice()) {
            Array!RunRef* listed = &runsOn.ptr[run.line];
            size_t at = 0;
            while (listed.ptr[at].record != tile || listed.ptr[at].run != index) {
                at += 1;
            }
            listed.length -= 1;
            listed.ptr[at] = listed.ptr[listed.length];
        }
        record.painted.release();
        removeLive(tile);
        record.state = TileState.dropped;
        enlist(droppedTiles, tile);
    }

    void collectBrushes(uint line, int level, ref Array!Brush into, ref Array!BrushRank ranks) const {
        foreach (listed; runsOn.ptr[line].slice()) {
            if (listed.lowEdge > level || listed.highEdge < level) {
                continue;
            }
            const(Painted)* painted = &paintedBy(listed.record);
            LineRun run = painted.runs.ptr[listed.run];
            ulong tile = tileRank(listed.record);
            foreach (brush; painted.brushes.ptr[run.first .. run.first + run.count]) {
                if (edgeOf(brush.box.low[2], dimension) <= level && edgeOf(brush.box.high[2], dimension) >= level) {
                    into.append(brush);
                    ranks.append(BrushRank(tile, brush.order));
                }
            }
        }
    }

    ulong tileRank(uint record) const {
        if (record == PLACED_RECORD) {
            return PLACED_RANK;
        } else {
            const(TileRecord)* tile = &tiles.ptr[record];
            return SplitMix(tile.face.spice() ^ (tile.feature * FIBONACCI_MULTIPLIER)).next() | TILE_RANK_BIT;
        }
    }

    size_t brushTotal() const {
        size_t total = placed.brushes.length;
        foreach (ref tile; tiles.slice()) {
            total += tile.painted.brushes.length;
        }
        return total;
    }

    ubyte paintOf(Material material) {
        if (paints[material] == 0) {
            materials.append(material);
            paints[material] = cast(ubyte) materials.length;
        }
        return paints[material];
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
        foreach (ref tile; tiles.slice()) {
            tile.painted.release();
            tile.edges.release();
        }
        foreach (ref listed; runsOn.slice()) {
            listed.release();
        }
        lines.release();
        lineStates.release();
        freeLines.release();
        runsOn.release();
        linePins.release();
        placed.release();
        tiles.release();
        liveTiles.release();
        liveUses.release();
        droppedTiles.release();
        freeTiles.release();
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

    static BlueprintBuilder make(ref Graph target) {
        return BlueprintBuilder(Array!SiteLine.init, &target, 0, false);
    }

    void growFrom(uint key) {
        known.clear();
        paintLimit = cast(int) key - PAINT_REACH;
        isGrowing = true;
    }

    ref Blueprint blueprint() {
        return graph.structures.blueprint;
    }

    bool isOpen(uint slot) const {
        return cast(int) graph.depthOf(slot) >= paintLimit;
    }

    SiteLine* lineOf(SiteFrame site) {
        uint index = 0;
        while (index < known.length && known.ptr[index].site != site) {
            index += 1;
        }
        if (index == known.length) {
            CanonicalSite canonical = graph.view.canonicalOf(site);
            known.append(SiteLine(site, canonical.transform, blueprint.lineOf(canonical.line, graph.idAt(canonical.line.node))));
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
            blueprint.keepLine(found.line);
            blueprint.addBrush(PLACED_RECORD, found.line, Brush(canonical, canonicalRhythm(rhythm, found.transform, dimension), blueprint.takeOrders(1), Paint(blueprint.paintOf(material), isIntoAirOnly)));
            return PaintResult.painted;
        }
    }

    bool isAhead(ref SiteLine found, int lowEdge, int highEdge) {
        if (found.open.contains(lowEdge, highEdge)) {
            return true;
        } else {
            LineSpec spec = blueprint.lines.ptr[found.line];
            SlotTouch edge = seedTouch(spec, found.line);
            bool isClear = true;
            int level = lowEdge;
            while (isClear && level <= highEdge) {
                edge = graph.view.walkedTouch(edge, spec, level);
                foreach (around; graph.view.aroundEdge(edge, spec)) {
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
        LineSpec spec = blueprint.lines.ptr[line];
        if (isUnbounded && !spec.isEndless()) {
            SlotTouch seed = seedTouch(spec, line);
            (*graph).addPendingTouch(seed.slot, seed.touch);
        } else if (!isUnbounded && !spec.isEndless() && !found.touched.contains(lowEdge, highEdge)) {
            touchEdges(line, spec, lowEdge, highEdge);
            found.touched.include(lowEdge, highEdge);
        }
        LineSpec* stored = &blueprint.lines.ptr[line];
        stored.lowest = lowerOf(spec.lowest, lowEdge);
        stored.highest = higherOf(spec.highest, highEdge);
    }

    void touchEdges(uint line, ref const LineSpec spec, int lowEdge, int highEdge) {
        SlotTouch edge = seedTouch(spec, line);
        foreach (level; lowEdge .. highEdge + 1) {
            LineEdge key = LineEdge(line, level);
            if (!blueprint.isEdgeTouched(key)) {
                edge = graph.view.walkedTouch(edge, spec, level);
                NodeId[EDGE_NODES] nodes = void;
                foreach (index, around; graph.view.aroundEdge(edge, spec)) {
                    nodes[index] = graph.idAt(around.slot);
                    (*graph).addPendingTouch(around.slot, around.touch);
                }
                blueprint.touchEdge(key, nodes);
            }
            blueprint.keepEdge(key);
        }
    }

    void stop(SiteFrame site, ColumnSpot spot) {
        blueprint.route.append(RouteStop(site, spot));
        graph.reference(site.node);
    }

    void enter(SiteFrame site, ColumnSpot spot) {
        if (!blueprint.hasEntrance) {
            blueprint.entrance = RouteStop(site, spot);
            blueprint.hasEntrance = true;
            graph.reference(site.node);
        }
    }

    bool claim(ClaimKey key) {
        bool isNewlyClaimed = blueprint.claim(key);
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

unittest {
    int edge = edgeCells(TEST_DIMENSION);
    assert(edgeOf(-3, TEST_DIMENSION) == -1 && edgeOf(0, TEST_DIMENSION) == 0);
    assert(edgeOf(edge - 1, TEST_DIMENSION) == 0 && edgeOf(edge, TEST_DIMENSION) == 1);
    assert(edgeOf(-edge, TEST_DIMENSION) == -1 && edgeOf(-edge - 1, TEST_DIMENSION) == -2);
    assert(edgeOf(int.min, TEST_DIMENSION) == int.min && edgeOf(int.max, TEST_DIMENSION) == int.max);
    LineTransform mirrored = LineTransform(2, 1, 1, -1, false);
    Rhythm local = Rhythm(8, 1, 3);
    Rhythm moved = canonicalRhythm(local, mirrored, TEST_DIMENSION);
    foreach (height; -20 .. 20) {
        assert(local.includes(height) == moved.includes(mirrored.offsetLevels * edge - 1 - height));
    }
}
