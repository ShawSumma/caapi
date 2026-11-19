module client.tiles;

import core.stdc.math : asin, asinh;
import core.stdc.stdlib : calloc, free;
import base.array : Array;
import base.clock : Deadline, nowMilliseconds;
import base.hashmap : HashMap;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : clamped, higherOf, lowerOf;
import base.parallel : Executor, ParallelJob;
import base.splitmix : SplitMix;
import base.stdio : snprintf;
import client.structures : BAD_PEN_DRAW, MESSAGE_CAPACITY, ONLY_WORLD_FLATTENS, ONLY_WORLD_GIVES_KINDS, ONLY_WORLD_OPENS, ONLY_WORLD_ROOTS, ONLY_WORLD_SETS_FOG, ONLY_WORLD_SETS_LOOK, ONLY_WORLD_SHAPES_GROUND, ONLY_WORLD_TILES_EDGES, ONLY_WORLD_TILES_GROUND, ONLY_WORLD_TILES_VERTICES, ONLY_WORLD_TURNS_GRAVITY, PenFrame, Refusing, UNBOUNDED_PAINT, apiBuild, apiColumn, apiCrust, apiEdgeCells, apiFail, apiFailure, apiFill, apiForward, apiHash, apiLeaves, apiLimb, apiOwns, apiPaint, apiVoid, isLeastAround, apiPen, apiPenForward, apiPenHeight, apiPenLift, apiPenRise, apiPenRoll, apiPenTurn, apiPick, apiPort, apiRandom, apiRelief, apiReplace, apiRising, apiTurned, boxRefusal, cellBoxOf, cellLengthOf, columnOf, engineRhythm, ensureRisingTag, probeCrust, probePort, probeRelief, unitNormal;
import common.graph : Exposure, Graph, NodeContent, NodeId;
import common.traversal : PAINT_MILLISECONDS;
import common.view : GraphView;
import common.worldgen.blueprint : Blueprint, Brush, CellBox, Cover, LevelRange, LineEdge, LineKey, LineSpec, Paint, PaintOwner, PaintResult, Rhythm, RouteStop, SiteLine, TileEdge, canonicalBox, canonicalRhythm, edgeOf, probeLineAhead;
import common.worldgen.horospheres : Fill, Ground, Grounds, Horosphere, HorosphereId, HorosphereRef, MOST_GROUNDS, ROOT, RiseMeasure, TileReach, ensureBalanceAlong, ensureGroundNode, ensureGrounds, ensureHorospheresAt, ensureMeasure, ensureMeasured, ensurePlaneIn, ensureSegmentSite, ensureSegmentsNear, probeBelowBottom, probeBuried, probePaintedBy, probeReachedBy, storeMeasure;
import common.worldgen.plane : PlaneMeasure;
import common.worldgen.store : AheadPass, NodeMark, TileKey, edgeBit;
import common.worldgen.strokes : Stroke, StrokeForm, StrokeReached, StrokeWalk;
import common.worldgen.structure : CanonicalSite, ColumnSpot, EDGE_NODES, LineTouch, NODE_EDGES, SiteFrame, SlotTouch, addPendingTouch, canonicalOf, edgeSitesOf, ensureAroundEdge, ensureGroundRing, ensureSiteHash, faceSite, forwarded, frameOf, seedTouch, sideAxis, siteOf, sitePlacement, turnSite, walkTouch;
import geometry.honeycomb : CORNER_COUNT, FACE_COUNT, Face, cornerToNode;
import geometry.lorentz : Motion, Point;
import plugins.api.api : Api, Box, HorosphereForm, KindId, KindTag, Material, Pen, PortRule, Risen, Rising, Site, SitePart, Span, Spot, Structure, Tile, Turn;
import plugins.api.api : ApiRhythm = Rhythm;

enum double INITIAL_MS_PER_TASK = PAINT_MILLISECONDS / 256;
enum double TILE_TASK_LEAST = 64;
enum double TILE_TASK_MOST = 4096;
enum uint PLAN_ROUNDS = 4;
enum double INITIAL_TASKS_PER_CANDIDATE = 4;
enum double LEAST_TASKS_PER_CANDIDATE = 0.25;
enum double PLAN_MARGIN = 1.5;
enum double LEAST_PLANNED = 16;
enum float CEILING_SLACK = 0.02f;
enum uint FACE_CORNERS = 5;
enum int CORNER_LINE_LEVELS = 8;
enum string TILE_CANNOT_PLACE = "a tile cannot place: tiles run in any order, so decide from site:hash";

enum TileSpan : ubyte {
    ground,
    edge,
}

immutable string[TileSpan.max + 1] SPAN_NAMES = [TileSpan.ground: "a ground's", TileSpan.edge: "the edge"];

enum TilePass : ubyte {
    first,
    restoring,
}

enum TaskEnd : ubyte {
    painted,
    failed,
}

enum StopKind : ubyte {
    route,
    entrance,
}

enum PlanEnd : ubyte {
    planned,
    blocked,
    buried,
}

enum Reached : ubyte {
    within,
    beyond,
}

enum Planning : ubyte {
    idle,
    started,
}

enum Census : ubyte {
    off,
    counting,
}

__gshared Census footprintCensus;

struct FootprintCount {
    uint brushes;
    uint strays;
}

__gshared FootprintCount footprintTotal;

struct TileCall {
    Tile tile;
    Array!ubyte data;
}

struct PortCall {
    KindTag ground;
    double most;
    PortRule rule;
    Array!ubyte data;
}

struct FootCall {
    uint tag;
    TileCall call;
}

struct TileCalls {
    TileCall root;
    TileCall vertex;
    Array!TileCall edges;
    Array!TileCall kinds;
    Array!PortCall ports;
    Array!FootCall feet;
    Maybe!float edgeCeiling;

    bool hasRoot() const {
        return root.tile !is null;
    }

    bool hasEdge() const {
        return edges.length > 0;
    }

    MaybeIndex!uint footCallOf(KindTag ground) const {
        uint index = 0;
        while (index < feet.length && !(ground.exists && feet.ptr[index].tag == ground.value)) {
            index += 1;
        }
        if (index < feet.length) {
            return MaybeIndex!uint.of(index);
        } else {
            return MaybeIndex!uint.init;
        }
    }

    MaybeIndex!uint portCallOf(KindTag ground) const {
        uint index = 0;
        while (index < ports.length && ports.ptr[index].ground != ground) {
            index += 1;
        }
        if (index < ports.length) {
            return MaybeIndex!uint.of(index);
        } else {
            return MaybeIndex!uint.init;
        }
    }

    void release() {
        root.data.release();
        vertex.data.release();
        foreach (ref call; edges.slice()) {
            call.data.release();
        }
        edges.release();
        foreach (ref call; kinds.slice()) {
            call.data.release();
        }
        kinds.release();
        foreach (ref call; ports.slice()) {
            call.data.release();
        }
        ports.release();
        foreach (ref foot; feet.slice()) {
            foot.call.data.release();
        }
        feet.release();
    }
}

struct LineOutput {
    LineKey key;
    LineSpec spec;
    LevelRange edges;
}

struct BrushOutput {
    uint line;
    Brush brush;
    Material material;
}

struct TouchOutput {
    uint line;
    int level;
    NodeId[EDGE_NODES] nodes;
    LineTouch[EDGE_NODES] touches;
}

