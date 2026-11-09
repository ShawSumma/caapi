module common.worldgen.blueprint;

import base.array : Array;
import base.hashmap : FIBONACCI_MULTIPLIER, HashMap, Present;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : higherOf, lowerOf;
import base.splitmix : SplitMix;
import base.vector3 : Vec3;
import common.graph : Graph, NodeId;
import common.look : Look;
import common.view : GraphView;
import common.worldgen.horospheres : HorosphereId;
import common.worldgen.strokes : Stroke, StrokeRun;
import common.worldgen.structure : AxisOrder, CanonicalSite, ClaimKey, ColumnSpot, EDGE_NODES, LineTransform, PAINT_REACH, SiteFrame, SlotTouch, addPendingTouch, canonicalOf, edgeCells, ensureAroundEdge, isEndless, seedTouch, walkTouch;
import geometry.honeycomb : Corner, FACE_COUNT, Face;
import plugins.api.api : Extent, MOST_MATERIALS, Material, Repeat, Span;

enum ulong PLACED_RANK = 0;
enum ulong TILE_RANK_BIT = 1;

enum Cover : ubyte {
    over,
    intoAir,
}

struct Paint {
    MaybeIndex!ubyte material;
    Cover cover;
}

struct PaintOwner {
    MaybeIndex!uint tile;

    static PaintOwner ofTile(uint index) {
        return PaintOwner(MaybeIndex!uint.of(index));
    }
}

struct CellBox {
    Vec3!int low;
    Vec3!int high;
    Extent extent;

    static CellBox make(int xLow, int xHigh, int yLow, int yHigh, int zLow, int zHigh) {
        return CellBox(Vec3!int(xLow, yLow, zLow), Vec3!int(xHigh, yHigh, zHigh));
    }

    static CellBox alongLine(int xLow, int xHigh, int yLow, int yHigh) {
        return CellBox(Vec3!int(xLow, yLow, 0), Vec3!int(xHigh, yHigh, 0), Extent.endless);
    }

    bool isEndless() const {
        return extent == Extent.endless;
    }

    bool contains(Vec3!int cell) const {
        return cell.x >= low.x && cell.x <= high.x && cell.y >= low.y && cell.y <= high.y && (isEndless || (cell.z >= low.z && cell.z <= high.z));
    }

    bool overlaps(ref const CellBox other) const {
        return low.x <= other.high.x && other.low.x <= high.x && low.y <= other.high.y && other.low.y <= high.y && (isEndless || other.isEndless || (low.z <= other.high.z && other.low.z <= high.z));
    }

    bool reachesEdge(int level, ubyte dimension) const {
        return isEndless || (edgeOf(low.z, dimension) <= level && edgeOf(high.z, dimension) >= level);
    }
}

struct Rhythm {
    int period;
    int phase;
    int span;
    Repeat repeat;

    bool includes(int height) const {
        final switch (repeat) {
            case Repeat.always:
                return true;
            case Repeat.rhythmic:
                int offset = (height - phase) % period;
                if (offset < 0) {
                    offset += period;
                }
                return offset < span;
        }
    }
}

enum Rhythm EVERY_HEIGHT = Rhythm(0, 0, 0, Repeat.always);

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

    bool covers(Vec3!int column) const {
        return box.contains(column) && rhythm.includes(column.z);
    }
}

struct LineSpec {
    LevelRange edges;
    MaybeIndex!uint node;
    Corner lower;
    Face xSide;
    Face ySide;
    Extent extent;
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
    PaintOwner owner;
    uint run;
    int lowEdge;
    int highEdge;
    Extent extent;

    bool reachesEdge(int level) const {
        return extent == Extent.endless || (lowEdge <= level && highEdge >= level);
    }
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
    HorosphereId horosphere;
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
    LineLife life;
}

struct EdgeUses {
    uint kept;
    uint used;
    uint unused;
}

struct LineState {
    NodeId node;
    uint edges;
    uint touchers;
    LineLife life;
}

struct SiteLine {
    SiteFrame site;
    LineTransform transform;
    uint line;
    LevelRange open;
    LevelRange touched;
}

enum Coverage : ubyte {
    empty,
    covered,
}

struct LevelRange {
    int low;
    int high;
    Coverage coverage;

    bool contains(int first, int last) const {
        return coverage == Coverage.covered && first >= low && last <= high;
    }

    void include(int first, int last) {
        if (coverage == Coverage.covered && first <= high + 1L && last >= low - 1L) {
            low = lowerOf(low, first);
            high = higherOf(high, last);
        } else {
            low = first;
            high = last;
            coverage = Coverage.covered;
        }
    }

