module client.tiles;

import core.stdc.math : asin, asinh;
import core.stdc.stdlib : calloc, free;
import base.array : Array;
import base.hashmap : HashMap;
import base.clock : Deadline, nowMilliseconds;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : clamped;
import base.parallel : Executor, ParallelJob;
import base.splitmix : SplitMix;
import base.stdio : snprintf;
import client.structures : BAD_PEN_DRAW, MESSAGE_CAPACITY, ONLY_WORLD_FLATTENS, ONLY_WORLD_GIVES_KINDS, ONLY_WORLD_OPENS, ONLY_WORLD_ROOTS, ONLY_WORLD_SETS_FOG, ONLY_WORLD_SETS_LOOK, ONLY_WORLD_TILES_EDGES, ONLY_WORLD_TILES_GROUND, ONLY_WORLD_TURNS_GRAVITY, PenFrame, Refusing, UNBOUNDED_PAINT, apiBuild, apiColumn, apiEdgeCells, apiFail, apiFailure, apiFill, apiForward, apiHash, apiLeaves, apiLimb, apiPaint, apiPen, apiPenForward, apiPenHeight, apiPenLift, apiPenRise, apiPenRoll, apiPenTurn, apiPick, apiRandom, apiRising, apiTurned, boxRefusal, cellBoxOf, cellLengthOf, columnOf, engineRhythm, ensureRisingTag, unitNormal;
import common.graph : Graph, NodeId;
import common.view : GraphView;
import common.worldgen.blueprint : Blueprint, Brush, CellBox, Cover, LevelRange, LineEdge, LineKey, LineSpec, Paint, PaintOwner, PaintResult, Rhythm, RouteStop, SiteLine, TileEdge, canonicalBox, canonicalRhythm, edgeOf, probeLineAhead;
import common.worldgen.horospheres : Horosphere, HorosphereId, HorosphereRef, ROOT, RiseMeasure, ensureBalanceAlong, ensureGroundNode, ensureHorospheresAt, ensureMeasure, ensureMeasured, ensurePlaneIn, ensureSegmentSite, ensureSegmentsNear, probePaintedBy, storeMeasure;
import common.worldgen.store : NodeMark, TileKey;
import common.worldgen.strokes : Stroke, StrokeForm;
import common.worldgen.structure : CanonicalSite, ColumnSpot, EDGE_NODES, LineTouch, SiteFrame, SlotTouch, addPendingTouch, canonicalOf, edgeSitesOf, ensureAroundEdge, ensureGroundRing, faceSite, frameOf, seedTouch, sideAxis, siteOf, sitePlacement, turnSite, walkTouch;
import geometry.honeycomb : CORNER_COUNT, FACE_COUNT, Face;
import geometry.lorentz : Motion;
import plugins.api.api : Api, Box, HorosphereForm, KindId, KindTag, Look, Material, Pen, Risen, Rising, Site, SitePart, Span, Spot, Structure, Tile, Turn;
import plugins.api.api : ApiRhythm = Rhythm;

enum double PAINT_AHEAD_MILLISECONDS = 2.0;
enum double INITIAL_MS_PER_TASK = PAINT_AHEAD_MILLISECONDS / 256;
enum double TILE_TASK_LEAST = 64;
enum double TILE_TASK_MOST = 4096;
enum uint PLAN_ROUNDS = 4;
enum string TILE_CANNOT_PLACE = "a tile cannot place: tiles run in any order, so decide from site:hash";

enum TileSpan : ubyte {
    ground,
    edge,
}

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
}

struct TileCall {
    Tile tile;
    Array!ubyte data;
}

struct TileCalls {
    TileCall root;
    TileCall edge;
    Array!TileCall kinds;

    bool hasRoot() const {
        return root.tile !is null;
    }

    bool hasEdge() const {
        return edge.tile !is null;
    }