struct StopOutput {
    SiteFrame site;
    ColumnSpot spot;
    uint start;
    uint pathStart;
    uint pathLength;
    StopKind kind;
}

struct StrokeOutput {
    Stroke stroke;
    NodeId node;
    uint reachStart;
    uint reachCount;
}

struct TileOutput {
    uint task;
    uint lineStart;
    uint lineCount;
    uint brushStart;
    uint brushCount;
    uint touchStart;
    uint touchCount;
    uint stopStart;
    uint stopCount;
    uint strokeStart;
    uint strokeCount;
    TaskEnd end;

    bool isBlank() const {
        return lineCount == 0 && brushCount == 0 && touchCount == 0 && stopCount == 0 && strokeCount == 0;
    }
}

struct TilePainter {
    Array!SiteLine known;
    Array!LineOutput lines;
    Array!BrushOutput brushes;
    Array!TouchOutput touches;
    Array!StopOutput stops;
    Array!StrokeOutput strokes;
    Array!Face paths;
    Array!TileOutput outputs;
    Array!uint reached;
    Array!StrokeReached reaches;
    StrokeWalk walk;
    TileOutput current;
    TileReach reach;
    HorosphereId ground;
    TilePass pass;
    Array!ulong corners;
    int lineSlack;
    uint brushesCounted;
    uint strays;

    void clear() {
        lines.clear();
        brushes.clear();
        touches.clear();
        stops.clear();
        strokes.clear();
        paths.clear();
        outputs.clear();
        reaches.clear();
    }

    void begin(uint task, TilePass chosen, HorosphereId over, TileReach bound) {
        known.clear();
        reached.clear();
        ground = over;
        reach = bound;
        pass = chosen;
        current = TileOutput.init;
        current.task = task;
        current.lineStart = cast(uint) lines.length;
        current.brushStart = cast(uint) brushes.length;
        current.touchStart = cast(uint) touches.length;
        current.stopStart = cast(uint) stops.length;
        current.strokeStart = cast(uint) strokes.length;
    }

    void finish(TaskEnd end) {
        current.lineCount = cast(uint) lines.length - current.lineStart;
        current.brushCount = cast(uint) brushes.length - current.brushStart;
        current.touchCount = cast(uint) touches.length - current.touchStart;
        current.stopCount = cast(uint) stops.length - current.stopStart;
        current.strokeCount = cast(uint) strokes.length - current.strokeStart;
        current.end = end;
        outputs.append(current);
    }

    SiteLine* ensureLine(ref GraphView view, SiteFrame site) {
        uint index = 0;
        while (index < known.length && known.ptr[index].site != site) {
            index += 1;
        }
        if (index == known.length) {
            CanonicalSite canonical = view.canonicalOf(site);
            LineKey key = LineKey(view.idAt(canonical.line.node.value), canonical.line.lower, canonical.line.xSide, canonical.line.ySide);
            uint line = current.lineStart;
            while (line < lines.length && lines.ptr[line].key != key) {
                line += 1;
            }
            if (line == lines.length) {
                lines.append(LineOutput(key, canonical.line));
            }
            known.append(SiteLine(site, canonical.transform, line));
        }
        return &known.ptr[index];
    }

    PaintResult paint(ref GraphView view, SiteFrame site, CellBox box, Rhythm rhythm, Material material, Cover cover) {
        SiteLine* found = ensureLine(view, site);
        ubyte dimension = view.layout.dimension;
        CellBox canonical = canonicalBox(box, found.transform, dimension);
        int lowEdge = edgeOf(canonical.low.z, dimension);
        int highEdge = edgeOf(canonical.high.z, dimension);
        if (canonical.isEndless) {
            return PaintResult.endless;
        } else {
            Reached within = Reached.within;
            bool ahead = true;
            if (pass == TilePass.first) {
                bool isClosed(uint slot) {
                    return view.hasStructureAt(slot);
                }
                within = record(view, *found, lowEdge, highEdge);
                ahead = probeLineAhead!isClosed(view, *found, lines.ptr[found.line].spec, lowEdge, highEdge);
            }
            if (within == Reached.beyond) {
                return PaintResult.beyond;
            } else if (!ahead) {
                return PaintResult.behind;
            } else {
                if (footprintCensus == Census.counting && pass == TilePass.first && corners.length > 0) {
                    brushesCounted += 1;
                    if (!isThroughCorner(view, site, edgeOf(box.low.z, dimension) - lineSlack, edgeOf(box.high.z, dimension) + 1 + lineSlack)) {
                        strays += 1;
                    }
                }
                brushes.append(BrushOutput(found.line, Brush(canonical, canonicalRhythm(rhythm, found.transform, dimension), 0, Paint(MaybeIndex!ubyte.init, cover)), material));
                return PaintResult.painted;
            }
        }
    }

    bool isThroughCorner(ref GraphView view, SiteFrame site, int low, int high) {
        int level = low;
        while (level <= high && !isCorner(view.ensureSiteHash(forwarded(site, level), SitePart.vertex))) {
            level += 1;
        }
        return level <= high;
    }

    bool isCorner(ulong vertex) const {
        size_t index = 0;
        while (index < corners.length && corners.ptr[index] != vertex) {
            index += 1;
        }
        return index < corners.length;
    }

    Reached record(ref GraphView view, ref SiteLine found, int lowEdge, int highEdge) {
        LineOutput* line = &lines.ptr[found.line];
        Reached within = Reached.within;
        if (!found.touched.contains(lowEdge, highEdge)) {
            const(uint)* existing = view.blueprint.lineIndex.find(line.key);
            SlotTouch edge = seedTouch(line.spec, found.line);
            foreach (level; lowEdge .. highEdge + 1) {
                bool fresh = existing is null || !view.blueprint.isEdgeTouched(LineEdge(*existing, level));
                if (fresh || reach.isBounded) {
                    edge = view.walkTouch(edge, line.spec, level);
                    TouchOutput touched = TouchOutput(found.line, level);
                    foreach (index, around; view.ensureAroundEdge(edge, line.spec)) {
                        touched.nodes[index] = view.idAt(around.slot);
                        touched.touches[index] = around.touch;
                        if (reach.isBounded && !probeReached(view, around.slot)) {
                            within = Reached.beyond;
                        }
                    }
                    if (fresh) {
                        touches.append(touched);
                    }
                }
            }
            found.touched.include(lowEdge, highEdge);
        }
        line.edges.widen(lowEdge, highEdge);
        return within;
    }

    bool probeReached(ref GraphView view, uint slot) {
        size_t index = 0;
        while (index < reached.length && reached.ptr[index] != slot) {
            index += 1;
        }
        if (index < reached.length) {
            return true;
        } else {
            bool within = view.probeReachedBy(slot, ground);
            if (within) {
                reached.append(slot);
            }
            return within;
        }
    }

    void stop(ref GraphView view, SiteFrame site, ColumnSpot spot, StopKind kind) {
        if (pass == TilePass.first) {
            uint pathStart = cast(uint) paths.length;
            uint start = view.pathTo(site.node, paths);
            stops.append(StopOutput(site, spot, start, pathStart, cast(uint) paths.length - pathStart, kind));
        }
    }