    void widen(int first, int last) {
        if (coverage == Coverage.covered) {
            low = lowerOf(low, first);
            high = higherOf(high, last);
        } else {
            low = first;
            high = last;
            coverage = Coverage.covered;
        }
    }

    void widen(ref const LevelRange other) {
        if (other.coverage == Coverage.covered) {
            widen(other.low, other.high);
        }
    }
}

enum PaintResult : ubyte {
    painted,
    endless,
    behind,
}

enum LineLife : ubyte {
    loose,
    kept,
}

enum BuilderPhase : ubyte {
    placing,
    growing,
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
    Array!SiteFrame flats;
    Array!Material materials;
    MaybeIndex!ubyte[MOST_MATERIALS] paints;
    HashMap!(LineKey, uint) lineIndex;
    HashMap!(LineEdge, EdgeRecord) touchedEdges;
    HashMap!(ClaimKey, Present) claims;
    Maybe!RouteStop entrance;
    Look look;
    Maybe!float fog;
    uint sweep;
    uint madeLive;
    uint brushCount;
    uint claimCount;
    uint restoredTiles;
    ubyte dimension;

    static Blueprint make(ubyte chunkDimension) {
        Blueprint blueprint;
        blueprint.dimension = chunkDimension;
        return blueprint;
    }

    uint ensureLine(LineSpec spec, NodeId node) {
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
        lineStates.ptr[line].life = LineLife.kept;
    }