    void release() {
        root.data.release();
        edge.data.release();
        foreach (ref call; kinds.slice()) {
            call.data.release();
        }
        kinds.release();
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
    Motion!double frame;
    double length;
    float startRadius;
    float endRadius;
    Material material;
    StrokeForm form;
    uint start;
    uint pathStart;
    uint pathLength;
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
    TileOutput current;
    TilePass pass;

    void clear() {
        lines.clear();
        brushes.clear();
        touches.clear();
        stops.clear();
        strokes.clear();
        paths.clear();
        outputs.clear();
    }

    void begin(uint task, TilePass chosen) {
        known.clear();
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
            bool ahead = true;
            if (pass == TilePass.first) {
                bool isClosed(uint slot) {
                    return view.hasStructureAt(slot);
                }
                ahead = probeLineAhead!isClosed(view, *found, lines.ptr[found.line].spec, lowEdge, highEdge);
            }
            if (!ahead) {
                return PaintResult.behind;
            } else {
                if (pass == TilePass.first) {
                    record(view, *found, lowEdge, highEdge);
                }
                brushes.append(BrushOutput(found.line, Brush(canonical, canonicalRhythm(rhythm, found.transform, dimension), 0, Paint(MaybeIndex!ubyte.init, cover)), material));
                return PaintResult.painted;
            }
        }
    }

    void record(ref GraphView view, ref SiteLine found, int lowEdge, int highEdge) {
        LineOutput* line = &lines.ptr[found.line];
        if (!found.touched.contains(lowEdge, highEdge)) {
            const(uint)* existing = view.blueprint.lineIndex.find(line.key);
            SlotTouch edge = seedTouch(line.spec, found.line);
            foreach (level; lowEdge .. highEdge + 1) {
                if (existing is null || !view.blueprint.isEdgeTouched(LineEdge(*existing, level))) {
                    edge = view.walkTouch(edge, line.spec, level);
                    TouchOutput touched = TouchOutput(found.line, level);
                    foreach (index, around; view.ensureAroundEdge(edge, line.spec)) {
                        touched.nodes[index] = view.idAt(around.slot);
                        touched.touches[index] = around.touch;
                    }
                    touches.append(touched);
                }
            }
            found.touched.include(lowEdge, highEdge);
        }
        line.edges.widen(lowEdge, highEdge);
    }

    void stop(ref GraphView view, SiteFrame site, ColumnSpot spot, StopKind kind) {
        if (pass == TilePass.first) {
            uint pathStart = cast(uint) paths.length;
            uint start = view.pathTo(site.node, paths);
            stops.append(StopOutput(site, spot, start, pathStart, cast(uint) paths.length - pathStart, kind));
        }
    }

    void stroke(ref GraphView view, PenFrame pen, double length, float startRadius, float endRadius, Material material, StrokeForm form) {
        uint pathStart = cast(uint) paths.length;
        uint start = view.pathTo(pen.node, paths);
        strokes.append(StrokeOutput(pen.frame, length, startRadius, endRadius, material, form, start, pathStart, cast(uint) paths.length - pathStart));
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
    }
}

struct TileTask {
    TileKey key;
    uint start;
    uint pathStart;
    uint pathLength;
    uint record;
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
    return callFor(graph, calls, horosphere).tile !is null;
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
    if (isTiledBy(*view.graph, calls, ROOT)) {
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
        foreach (site; view.edgeSitesOf(slot)) {
            onTile(view.edgeKey(site), site, ROOT, 0, TileSpan.edge);
        }
    }
}