    void stroke(ref GraphView view, PenFrame pen, double length, float startRadius, float endRadius, Material material, StrokeForm form) {
        Stroke drawn = Stroke.make(pen.frame, length, startRadius, endRadius, material, form);
        uint reachStart = cast(uint) reaches.length;
        walk.reach(view, pen.node, drawn, reaches);
        strokes.append(StrokeOutput(drawn, view.idAt(pen.node), reachStart, cast(uint) reaches.length - reachStart));
    }

    void release() {
        known.release();
        lines.release();
        brushes.release();
        touches.release();
        stops.release();
        strokes.release();
        paths.release();
        outputs.release();
        reached.release();
        reaches.release();
        walk.release();
        corners.release();
    }
}

struct TileTask {
    TileKey key;
    uint start;
    uint pathStart;
    uint pathLength;
    MaybeIndex!uint record;
    HorosphereId horosphere;
    SiteFrame site;
    int segment;
    TileSpan span;
    TilePass pass;
}

struct PlannedTile {
    TileKey key;
    uint start;
    uint pathStart;
    uint pathLength;
    HorosphereId horosphere;
    SiteFrame site;
    int segment;
    TileSpan span;
}

struct PlanResult {
    uint candidate;
    uint tileStart;
    uint tileCount;
    PlanEnd end;
    Exposure exposure;
}

struct MeasuredRise {
    HorosphereId horosphere;
    RiseMeasure measure;
}

struct PlanOutputs {
    Array!PlannedTile tiles;
    Array!Face paths;
    Array!PlanResult results;
    Array!uint usedRecords;
    Array!MeasuredRise measures;

    void clear() {
        tiles.clear();
        paths.clear();
        results.clear();
        usedRecords.clear();
        measures.clear();
    }

    bool hasMeasure(HorosphereId horosphere) const {
        uint index = 0;
        while (index < measures.length && measures.ptr[index].horosphere != horosphere) {
            index += 1;
        }
        return index < measures.length;
    }

    void release() {
        tiles.release();
        paths.release();
        results.release();
        usedRecords.release();
        measures.release();
    }
}

bool isTiledBy(ref const Graph graph, ref const TileCalls calls, HorosphereId horosphere) {
    return callFor(graph, calls, horosphere).tile !is null || (horosphere == ROOT && calls.vertex.tile !is null) || (horosphere != ROOT && calls.footCallOf(graph.horospheres.tagOf(horosphere)).exists);
}

const(TileCall)* callFor(ref const Graph graph, ref const TileCalls calls, HorosphereId horosphere) {
    MaybeIndex!ubyte kind = graph.horospheres.kindOf(horosphere);
    if (kind.exists) {
        return &calls.kinds.ptr[kind.value];
    } else {
        return &calls.root;
    }
}

void visitTilesAt(alias onTile)(ref GraphView view, ref const TileCalls calls, uint slot) {
    bool bottomed = view.probeBelowBottom(slot);
    if (!bottomed) {
        if (isTiledBy(*view.graph, calls, ROOT) && view.horospheres.reachOf(ROOT).canReach(view.ensureState(slot).surface)) {
            foreach (face; view.ensureGroundRing(view.ensureGroundNode(slot, ROOT), Face.first)) {
                onTile(view.faceKey(face, Face.first), faceSite(face, Face.first), ROOT, 0, TileSpan.ground);
            }
        }
        size_t count = view.ensureHorospheresAt(slot).length;
        foreach (index; 0 .. count) {
            HorosphereRef near = view.horospheresAt(slot)[index];
            if (!view.isBlocked && isTiledBy(*view.graph, calls, near.horosphere)) {
                if (view.horospheres.isUpright(near.horosphere)) {
                    Span segments = view.ensureSegmentsNear(near);
                    foreach (segment; segments.low .. segments.high + 1) {
                        SiteFrame site = view.ensureSegmentSite(near.horosphere, segment);
                        onTile(view.segmentKey(site), site, near.horosphere, segment, TileSpan.ground);
                    }
                } else {
                    bool painted = view.probePaintedBy(slot, near);
                    if (painted) {
                        Face label = view.horospheres.horosphere(near.horosphere).label;
                        foreach (face; view.ensureGroundRing(view.ensureGroundNode(slot, near.horosphere), label)) {
                            onTile(view.faceKey(face, label), faceSite(face, label), near.horosphere, 0, TileSpan.ground);
                        }
                    }
                }
            }
        }
        if (calls.hasEdge) {
            EdgeOwners owners;
            foreach (site; view.edgeSitesOf(slot)) {
                TileKey key = view.edgeKey(site);
                if (!view.graph.structures.at(site.node).isBlankEdge(key.feature)) {
                    const(OwnerGrounds)* owner = owners.ensure(view, calls, site.node);
                    if (!isOverCeiling(calls, site, *owner)) {
                        onTile(key, site, ROOT, 0, TileSpan.edge);
                    }
                }
            }
        }
    }
}

struct OwnerGrounds {
    uint node;
    Grounds grounds;
    PlaneMeasure[MOST_GROUNDS] surfaces;
}

struct EdgeOwners {
    OwnerGrounds[NODE_EDGES] known = void;
    uint count;

    const(OwnerGrounds)* ensure(ref GraphView view, ref const TileCalls calls, uint node) {
        uint index = 0;
        while (index < count && known[index].node != node) {
            index += 1;
        }
        if (index == count) {
            OwnerGrounds* made = &known[index];
            made.node = node;
            made.grounds = view.ensureGrounds(node);
            if (calls.edgeCeiling.exists) {
                foreach (ground; 0 .. made.grounds.count) {
                    made.surfaces[ground] = made.grounds.items[ground].surface.measure();
                }
            }
            count += 1;
        }
        return &known[index];
    }
}

bool isOverCeiling(ref const TileCalls calls, SiteFrame site, ref const OwnerGrounds owner) {
    if (!calls.edgeCeiling.exists) {
        return false;
    } else {
        Point!float near = site.corner.cornerToNode * Point!float.origin();
        Point!float far = site.nextCorner().cornerToNode * Point!float.origin();
        float ceiling = calls.edgeCeiling.value + CEILING_SLACK;
        uint index = 0;
        while (index < owner.grounds.count && isClearOver(owner.grounds.items[index], owner.surfaces[index], index, near, far, ceiling)) {
            index += 1;
        }
        return index == owner.grounds.count;
    }
}

bool isClearOver(ref const Ground ground, ref const PlaneMeasure surface, uint index, Point!float near, Point!float far, float ceiling) {
    if (index > 0 && ground.fill == Fill.none) {
        return true;
    } else {
        return surface.distanceTo(near) > ceiling && surface.distanceTo(far) > ceiling;
    }
}

Risen risenOf(ref const Graph graph, HorosphereId horosphere, int segment) {
    Risen risen;
    risen.segment = segment;
    risen.tag = graph.horospheres.tagOf(horosphere);
    risen.form = graph.horospheres.formOf(horosphere);
    if (horosphere != ROOT) {
        const(Horosphere)* found = &graph.horospheres.horosphere(horosphere);
        risen.rising = Rising.risen;
        risen.foot = siteOf(found.foot);
        risen.edges = found.edges;
        risen.ground = found.ground;
        risen.balance = found.balance;
        risen.lower = graph.horospheres.tagOf(found.parent);
    }
    return risen;
}

uint slotAlong(View)(ref View view, uint start, const(Face)[] path) {
    uint slot = start;
    foreach (side; path) {
        slot = view.ensureNeighborSlot(slot, side);
    }
    return slot;
}