    void forgetLineIfUnused(uint line) {
        LineState* state = &lineStates.ptr[line];
        if (state.life == LineLife.loose && state.edges == 0 && state.touchers == 0 && linePins.ptr[line] == 0 && runsOn.ptr[line].length == 0) {
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
        touchedEdges.insert(edge, EdgeRecord(nodes));
        lineStates.ptr[edge.line].edges += 1;
    }

    NodeId[EDGE_NODES] useEdge(LineEdge edge) {
        EdgeRecord* found = touchedEdges.find(edge);
        found.users += 1;
        return found.nodes;
    }

    void keepEdge(LineEdge edge) {
        touchedEdges.find(edge).life = LineLife.kept;
    }

    bool releaseEdge(LineEdge edge) {
        EdgeRecord* found = touchedEdges.find(edge);
        found.users -= 1;
        return found.life == LineLife.loose && found.users == 0;
    }

    EdgeUses edgeUses() const {
        EdgeUses uses;
        foreach (ref const edge, ref const record; touchedEdges) {
            if (record.life == LineLife.kept) {
                uses.kept += 1;
            } else if (record.users > 0) {
                uses.used += 1;
            } else {
                uses.unused += 1;
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

    uint addTile(NodeId face, ubyte feature, HorosphereId horosphere) {
        TileRecord made;
        made.face = face;
        made.horosphere = horosphere;
        made.feature = feature;
        made.state = TileState.live;
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

    ref inout(Painted) paintedBy(PaintOwner owner) inout return {
        if (owner.tile.exists) {
            return tiles.ptr[owner.tile.value].painted;
        } else {
            return placed;
        }
    }

    uint takeOrders(uint count) {
        uint first = brushCount;
        brushCount += count;
        return first;
    }

    uint addStroke(PaintOwner owner, NodeId node, Stroke stroke) {
        Painted* painted = &paintedBy(owner);
        if (painted.strokeRuns.length == 0 || painted.strokeRuns.ptr[painted.strokeRuns.length - 1].node != node) {
            painted.strokeRuns.append(StrokeRun(node, cast(uint) painted.strokes.length, 0));
        }
        painted.strokeRuns.ptr[painted.strokeRuns.length - 1].count += 1;
        painted.strokes.append(stroke);
        return cast(uint)(painted.strokeRuns.length - 1);
    }

    void addBrush(PaintOwner owner, uint line, Brush brush) {
        Painted* painted = &paintedBy(owner);
        int lowEdge = edgeOf(brush.box.low.z, dimension);
        int highEdge = edgeOf(brush.box.high.z, dimension);
        uint run = cast(uint) painted.runs.length - 1;
        if (painted.runs.length == 0 || painted.runs.ptr[run].line != line) {
            painted.runs.append(LineRun(line, cast(uint) painted.brushes.length, 0));
            run = cast(uint) painted.runs.length - 1;
            runsOn.ptr[line].append(RunRef(owner, run, lowEdge, highEdge, brush.box.extent));
        } else {
            Array!RunRef* listed = &runsOn.ptr[line];
            size_t at = listed.length - 1;
            while (listed.ptr[at].owner != owner || listed.ptr[at].run != run) {
                at -= 1;
            }
            listed.ptr[at].lowEdge = lowerOf(listed.ptr[at].lowEdge, lowEdge);
            listed.ptr[at].highEdge = higherOf(listed.ptr[at].highEdge, highEdge);
            if (brush.box.isEndless) {
                listed.ptr[at].extent = Extent.endless;
            }
        }
        painted.runs.ptr[run].count += 1;
        painted.brushes.append(brush);
    }

    void dropTile(uint tile) {
        TileRecord* record = &tiles.ptr[tile];
        foreach (index, run; record.painted.runs.slice()) {
            Array!RunRef* listed = &runsOn.ptr[run.line];
            size_t at = 0;
            while (listed.ptr[at].owner != PaintOwner.ofTile(tile) || listed.ptr[at].run != index) {
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
            if (listed.reachesEdge(level)) {
                const(Painted)* painted = &paintedBy(listed.owner);
                LineRun run = painted.runs.ptr[listed.run];
                ulong tile = tileRank(listed.owner);
                foreach (brush; painted.brushes.ptr[run.first .. run.first + run.count]) {
                    if (brush.box.reachesEdge(level, dimension)) {
                        into.append(brush);
                        ranks.append(BrushRank(tile, brush.order));
                    }
                }
            }
        }
    }

    ulong tileRank(PaintOwner owner) const {
        if (owner.tile.exists) {
            const(TileRecord)* tile = &tiles.ptr[owner.tile.value];
            return SplitMix(tile.face.spice() ^ (tile.feature * FIBONACCI_MULTIPLIER)).next() | TILE_RANK_BIT;
        } else {
            return PLACED_RANK;
        }
    }

    size_t brushTotal() const {
        size_t total = placed.brushes.length;
        foreach (ref tile; tiles.slice()) {
            total += tile.painted.brushes.length;
        }
        return total;
    }

    MaybeIndex!ubyte ensurePaint(Material material) {
        if (!paints[material.id].exists) {
            paints[material.id] = MaybeIndex!ubyte.of(cast(ubyte) materials.length);
            materials.append(material);
        }
        return paints[material.id];
    }

    bool isClaimed(ClaimKey key) const {
        return claims.find(key) !is null;
    }

    bool claim(ClaimKey key) {
        if (isClaimed(key)) {
            return false;
        } else {
            claims.insert(key, Present.init);
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
        flats.release();
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
    BuilderPhase phase;

    static BlueprintBuilder make(ref Graph target) {
        return BlueprintBuilder(Array!SiteLine.init, &target, 0, BuilderPhase.placing);
    }

    bool isGrowing() const {
        return phase == BuilderPhase.growing;
    }

    void growFrom(uint key) {
        known.clear();
        paintLimit = cast(int) key - PAINT_REACH;
        phase = BuilderPhase.growing;
    }

    ref Blueprint blueprint() {
        return graph.structures.blueprint;
    }

    bool isOpen(uint slot) const {
        return cast(int) graph.depthOf(slot) >= paintLimit;
    }

    SiteLine* ensureLine(SiteFrame site) {
        uint index = 0;
        while (index < known.length && known.ptr[index].site != site) {
            index += 1;
        }
        if (index == known.length) {
            CanonicalSite canonical = graph.view.canonicalOf(site);
            known.append(SiteLine(site, canonical.transform, blueprint.ensureLine(canonical.line, graph.idAt(canonical.line.node.value))));
        }
        return &known.ptr[index];
    }

    PaintResult paint(SiteFrame site, CellBox box, Rhythm rhythm, Material material, Cover cover) {
        SiteLine* found = ensureLine(site);
        ubyte dimension = graph.layout.dimension;
        CellBox canonical = canonicalBox(box, found.transform, dimension);
        int lowEdge = edgeOf(canonical.low.z, dimension);
        int highEdge = edgeOf(canonical.high.z, dimension);
        if (isGrowing && canonical.isEndless) {
            return PaintResult.endless;
        } else {
            bool ahead = true;
            if (isGrowing) {
                bool isClosed(uint slot) {
                    return !isOpen(slot);
                }
                ahead = probeLineAhead!isClosed(graph.view, *found, blueprint.lines.ptr[found.line], lowEdge, highEdge);
            }
            if (!ahead) {
                return PaintResult.behind;
            } else {
                if (canonical.isEndless) {
                    recordEndless(found.line);
                } else {
                    record(*found, lowEdge, highEdge);
                }
                blueprint.keepLine(found.line);
                blueprint.addBrush(PaintOwner.init, found.line, Brush(canonical, canonicalRhythm(rhythm, found.transform, dimension), blueprint.takeOrders(1), Paint(blueprint.ensurePaint(material), cover)));
                return PaintResult.painted;
            }
        }
    }

    void recordEndless(uint line) {
        LineSpec spec = blueprint.lines.ptr[line];
        if (!spec.isEndless()) {
            SlotTouch seed = seedTouch(spec, line);
            (*graph).addPendingTouch(seed.slot, seed.touch);
        }
        blueprint.lines.ptr[line].extent = Extent.endless;
    }

    void record(ref SiteLine found, int lowEdge, int highEdge) {
        uint line = found.line;
        LineSpec spec = blueprint.lines.ptr[line];
        if (!spec.isEndless() && !found.touched.contains(lowEdge, highEdge)) {
            touchEdges(line, spec, lowEdge, highEdge);
            found.touched.include(lowEdge, highEdge);
        }
        blueprint.lines.ptr[line].edges.widen(lowEdge, highEdge);
    }

    void touchEdges(uint line, ref const LineSpec spec, int lowEdge, int highEdge) {
        SlotTouch edge = seedTouch(spec, line);
        foreach (level; lowEdge .. highEdge + 1) {
            LineEdge key = LineEdge(line, level);
            if (!blueprint.isEdgeTouched(key)) {
                edge = graph.view.walkTouch(edge, spec, level);
                NodeId[EDGE_NODES] nodes = void;
                foreach (index, around; graph.view.ensureAroundEdge(edge, spec)) {
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
        if (!blueprint.entrance.exists) {
            blueprint.entrance = Maybe!RouteStop.of(RouteStop(site, spot));
            graph.reference(site.node);
        }
    }

    bool claim(ClaimKey key) {
        bool claimed = blueprint.claim(key);
        if (claimed) {
            graph.reference(key.slot);
        }
        return claimed;
    }

    void release() {
        known.release();
    }
}

bool probeLineAhead(alias isClosed)(ref GraphView view, ref SiteLine found, LineSpec spec, int lowEdge, int highEdge) {
    if (found.open.contains(lowEdge, highEdge)) {
        return true;
    } else {
        SlotTouch edge = seedTouch(spec, found.line);
        int level = lowEdge;
        while (level <= highEdge) {
            edge = view.walkTouch(edge, spec, level);
            foreach (around; view.ensureAroundEdge(edge, spec)) {
                if (isClosed(around.slot)) {
                    return false;
                }
            }
            level += 1;
        }
        found.open.include(lowEdge, highEdge);
        return true;
    }
}

CellBox canonicalBox(CellBox local, LineTransform transform, ubyte dimension) {
    Span x = signedRange(local.low.x, local.high.x, transform.xSign);
    Span y = signedRange(local.low.y, local.high.y, transform.ySign);
    Span z = heightRange(local.low.z, local.high.z, transform, dimension);
    if (transform.order == AxisOrder.swapped) {
        return CellBox(Vec3!int(y.low, x.low, z.low), Vec3!int(y.high, x.high, z.high), local.extent);
    } else {
        return CellBox(Vec3!int(x.low, y.low, z.low), Vec3!int(x.high, y.high, z.high), local.extent);
    }
}

Span signedRange(int low, int high, int sign) {
    if (sign > 0) {
        return Span(low, high);
    } else {
        return Span(-1 - high, -1 - low);
    }
}

Span heightRange(int low, int high, LineTransform transform, ubyte dimension) {
    int offset = transform.offsetLevels * edgeCells(dimension);
    if (transform.zSign > 0) {
        return Span(low + offset, high + offset);
    } else {
        return Span(offset - 1 - high, offset - 1 - low);
    }
}

Rhythm canonicalRhythm(Rhythm local, LineTransform transform, ubyte dimension) {
    int offset = transform.offsetLevels * edgeCells(dimension);
    if (local.repeat == Repeat.always) {
        return local;
    } else if (transform.zSign > 0) {
        return Rhythm(local.period, local.phase + offset, local.span);
    } else {
        return Rhythm(local.period, offset - local.phase - local.span, local.span);
    }
}

int edgeOf(int height, ubyte dimension) {
    return floorDivision(height, edgeCells(dimension));
}

int floorDivision(int value, int divisor) {
    int quotient = value / divisor;
    if (value % divisor != 0 && value < 0) {
        quotient -= 1;
    }
    return quotient;
}