Risen risenOf(ref const Graph graph, HorosphereId horosphere, int segment) {
    Risen risen;
    risen.segment = segment;
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

TileKey faceKey(ref const GraphView view, uint face, Face label) {
    return TileKey(view.idAt(face), label);
}

TileKey segmentKey(ref const GraphView view, SiteFrame site) {
    return TileKey(view.idAt(site.node), cast(ubyte)(FACE_COUNT + site.corner));
}

TileKey edgeKey(ref const GraphView view, SiteFrame site) {
    return TileKey(view.idAt(site.node), cast(ubyte)(FACE_COUNT + CORNER_COUNT + site.corner * 3 + sideAxis(site.corner, site.zSide())));
}

struct TileHost {
    TilePainter painter;
    PlanOutputs plan;
    GraphView* view;
    const(TileCalls)* calls;
    Api api;
    SplitMix random;
    HorosphereId horosphere;
    int segment;
    TaskEnd taskEnd;
    char[MESSAGE_CAPACITY] failure = 0;

    mixin Refusing;

    void fail(const(char)* message) {
        taskEnd = TaskEnd.failed;
        if (failure[0] == 0) {
            snprintf(failure.ptr, failure.length, "%s (tile over horosphere %u, segment %d)", message, horosphere.bits, segment);
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
        uint node = task.start;
        foreach (side; path) {
            node = view.ensureNeighborSlot(node, side);
        }
        painter.begin(index, task.pass);
        random = SplitMix(task.key.node.spice() ^ task.key.feature);
        horosphere = task.horosphere;
        segment = task.segment;
        taskEnd = TaskEnd.painted;
        const(TileCall)* call = &calls.edge;
        if (task.span == TileSpan.ground) {
            call = callFor(graph, *calls, task.horosphere);
        }
        Risen risen = risenOf(graph, task.horosphere, task.segment);
        SiteFrame site = task.site;
        site.node = node;
        call.tile(&api, siteOf(site), &risen, call.data.ptr);
        takeRefusal();
        painter.finish(taskEnd);
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

    void planCandidate(ref const Graph graph, GraphView* threadView, uint candidate, uint index) {
        view = threadView;
        uint tileStart = cast(uint) plan.tiles.length;
        if (!graph.isFinished(candidate)) {
            void onTile(TileKey key, SiteFrame site, HorosphereId over, int segment, TileSpan span) {
                planTile(graph, key, site, over, segment, span);
            }
            visitTilesAt!onTile(*view, *calls, candidate);
        }
        if (view.isBlocked) {
            plan.tiles.length = tileStart;
            plan.results.append(PlanResult(index, tileStart, 0, PlanEnd.blocked));
            view.forget();
        } else {
            plan.results.append(PlanResult(index, tileStart, cast(uint) plan.tiles.length - tileStart, PlanEnd.planned));
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
    return api;
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

void tileLook(const(Api)* api, KindId kind, const(Look)* look) {
    tileHost(api).refuse(ONLY_WORLD_SETS_LOOK);
}

void tileWorldLook(const(Api)* api, const(Look)* look) {
    tileHost(api).refuse(ONLY_WORLD_SETS_LOOK);
}

void tileRisingKinds(const(Api)* api, double odds) {
    tileHost(api).refuse(ONLY_WORLD_GIVES_KINDS);
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
    double msPerTask = INITIAL_MS_PER_TASK;
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

    size_t taskBudget() const {
        return cast(size_t) clamped(PAINT_AHEAD_MILLISECONDS / msPerTask, TILE_TASK_LEAST, TILE_TASK_MOST);
    }

    void paintAhead(ref Graph target, const(uint)[] candidates, Executor executor) {
        double start = nowMilliseconds();
        size_t budget = taskBudget();
        ensureHosts(executor.workers);
        covered.clear();
        planning.clear();
        planning.appendAll(candidates);
        uint round = 0;
        while (!hasFailed && planning.length > 0 && round < PLAN_ROUNDS && tasks.length < budget) {
            size_t made = planCandidates(target, executor);
            blocked.clear();
            size_t index = 0;
            while (index < planning.length && tasks.length < budget) {
                const(TileHost)* host = hosts.ptr[outputOf.ptr[index].host];
                PlanResult result = host.plan.results.ptr[outputOf.ptr[index].output];
                if (result.end == PlanEnd.blocked) {
                    blocked.append(planning.ptr[index]);
                } else {
                    foreach (tile; host.plan.tiles.ptr[result.tileStart .. result.tileStart + result.tileCount]) {
                        addTask(target, tile.key, tile.start, host.plan.paths.ptr[tile.pathStart .. tile.pathStart + tile.pathLength], tile.horosphere, tile.site, tile.segment, tile.span);
                    }
                    covered.append(planning.ptr[index]);
                }
                index += 1;
            }
            planning.clear();
            planning.appendAll(blocked.slice());
            round += 1;
            if (made == 0) {
                break;
            }
        }
        size_t painted = tasks.length;
        preparedTiles += cast(uint) painted;
        runTasks(target, executor);
        if (!hasFailed) {
            foreach (slot; covered.slice()) {
                target.structures.at(slot).marks.set(NodeMark.covered);
            }
        }
        if (painted >= TILE_TASK_LEAST) {
            msPerTask = (nowMilliseconds() - start) / painted;
        }
    }

    size_t planCandidates(ref Graph target, Executor executor) {
        foreach (host; hosts.slice()) {
            host.plan.clear();
        }
        target.threadViews.begin(target, executor.workers);
        TileJob context = TileJob(&target, hosts.ptr, null, null, planning.ptr);
        ParallelJob job = ParallelJob(&planCandidateTask, &context, Deadline.init,planning.length);
        executor.run(&job);
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
            Maybe!uint record;
            TilePass pass = TilePass.first;
            if (known is null) {
                record = Maybe!uint.of(target.structures.blueprint.addTile(key.node, key.feature, horosphere));
                target.structures.tiledFaces.insert(key, record.value);
            } else if (target.structures.blueprint.tiles.ptr[*known].isDropped) {
                record = Maybe!uint.of(*known);
                target.structures.blueprint.tiles.ptr[record.value].horosphere = horosphere;
                pass = TilePass.restoring;
            }
            if (record.exists) {
                if (horosphere != ROOT) {
                    target.horospheres.horospheres.ptr[horosphere.index].tiles += 1;
                    target.ensureMeasured(horosphere);
                }
                taskOf.insert(key, cast(uint) tasks.length);
                tasks.append(TileTask(key, start, cast(uint) paths.length, cast(uint) path.length, record.value, horosphere, site, segment, span, pass));
                paths.appendAll(path);
            }
        }
    }

    void runTasks(ref Graph target, Executor executor) {
        ensureHosts(executor.workers);
        if (tasks.length > 0 && !hasFailed) {
            foreach (host; hosts.slice()) {
                host.painter.clear();
            }
            target.threadViews.begin(target, executor.workers);
            TileJob context = TileJob(&target, hosts.ptr, tasks.ptr, paths.ptr, null);
            ParallelJob job = ParallelJob(&runTileTask, &context, Deadline.init,tasks.length);
            executor.run(&job);
            target.threadViews.finish(target);
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
        }
        clearTasks();
    }

    uint slotAlong(ref Graph target, ref const TilePainter painter, uint start, uint pathStart, uint pathLength) {
        uint slot = start;
        foreach (side; painter.paths.ptr[pathStart .. pathStart + pathLength]) {
            slot = target.ensureNeighborSlot(slot, side);
        }
        return slot;
    }

    void apply(ref Graph target, ref const TileTask task, ref const TilePainter painter, TileOutput output) {
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
        blueprint.tiles.ptr[task.record].painted.brushes.reserve(output.brushCount);
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
            blueprint.addBrush(PaintOwner.ofTile(task.record), lines[made.line - output.lineStart], brush);
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
            useEdges(blueprint, task.record, painted, lines, output.lineStart);
        }
        foreach (stop; painter.stops.ptr[output.stopStart .. output.stopStart + output.stopCount]) {
            uint slot = slotAlong(target, painter, stop.start, stop.pathStart, stop.pathLength);
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
        foreach (drawn; painter.strokes.ptr[output.strokeStart .. output.strokeStart + output.strokeCount]) {
            uint slot = slotAlong(target, painter, drawn.start, drawn.pathStart, drawn.pathLength);
            target.structures.addStroke(target.view, PaintOwner.ofTile(task.record), slot, Stroke.make(drawn.frame, drawn.length, drawn.startRadius, drawn.endRadius, drawn.material, drawn.form));
        }
        blueprint.reviveTile(task.record);
        blueprint.useTile(task.record);
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