TileKey faceKey(ref const GraphView view, uint face, Face label) {
    return TileKey(view.idAt(face), label);
}

TileKey segmentKey(ref const GraphView view, SiteFrame site) {
    return TileKey(view.idAt(site.node), cast(ubyte)(FACE_COUNT + site.corner));
}

TileKey edgeKey(ref const GraphView view, SiteFrame site) {
    return TileKey(view.idAt(site.node), cast(ubyte)(FACE_COUNT + CORNER_COUNT + site.corner * 3 + sideAxis(site.corner, site.zSide())));
}

struct SiteValue {
    Site site;
    HorosphereId over;
    double value;
}

struct SiteMemo {
    Array!SiteValue known;

    MaybeIndex!uint find(Site site, HorosphereId over) const {
        uint index = 0;
        while (index < known.length && !(known.ptr[index].site == site && known.ptr[index].over == over)) {
            index += 1;
        }
        if (index < known.length) {
            return MaybeIndex!uint.of(index);
        } else {
            return MaybeIndex!uint.init;
        }
    }

    double value(uint index) const {
        return known.ptr[index].value;
    }

    double keep(Site site, HorosphereId over, double value) {
        known.append(SiteValue(site, over, value));
        return value;
    }
}

struct TileHost {
    TilePainter painter;
    PlanOutputs plan;
    SiteMemo crusts;
    SiteMemo reliefs;
    GraphView* view;
    const(TileCalls)* calls;
    Api api;
    SplitMix random;
    HorosphereId horosphere;
    int segment;
    TileSpan span;
    uint rules;
    TaskEnd taskEnd;
    char[MESSAGE_CAPACITY] failure = 0;

    mixin Refusing;

    void fail(const(char)* message) {
        taskEnd = TaskEnd.failed;
        if (failure[0] == 0) {
            snprintf(failure.ptr, failure.length, "%s (%s tile over horosphere %u of tag %x, segment %d)", message, SPAN_NAMES[span].ptr, horosphere.bits, view.horospheres.tagOf(horosphere).bits, segment);
        }
    }

    ref GraphView hostView() {
        return *view;
    }

    ubyte dimension() const {
        return view.layout.dimension;
    }

    Span column() const {
        return columnOf(dimension());
    }

    double cellLength() const {
        return cellLengthOf(view.layout);
    }

    void run(ref const Graph graph, GraphView* threadView, ref const TileTask task, const(Face)[] path, uint index) {
        view = threadView;
        uint node = (*view).slotAlong(task.start, path);
        TileReach reach = TileReach.init;
        if (task.span == TileSpan.ground) {
            reach = graph.horospheres.reachOf(task.horosphere);
        }
        painter.begin(index, task.pass, task.horosphere, reach);
        crusts.known.clear();
        reliefs.known.clear();
        random = SplitMix(task.key.node.spice() ^ task.key.feature);
        horosphere = task.horosphere;
        segment = task.segment;
        span = task.span;
        taskEnd = TaskEnd.painted;
        SiteFrame site = task.site;
        site.node = node;
        painter.corners.clear();
        painter.lineSlack = 0;
        if (footprintCensus == Census.counting) {
            noteCorners(graph, site, task);
        }
        final switch (task.span) {
            case TileSpan.ground:
                const(TileCall)* call = callFor(graph, *calls, task.horosphere);
                Risen risen = risenOf(graph, task.horosphere, task.segment);
                if (call.tile !is null) {
                    call.tile(&api, siteOf(site), &risen, call.data.ptr);
                    takeRefusal();
                }
                runFoot(site, risen);
                if (task.horosphere == ROOT && calls.vertex.tile !is null) {
                    runVertices(site, risen);
                }
                break;
            case TileSpan.edge:
                foreach (ref call; calls.edges.slice()) {
                    horosphere = task.horosphere;
                    Risen risen = risenOf(graph, task.horosphere, task.segment);
                    call.tile(&api, siteOf(site), &risen, call.data.ptr);
                    takeRefusal();
                    runOverGrounds(graph, &call, site);
                }
                break;
        }
        if (view.isBlocked) {
            view.forget();
        }
        painter.finish(taskEnd);
    }

    void noteCorners(ref const Graph graph, SiteFrame site, ref const TileTask task) {
        final switch (task.span) {
            case TileSpan.ground:
                if (!graph.horospheres.isUpright(task.horosphere)) {
                    painter.lineSlack = CORNER_LINE_LEVELS;
                    SiteFrame corner = site;
                    foreach (index; 0 .. FACE_CORNERS) {
                        painter.corners.append((*view).ensureSiteHash(corner, SitePart.vertex));
                        corner = (*view).turnSite(forwarded(corner, 1), Turn.right);
                    }
                }
                break;
            case TileSpan.edge:
                painter.corners.append((*view).ensureSiteHash(site, SitePart.vertex));
                painter.corners.append((*view).ensureSiteHash(forwarded(site, 1), SitePart.vertex));
                break;
        }
    }

    void runFoot(SiteFrame face, ref const Risen risen) {
        MaybeIndex!uint foot = calls.footCallOf(risen.tag);
        if (risen.hasRisen && foot.exists && isFootOwner(face, frameOf(risen.foot))) {
            const(TileCall)* call = &calls.feet.ptr[foot.value].call;
            if (footprintCensus == Census.counting) {
                painter.corners.clear();
                painter.corners.append((*view).ensureSiteHash(frameOf(risen.foot), SitePart.vertex));
                painter.lineSlack = risen.edges;
            }
            call.tile(&api, risen.foot, &risen, call.data.ptr);
            takeRefusal();
        }
    }

    void runVertices(SiteFrame face, ref const Risen risen) {
        SiteFrame corner = face;
        foreach (index; 0 .. FACE_CORNERS) {
            if (isLeastAround(*view, corner, Turn.right)) {
                if (footprintCensus == Census.counting) {
                    painter.corners.clear();
                    painter.corners.append((*view).ensureSiteHash(corner, SitePart.vertex));
                    painter.lineSlack = CORNER_LINE_LEVELS;
                }
                calls.vertex.tile(&api, siteOf(corner), &risen, calls.vertex.data.ptr);
                takeRefusal();
            }
            corner = (*view).turnSite(forwarded(corner, 1), Turn.right);
        }
    }

    bool isFootOwner(SiteFrame face, SiteFrame foot) {
        ulong vertex = (*view).ensureSiteHash(foot, SitePart.vertex);
        SiteFrame corner = face;
        uint index = 0;
        while (index < FACE_CORNERS && !((*view).ensureSiteHash(corner, SitePart.vertex) == vertex && isLeastAround(*view, corner, Turn.right))) {
            corner = (*view).turnSite(forwarded(corner, 1), Turn.right);
            index += 1;
        }
        return index < FACE_CORNERS;
    }

    void runOverGrounds(ref const Graph graph, const(TileCall)* call, SiteFrame site) {
        Grounds grounds = (*view).ensureGrounds(site.node);
        foreach (ground; grounds.items[1 .. grounds.count]) {
            if (ground.fill != Fill.none) {
                horosphere = ground.horosphere;
                Risen risen = risenOf(graph, ground.horosphere, 0);
                call.tile(&api, siteOf(site), &risen, call.data.ptr);
                takeRefusal();
            }
        }
    }

    void paint(Site site, Material material, Box area, ApiRhythm rhythm, Cover cover) {
        const(char)* wrong = boxRefusal(area, rhythm, column());
        if (wrong !is null) {
            refuse(wrong);
        } else {
            PaintResult result = painter.paint(*view, frameOf(site), cellBoxOf(area), engineRhythm(rhythm), material, cover);
            if (result == PaintResult.endless) {
                refuse(UNBOUNDED_PAINT);
            } else if (result == PaintResult.behind) {
                refuse("paints ground that is already built: a tile paints only near its face");
            } else if (result == PaintResult.beyond) {
                refuse("paints farther from its ground than the reach its world gave that ground's tile");
            }
        }
    }

    void stop(Site site, Spot spot, StopKind kind) {
        painter.stop(*view, frameOf(site), ColumnSpot(spot.x, spot.y, spot.z), kind);
    }

    PenFrame ensurePen(Site site) {
        SiteFrame frame = frameOf(site);
        return PenFrame(sitePlacement(frame, view.layout).as!double(), unitNormal((*view).ensurePlaneIn(horosphere, frame.node)), frame.node);
    }

    void draw(Pen pen, double cells, double fromRadius, double toRadius, Material material, StrokeForm form) {
        if (!(cells >= 0) || !(fromRadius > 0) || !(toRadius > 0)) {
            refuse(BAD_PEN_DRAW);
        } else {
            double cell = cellLength();
            painter.stroke(*view, PenFrame.fromPen(pen), cells * cell, cast(float)(fromRadius * cell), cast(float)(toRadius * cell), material, form);
        }
    }

    KindTag ensureRisingTagAt(Site site) {
        return (*view).ensureRisingTag(site, horosphere);
    }

    bool probePortAt(Site site) {
        rules += 1;
        bool port = (*view).probePort(*calls, &api, site, horosphere);
        rules -= 1;
        return port;
    }

    double probeCrustAt(Site site) {
        MaybeIndex!uint known = crusts.find(site, horosphere);
        if (known.exists) {
            return crusts.value(known.value);
        } else {
            return crusts.keep(site, horosphere, (*view).probeCrust(site, horosphere));
        }
    }

    double probeReliefAt(Site site) {
        MaybeIndex!uint known = reliefs.find(site, horosphere);
        if (known.exists) {
            return reliefs.value(known.value);
        } else {
            return reliefs.keep(site, horosphere, (*view).probeRelief(site, horosphere));
        }
    }

    void planCandidate(ref const Graph graph, GraphView* threadView, uint candidate, uint index) {
        view = threadView;
        uint tileStart = cast(uint) plan.tiles.length;
        PlanEnd end = PlanEnd.planned;
        Exposure exposure = Exposure.unjudged;
        if (!graph.isFinished(candidate)) {
            NodeContent content = graph.nodeAt(candidate).content;
            Exposure judged = graph.nodeAt(candidate).exposure;
            bool buried = judged == Exposure.buried;
            if (judged == Exposure.unjudged && (content == NodeContent.unknown || content == NodeContent.shallow)) {
                buried = (*view).probeBuried(candidate);
                exposure = Exposure.unburied;
                if (buried) {
                    exposure = Exposure.buried;
                }
            }
            if (buried) {
                end = PlanEnd.buried;
            } else {
                void onTile(TileKey key, SiteFrame site, HorosphereId over, int segment, TileSpan span) {
                    planTile(graph, key, site, over, segment, span);
                }
                visitTilesAt!onTile(*view, *calls, candidate);
            }
        }
        if (view.isBlocked) {
            plan.tiles.length = tileStart;
            plan.results.append(PlanResult(index, tileStart, 0, PlanEnd.blocked));
            view.forget();
        } else {
            plan.results.append(PlanResult(index, tileStart, cast(uint) plan.tiles.length - tileStart, end, exposure));
            measureRises(graph, tileStart);
        }
    }

    void measureRises(ref const Graph graph, uint tileStart) {
        foreach (index; tileStart .. plan.tiles.length) {
            HorosphereId over = plan.tiles.ptr[index].horosphere;
            if (over != ROOT && !graph.horospheres.horosphere(over).isMeasured && !plan.hasMeasure(over)) {
                RiseMeasure measure = (*view).ensureMeasure(over);
                if (view.isBlocked) {
                    view.forget();
                } else {
                    plan.measures.append(MeasuredRise(over, measure));
                }
            }
        }
    }

    void planTile(ref const Graph graph, TileKey key, SiteFrame site, HorosphereId over, int segment, TileSpan span) {
        const(uint)* known = graph.structures.tiledFaces.find(key);
        if (known !is null) {
            plan.usedRecords.append(*known);
        }
        if (known is null || graph.structures.blueprint.tiles.ptr[*known].isDropped) {
            uint pathStart = cast(uint) plan.paths.length;
            uint start = view.pathTo(site.node, plan.paths);
            plan.tiles.append(PlannedTile(key, start, pathStart, cast(uint) plan.paths.length - pathStart, over, site, segment, span));
        }
    }

    void release() {
        painter.release();
        plan.release();
        crusts.known.release();
        reliefs.known.release();
    }
}

TileHost* tileHost(const(Api)* api) {
    return cast(TileHost*) api.host;
}

Api tileApi(TileHost* host) {
    Api api;
    api.host = host;
    api.failure = &apiFailure!tileHost;
    api.fail = &apiFail!tileHost;
    api.forward = &apiForward;
    api.turn = &apiTurned!tileHost;
    api.column = &apiColumn!tileHost;
    api.edgeCells = &apiEdgeCells!tileHost;
    api.pick = &apiPick!tileHost;
    api.random = &apiRandom!tileHost;
    api.probeHash = &apiHash!tileHost;
    api.paint = &apiPaint!tileHost;
    api.fill = &apiFill!tileHost;
    api.stop = &tileStop;
    api.entrance = &tileEntrance;
    api.place = &tilePlace;
    api.claim = &tileClaim;
    api.probeClaimed = &tileProbeClaimed;
    api.tile = &tileTile;
    api.tileEdges = &tileTileEdges;
    api.horosphere = &tileHorosphere;
    api.sunken = &tileSunken;
    api.openHorosphere = &tileOpenHorosphere;
    api.columnSite = &tileColumnSite;
    api.flatten = &tileFlatten;
    api.rooted = &tileRooted;
    api.invertGravity = &tileInvertGravity;
    api.fog = &tileFog;
    api.probeRising = &apiRising!tileHost;
    api.probeBalance = &tileBalance;
    api.openPen = &apiPen!tileHost;
    api.penForward = &apiPenForward!tileHost;
    api.penTurn = &apiPenTurn;
    api.penRoll = &apiPenRoll;
    api.penLift = &apiPenLift;
    api.penRise = &apiPenRise;
    api.penHeight = &apiPenHeight!tileHost;
    api.limb = &apiLimb!tileHost;
    api.leaves = &apiLeaves!tileHost;
    api.build = &apiBuild!tileHost;
    api.look = &tileLook;
    api.worldLook = &tileWorldLook;
    api.risingKinds = &tileRisingKinds;
    api.landmark = &tileLandmark;
    api.under = &tileUnder;
    api.crust = &tileCrust;
    api.ports = &tilePorts;
    api.probePort = &apiPort!tileHost;
    api.thinCrust = &tileThinCrust;
    api.probeCrust = &apiCrust!tileHost;
    api.underCrust = &tileUnderCrust;
    api.abyss = &tileAbyss;
    api.edgeCeiling = &tileEdgeCeiling;
    api.probeRelief = &apiRelief!tileHost;
    api.replace = &apiReplace!tileHost;
    api.portRule = &tilePortRule;
    api.tileReach = &tileTileReach;
    api.hanging = &tileHanging;
    api.probeOwns = &apiOwns!tileHost;
    api.paintVoid = &apiVoid;
    api.foot = &tileFoot;
    api.tileVertices = &tileTileVertices;
    return api;
}

void tileTileVertices(const(Api)* api, Tile tile, const(void)* data, size_t size) {
    tileHost(api).refuse(ONLY_WORLD_TILES_VERTICES);
}

KindId tileHanging(const(Api)* api, double odds, uint under, uint edges, uint tag, Tile tile, const(void)* data, size_t size) {
    tileHost(api).refuse(ONLY_WORLD_GIVES_KINDS);
    return KindId.init;
}

void tileFoot(const(Api)* api, uint tag, Tile tile, const(void)* data, size_t size) {
    tileHost(api).refuse(ONLY_WORLD_GIVES_KINDS);
}

void tileTileReach(const(Api)* api, KindTag ground, double above, double below) {
    tileHost(api).refuse(ONLY_WORLD_SHAPES_GROUND);
}

void tilePortRule(const(Api)* api, KindTag ground, double most, PortRule rule, const(void)* data, size_t size) {
    tileHost(api).refuse(ONLY_WORLD_SHAPES_GROUND);
}

void tileEdgeCeiling(const(Api)* api, double cells) {
    tileHost(api).refuse(ONLY_WORLD_TILES_EDGES);
}

void tileStop(const(Api)* api, Site site, Spot spot) {
    tileHost(api).stop(site, spot, StopKind.route);
}

void tileEntrance(const(Api)* api, Site site, Spot spot) {
    tileHost(api).stop(site, spot, StopKind.entrance);
}

bool tilePlace(const(Api)* api, Site site, Structure structure, const(void)* data, size_t size) {
    tileHost(api).refuse(TILE_CANNOT_PLACE);
    return true;
}

bool tileClaim(const(Api)* api, Site site, SitePart part) {
    tileHost(api).refuse("a tile cannot claim: tiles run in any order, so decide from site:hash");
    return true;
}

bool tileProbeClaimed(const(Api)* api, Site site, SitePart part) {
    tileHost(api).refuse("a tile cannot read claims: tiles run in any order, so decide from site:hash");
    return false;
}

void tileTile(const(Api)* api, Tile tile, const(void)* data, size_t size) {
    tileHost(api).refuse(ONLY_WORLD_TILES_GROUND);
}

KindId tileHorosphere(const(Api)* api, double odds, HorosphereForm form, uint tag, Tile tile, const(void)* data, size_t size) {
    tileHost(api).refuse(ONLY_WORLD_GIVES_KINDS);
    return KindId.init;
}

KindId tileSunken(const(Api)* api, double odds, uint under, uint tag, Tile tile, const(void)* data, size_t size) {
    tileHost(api).refuse(ONLY_WORLD_GIVES_KINDS);
    return KindId.init;
}

void tileOpenHorosphere(const(Api)* api, Site site, KindId kind, uint edges) {
    tileHost(api).refuse(ONLY_WORLD_OPENS);
}

Site tileColumnSite(const(Api)* api, Site site) {
    tileHost(api).refuse("only the world's own structure opens horospheres, so only it asks for their frames");
    return site;
}

void tileRooted(const(Api)* api, KindId kind) {
    tileHost(api).refuse(ONLY_WORLD_ROOTS);
}

void tileTileEdges(const(Api)* api, Tile tile, const(void)* data, size_t size) {
    tileHost(api).refuse(ONLY_WORLD_TILES_EDGES);
}

void tileFlatten(const(Api)* api, Site site) {
    tileHost(api).refuse(ONLY_WORLD_FLATTENS);
}

void tileInvertGravity(const(Api)* api) {
    tileHost(api).refuse(ONLY_WORLD_TURNS_GRAVITY);
}

void tileFog(const(Api)* api, double units) {
    tileHost(api).refuse(ONLY_WORLD_SETS_FOG);
}

int tileBalance(const(Api)* api, Site site, int most) {
    TileHost* host = tileHost(api);
    if (host.horosphere == ROOT || host.view.horospheres.isUpright(host.horosphere)) {
        host.refuse("only a horosphere that rose as a plane from another has one to balance against");
        return 0;
    } else if (most < 1) {
        host.refuse("balance looks at least one cell up");
        return 0;
    } else {
        return (*host.view).ensureBalanceAlong((*host.view).turnSite(frameOf(site), Turn.pitchUp), host.horosphere, most);
    }
}

void tileLook(const(Api)* api, KindId kind, const(char)[] look) {
    tileHost(api).refuse(ONLY_WORLD_SETS_LOOK);
}

void tileWorldLook(const(Api)* api, const(char)[] look) {
    tileHost(api).refuse(ONLY_WORLD_SETS_LOOK);
}

void tileRisingKinds(const(Api)* api, double odds) {
    tileHost(api).refuse(ONLY_WORLD_GIVES_KINDS);
}

void tileUnder(const(Api)* api, KindTag ground, const(char)[] look, double depth, double fog) {
    tileHost(api).refuse(ONLY_WORLD_SETS_LOOK);
}

void tileUnderCrust(const(Api)* api, KindTag ground, const(char)[] look, double edges, double fog) {
    tileHost(api).refuse(ONLY_WORLD_SETS_LOOK);
}

void tileCrust(const(Api)* api, KindTag ground, double edges) {
    tileHost(api).refuse(ONLY_WORLD_SHAPES_GROUND);
}

void tileThinCrust(const(Api)* api, KindTag ground, double edges) {
    tileHost(api).refuse(ONLY_WORLD_SHAPES_GROUND);
}

void tileAbyss(const(Api)* api, KindTag ground, double edges) {
    tileHost(api).refuse(ONLY_WORLD_SHAPES_GROUND);
}

void tilePorts(const(Api)* api, double odds) {
    tileHost(api).refuse(ONLY_WORLD_SHAPES_GROUND);
}

bool tileLandmark(const(Api)* api, uint index, Site site) {
    tileHost(api).refuse(TILE_CANNOT_PLACE);
    return false;
}

struct TileJob {
    Graph* graph;
    TileHost** hosts;
    const(TileTask)* tasks;
    const(Face)* paths;
    const(uint)* candidates;
}

void runTileTask(void* context, size_t index, uint worker) {
    TileJob* job = cast(TileJob*) context;
    const(TileTask)* task = &job.tasks[index];
    job.hosts[worker].run(*job.graph, &job.graph.threadViews[worker], *task, job.paths[task.pathStart .. task.pathStart + task.pathLength], cast(uint) index);
}

void planCandidateTask(void* context, size_t index, uint worker) {
    TileJob* job = cast(TileJob*) context;
    job.hosts[worker].planCandidate(*job.graph, &job.graph.threadViews[worker], job.candidates[index], cast(uint) index);
}

struct TaskOutput {
    uint host;
    uint output;
}

struct TileWork {
    Array!(TileHost*) hosts;
    Array!TileTask tasks;
    Array!Face paths;
    Array!TaskOutput outputOf;
    Array!uint lineIndices;
    Array!uint lineFills;
    Array!uint brushOrder;
    Array!uint covered;
    Array!uint planning;
    Array!uint blocked;
    HashMap!(TileKey, uint) taskOf;
    const(TileCalls)* calls;
    TileJob planContext;
    ParallelJob planJob;
    Planning ahead;
    double msPerTask = INITIAL_MS_PER_TASK;
    double tasksPerCandidate = INITIAL_TASKS_PER_CANDIDATE;
    uint preparedTiles;
    uint fallbackTiles;
    char[MESSAGE_CAPACITY] failure = 0;

    bool hasFailed() const {
        return failure[0] != 0;
    }

    void ensureHosts(uint workers) {
        while (hosts.length < workers) {
            TileHost* host = cast(TileHost*) calloc(1, TileHost.sizeof);
            *host = TileHost.init;
            host.api = tileApi(host);
            host.calls = calls;
            hosts.append(host);
        }
    }

    size_t taskBudget(double allowance) const {
        return cast(size_t) clamped(allowance / msPerTask, TILE_TASK_LEAST, TILE_TASK_MOST);
    }

    size_t candidatesFor(size_t room) const {
        return cast(size_t) higherOf(PLAN_MARGIN * room / higherOf(tasksPerCandidate, LEAST_TASKS_PER_CANDIDATE), LEAST_PLANNED);
    }

    void paintAhead(ref Graph target, const(uint)[] candidates, Executor executor, double allowance) {
        assert(ahead == Planning.idle);
        double start = nowMilliseconds();
        size_t budget = taskBudget(allowance);
        ensureHosts(executor.workers);
        covered.clear();
        planning.clear();
        size_t next = 0;
        uint round = 0;
        while (!hasFailed && (planning.length > 0 || next < candidates.length) && round < PLAN_ROUNDS && tasks.length < budget) {
            size_t taken = lowerOf(candidatesFor(budget - tasks.length), candidates.length - next);
            planning.appendAll(candidates[next .. next + taken]);
            next += taken;
            size_t made = planCandidates(target, executor);
            takePlans(target, budget);
            planning.clear();
            if (made > 0) {
                planning.appendAll(blocked.slice());
            }
            round += 1;
        }
        size_t painted = tasks.length;
        preparedTiles += cast(uint) painted;
        runTasks(target, executor);
        markCovered(target);
        if (painted >= TILE_TASK_LEAST) {
            msPerTask = (nowMilliseconds() - start) / painted;
        }
    }

    void startAhead(ref Graph target, const(uint)[] candidates, Executor executor) {
        assert(ahead == Planning.idle);
        ensureHosts(executor.workers);
        planning.clear();
        planning.appendAll(candidates);
        if (planning.length > 0 && !hasFailed) {
            preparePlanning(target, executor);
            executor.start(&planJob);
            ahead = Planning.started;
        }
    }

    AheadPass finishAhead(ref Graph target, Executor executor, double allowance) {
        if (ahead == Planning.started) {
            ahead = Planning.idle;
            executor.join(&planJob);
            collectPlanning(target);
            covered.clear();
            takePlans(target, taskBudget(allowance));
            planning.clear();
            preparedTiles += cast(uint) tasks.length;
            runTasks(target, executor);
            markCovered(target);
            return AheadPass.finished;
        } else {
            return AheadPass.none;
        }
    }

    void takePlans(ref Graph target, size_t budget) {
        size_t before = tasks.length;
        blocked.clear();
        size_t index = 0;
        while (index < planning.length && tasks.length < budget) {
            const(TileHost)* host = hosts.ptr[outputOf.ptr[index].host];
            PlanResult result = host.plan.results.ptr[outputOf.ptr[index].output];
            if (result.end == PlanEnd.blocked) {
                blocked.append(planning.ptr[index]);
            } else if (result.end == PlanEnd.buried) {
                target.nodeAt(planning.ptr[index]).content = NodeContent.deep;
            } else {
                foreach (tile; host.plan.tiles.ptr[result.tileStart .. result.tileStart + result.tileCount]) {
                    addTask(target, tile.key, tile.start, host.plan.paths.ptr[tile.pathStart .. tile.pathStart + tile.pathLength], tile.horosphere, tile.site, tile.segment, tile.span);
                }
                covered.append(planning.ptr[index]);
            }
            index += 1;
        }
        if (index > 0) {
            tasksPerCandidate = cast(double)(tasks.length - before) / index;
        }
    }

    void markCovered(ref Graph target) {
        if (!hasFailed) {
            foreach (slot; covered.slice()) {
                target.structures.at(slot).marks.set(NodeMark.covered);
            }
        }
    }

    size_t planCandidates(ref Graph target, Executor executor) {
        preparePlanning(target, executor);
        executor.run(&planJob);
        return collectPlanning(target);
    }

    void preparePlanning(ref Graph target, Executor executor) {
        foreach (host; hosts.slice()) {
            host.plan.clear();
        }
        target.threadViews.begin(target, executor.workers);
        planContext = TileJob(&target, hosts.ptr, null, null, planning.ptr);
        planJob = ParallelJob(&planCandidateTask, &planContext, Deadline.init, planning.length);
    }

    size_t collectPlanning(ref Graph target) {
        size_t made = target.threadViews.finish(target);
        outputOf.resize(planning.length);
        foreach (hostIndex, host; hosts.slice()) {
            foreach (record; host.plan.usedRecords.slice()) {
                target.structures.blueprint.useTile(record);
            }
            foreach (measured; host.plan.measures.slice()) {
                if (!target.horospheres.horosphere(measured.horosphere).isMeasured) {
                    target.storeMeasure(measured.horosphere, measured.measure);
                }
            }
            foreach (resultIndex, result; host.plan.results.slice()) {
                outputOf.ptr[result.candidate] = TaskOutput(cast(uint) hostIndex, cast(uint) resultIndex);
                if (result.exposure != Exposure.unjudged && target.nodeAt(planning.ptr[result.candidate]).exposure == Exposure.unjudged) {
                    target.nodeAt(planning.ptr[result.candidate]).exposure = result.exposure;
                }
            }
        }
        return made;
    }

    void takeFailure(const(TileHost)* host) {
        failure = host.failure;
    }

    void clearTasks() {
        tasks.clear();
        paths.clear();
        taskOf.clear();
    }

    void addTask(ref Graph target, TileKey key, uint start, const(Face)[] path, HorosphereId horosphere, SiteFrame site, int segment, TileSpan span) {
        if (taskOf.find(key) is null) {
            const(uint)* known = target.structures.tiledFaces.find(key);
            if (known is null || target.structures.blueprint.tiles.ptr[*known].isDropped) {
                MaybeIndex!uint record;
                TilePass pass = TilePass.first;
                if (known !is null) {
                    record = MaybeIndex!uint.of(*known);
                    target.structures.blueprint.tiles.ptr[record.value].horosphere = horosphere;
                    pass = TilePass.restoring;
                }
                if (horosphere != ROOT) {
                    target.horospheres.horospheres.ptr[horosphere.index].tiles += 1;
                    target.ensureMeasured(horosphere);
                }
                taskOf.insert(key, cast(uint) tasks.length);
                tasks.append(TileTask(key, start, cast(uint) paths.length, cast(uint) path.length, record, horosphere, site, segment, span, pass));
                paths.appendAll(path);
            }
        }
    }

    uint ensureRecord(ref Graph target, ref const TileTask task, uint face) {
        Blueprint* blueprint = &target.structures.blueprint;
        if (task.record.exists) {
            blueprint.reviveTile(task.record.value);
            target.structures.linkTile(face, task.record.value);
            return task.record.value;
        } else {
            uint record = blueprint.addTile(task.key.node, task.key.feature, task.horosphere);
            target.structures.tiledFaces.insert(task.key, record);
            target.structures.linkTile(face, record);
            return record;
        }
    }

    void apply(ref Graph target, ref const TileTask task, ref const TilePainter painter, TileOutput output) {
        uint face = target.slotAlong(task.start, paths.ptr[task.pathStart .. task.pathStart + task.pathLength]);
        if (task.span == TileSpan.edge && output.isBlank) {
            target.structures.at(face).blankEdges |= edgeBit(task.key.feature);
        } else {
            keep(target, task, ensureRecord(target, task, face), painter, output);
        }
    }

    void runTasks(ref Graph target, Executor executor) {
        assert(ahead == Planning.idle);
        ensureHosts(executor.workers);
        if (tasks.length > 0 && !hasFailed) {
            foreach (host; hosts.slice()) {
                host.painter.clear();
            }
            target.threadViews.begin(target, executor.workers);
            TileJob context = TileJob(&target, hosts.ptr, tasks.ptr, paths.ptr, null);
            ParallelJob job = ParallelJob(&runTileTask, &context, Deadline.init, tasks.length);
            executor.run(&job);
            target.threadViews.finish(target);
            foreach (host; hosts.slice()) {
                footprintTotal.brushes += host.painter.brushesCounted;
                footprintTotal.strays += host.painter.strays;
                host.painter.brushesCounted = 0;
                host.painter.strays = 0;
            }
            outputOf.resize(tasks.length);
            foreach (hostIndex, host; hosts.slice()) {
                foreach (outputIndex, output; host.painter.outputs.slice()) {
                    outputOf.ptr[output.task] = TaskOutput(cast(uint) hostIndex, cast(uint) outputIndex);
                }
            }
            size_t index = 0;
            while (index < tasks.length && !hasFailed) {
                TileHost* host = hosts.ptr[outputOf.ptr[index].host];
                TileOutput output = host.painter.outputs.ptr[outputOf.ptr[index].output];
                if (output.end == TaskEnd.failed) {
                    takeFailure(host);
                } else {
                    apply(target, tasks.ptr[index], host.painter, output);
                }
                index += 1;
            }
            foreach (host; hosts.slice()) {
                host.painter.reaches.release();
            }
        }
        clearTasks();
    }

    void keep(ref Graph target, ref const TileTask task, uint record, ref const TilePainter painter, TileOutput output) {
        Blueprint* blueprint = &target.structures.blueprint;
        lineIndices.resize(output.lineCount);
        uint[] lines = lineIndices.slice();
        foreach (local; 0 .. output.lineCount) {
            const(LineOutput)* line = &painter.lines.ptr[output.lineStart + local];
            LineSpec spec = line.spec;
            spec.node = MaybeIndex!uint.init;
            uint index = blueprint.ensureLine(spec, line.key.node);
            blueprint.lines.ptr[index].edges.widen(line.edges);
            lines[local] = index;
        }
        const(BrushOutput)[] painted = painter.brushes.ptr[output.brushStart .. output.brushStart + output.brushCount];
        blueprint.tiles.ptr[record].painted.brushes.reserve(output.brushCount);
        lineFills.resize(output.lineCount + 1);
        lineFills.slice()[] = 0;
        foreach (made; painted) {
            lineFills.ptr[made.line - output.lineStart + 1] += 1;
        }
        foreach (local; 0 .. output.lineCount) {
            lineFills.ptr[local + 1] += lineFills.ptr[local];
        }
        brushOrder.resize(output.brushCount);
        foreach (index, made; painted) {
            uint local = made.line - output.lineStart;
            brushOrder.ptr[lineFills.ptr[local]] = cast(uint) index;
            lineFills.ptr[local] += 1;
        }
        foreach (index; brushOrder.slice()) {
            const(BrushOutput)* made = &painted[index];
            Brush brush = made.brush;
            brush.order = index;
            brush.paint.material = blueprint.ensurePaint(made.material);
            blueprint.addBrush(PaintOwner.ofTile(record), lines[made.line - output.lineStart], brush);
        }
        foreach (touched; painter.touches.ptr[output.touchStart .. output.touchStart + output.touchCount]) {
            uint line = lines[touched.line - output.lineStart];
            if (!blueprint.isEdgeTouched(LineEdge(line, touched.level))) {
                blueprint.touchEdge(LineEdge(line, touched.level), touched.nodes);
                foreach (corner; 0 .. EDGE_NODES) {
                    LineTouch touch = touched.touches[corner];
                    touch.line = line;
                    target.addPendingTouch(touched.nodes[corner], touch);
                }
            }
        }
        if (task.pass == TilePass.first) {
            useEdges(blueprint, record, painted, lines, output.lineStart);
        }
        foreach (stop; painter.stops.ptr[output.stopStart .. output.stopStart + output.stopCount]) {
            uint slot = target.slotAlong(stop.start, painter.paths.ptr[stop.pathStart .. stop.pathStart + stop.pathLength]);
            SiteFrame site = stop.site;
            site.node = slot;
            if (stop.kind == StopKind.route) {
                blueprint.route.append(RouteStop(site, stop.spot));
                target.reference(slot);
            } else if (!blueprint.entrance.exists) {
                blueprint.entrance = Maybe!RouteStop.of(RouteStop(site, stop.spot));
                target.reference(slot);
            }
        }
        foreach (ref drawn; painter.strokes.ptr[output.strokeStart .. output.strokeStart + output.strokeCount]) {
            target.structures.addReachedStroke(PaintOwner.ofTile(record), drawn.node, drawn.stroke, painter.reaches.ptr[drawn.reachStart .. drawn.reachStart + drawn.reachCount]);
        }
        blueprint.useTile(record);
        if (task.pass == TilePass.restoring) {
            blueprint.restoredTiles += 1;
        }
    }

    void useEdges(Blueprint* blueprint, uint tile, const(BrushOutput)[] painted, const(uint)[] lines, uint lineStart) {
        Array!TileEdge* edges = &blueprint.tiles.ptr[tile].edges;
        foreach (ref made; painted) {
            uint line = lines[made.line - lineStart];
            foreach (level; edgeOf(made.brush.box.low.z, blueprint.dimension) .. edgeOf(made.brush.box.high.z, blueprint.dimension) + 1) {
                LineEdge edge = LineEdge(line, level);
                size_t index = 0;
                while (index < edges.length && edges.ptr[index].edge != edge) {
                    index += 1;
                }
                if (index == edges.length) {
                    edges.append(TileEdge(edge, blueprint.useEdge(edge)));
                }
            }
        }
    }

    void release() {
        foreach (host; hosts.slice()) {
            host.release();
            free(host);
        }
        hosts.release();
        tasks.release();
        paths.release();
        outputOf.release();
        lineIndices.release();
        lineFills.release();
        brushOrder.release();
        covered.release();
        planning.release();
        blocked.release();
        taskOf.release();
    }
}
