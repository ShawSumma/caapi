module client.tiles;

import core.stdc.math : asin, asinh;
import core.stdc.stdlib : calloc, free;
import core.stdc.string : memcpy, strlen;
import base.array : Array;
import base.hashmap : HashMap;
import base.clock : nowMilliseconds;
import base.numbers : RADIANS_PER_DEGREE, clamped, higherOf, lowerOf;
import base.parallel : Executor, ParallelJob;
import base.splitmix : SplitMix;
import client.structures : AHEAD, ACROSS, MESSAGE_CAPACITY, PenFrame, UP, axisOf, boxRefusal, engineRhythm, unitNormal, worldNamed;
import common.graph : Graph, NO_SLOT, NodeId;
import common.view : GraphView;
import common.worldgen.blueprint : Blueprint, Brush, CellBox, LineEdge, LineKey, LineSpec, Paint, PaintResult, Rhythm, RouteStop, SiteLine, TileEdge, canonicalBox, canonicalRhythm, edgeOf;
import common.worldgen.horospheres : Horosphere, HorosphereRef, NO_RISE, ROOT, Rise, RiseMeasure, balanceAlong, ensureHorospheresAt, groundNodeOf, isPaintedBy, measureOf, measuredHorosphere, planeOfHorosphereIn, riseAt, segmentSite, segmentsNear, storeMeasure;
import common.worldgen.store : TileKey;
import common.worldgen.strokes : Stroke;
import common.worldgen.structure : CanonicalSite, ColumnSpot, EDGE_NODES, GROUND_RING, LineTouch, SiteFrame, SlotTouch, addPendingTouch, aroundEdge, atLevel, canonicalOf, edgeCells, edgeLength, edgeSitesOf, faceSite, forwarded, frameOf, groundRing, seedTouch, sideAxis, siteHash, siteOf, sitePlacement, turned, walkedTouch;
import geometry.honeycomb : CORNER_COUNT, FACE_COUNT, Face;
import geometry.lorentz : Motion;
import plugins.api.api : Api, Box, Column, HorosphereForm, Look, Material, NO_KIND, Pen, Risen, Site, SitePart, Spot, Structure, Tile, Turn;
import plugins.api.api : ApiRhythm = Rhythm;

enum uint NO_RECORD = uint.max;
enum double PAINT_AHEAD_MILLISECONDS = 2.0;
enum double INITIAL_MS_PER_TASK = PAINT_AHEAD_MILLISECONDS / 256;
enum double TILE_TASK_LEAST = 64;
enum double TILE_TASK_MOST = 4096;
enum uint PLAN_ROUNDS = 4;

struct TileCall {
    Tile tile;
    Array!ubyte data;
}

struct TileCalls {
    TileCall root;
    TileCall edge;
    Array!TileCall kinds;
    bool hasRoot;
    bool hasEdge;

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
    int lowest = int.max;
    int highest = int.min;
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
    bool isEntrance;
}

struct StrokeOutput {
    Motion!double frame;
    double length;
    float startRadius;
    float endRadius;
    Material material;
    bool isLeafy;
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
    bool isFailed;
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
    bool isRestoring;

    void clear() {
        lines.clear();
        brushes.clear();
        touches.clear();
        stops.clear();
        strokes.clear();
        paths.clear();
        outputs.clear();
    }

    void begin(uint task, bool restoring) {
        known.clear();
        isRestoring = restoring;
        current = TileOutput(task, cast(uint) lines.length, 0, cast(uint) brushes.length, 0, cast(uint) touches.length, 0, cast(uint) stops.length, 0, cast(uint) strokes.length, 0, false);
    }

    void finish(bool isFailed) {
        current.lineCount = cast(uint) lines.length - current.lineStart;
        current.brushCount = cast(uint) brushes.length - current.brushStart;
        current.touchCount = cast(uint) touches.length - current.touchStart;
        current.stopCount = cast(uint) stops.length - current.stopStart;
        current.strokeCount = cast(uint) strokes.length - current.strokeStart;
        current.isFailed = isFailed;
        outputs.append(current);
    }

    SiteLine* lineOf(ref GraphView view, SiteFrame site) {
        uint index = 0;
        while (index < known.length && known.ptr[index].site != site) {
            index += 1;
        }
        if (index == known.length) {
            CanonicalSite canonical = view.canonicalOf(site);
            LineKey key = LineKey(view.idAt(canonical.line.node), canonical.line.lower, canonical.line.xSide, canonical.line.ySide);
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

    PaintResult paint(ref GraphView view, SiteFrame site, CellBox box, Rhythm rhythm, Material material, bool isIntoAirOnly) {
        SiteLine* found = lineOf(view, site);
        ubyte dimension = view.layout.dimension;
        CellBox canonical = canonicalBox(box, found.transform, dimension);
        int lowEdge = edgeOf(canonical.low[2], dimension);
        int highEdge = edgeOf(canonical.high[2], dimension);
        if (lowEdge == int.min || highEdge == int.max) {
            return PaintResult.endless;
        } else if (!isRestoring && !isAhead(view, *found, lowEdge, highEdge)) {
            return PaintResult.behind;
        } else {
            if (!isRestoring) {
                record(view, *found, lowEdge, highEdge);
            }
            brushes.append(BrushOutput(found.line, Brush(canonical, canonicalRhythm(rhythm, found.transform, dimension), 0, Paint(0, isIntoAirOnly)), material));
            return PaintResult.painted;
        }
    }

    bool isAhead(ref GraphView view, ref SiteLine found, int lowEdge, int highEdge) {
        if (found.open.contains(lowEdge, highEdge)) {
            return true;
        } else {
            LineSpec spec = lines.ptr[found.line].spec;
            SlotTouch edge = seedTouch(spec, found.line);
            bool isClear = true;
            int level = lowEdge;
            while (isClear && level <= highEdge) {
                edge = view.walkedTouch(edge, spec, level);
                foreach (around; view.aroundEdge(edge, spec)) {
                    isClear = isClear && !view.hasStructureAt(around.slot);
                }
                level += 1;
            }
            if (isClear) {
                found.open.include(lowEdge, highEdge);
            }
            return isClear;
        }
    }

    void record(ref GraphView view, ref SiteLine found, int lowEdge, int highEdge) {
        LineOutput* line = &lines.ptr[found.line];
        if (!found.touched.contains(lowEdge, highEdge)) {
            const(uint)* existing = view.blueprint.lineIndex.find(line.key);
            SlotTouch edge = seedTouch(line.spec, found.line);
            foreach (level; lowEdge .. highEdge + 1) {
                if (existing is null || !view.blueprint.isEdgeTouched(LineEdge(*existing, level))) {
                    edge = view.walkedTouch(edge, line.spec, level);
                    TouchOutput touched = TouchOutput(found.line, level);
                    foreach (index, around; view.aroundEdge(edge, line.spec)) {
                        touched.nodes[index] = view.idAt(around.slot);
                        touched.touches[index] = around.touch;
                    }
                    touches.append(touched);
                }
            }
            found.touched.include(lowEdge, highEdge);
        }
        line.lowest = lowerOf(line.lowest, lowEdge);
        line.highest = higherOf(line.highest, highEdge);
    }

    void stop(ref GraphView view, SiteFrame site, ColumnSpot spot, bool isEntrance) {
        if (!isRestoring) {
            uint pathStart = cast(uint) paths.length;
            uint start = view.pathTo(site.node, paths);
            stops.append(StopOutput(site, spot, start, pathStart, cast(uint) paths.length - pathStart, isEntrance));
        }
    }

    void stroke(ref GraphView view, PenFrame pen, double length, float startRadius, float endRadius, Material material, bool isLeafy) {
        uint pathStart = cast(uint) paths.length;
        uint start = view.pathTo(pen.node, paths);
        strokes.append(StrokeOutput(pen.frame, length, startRadius, endRadius, material, isLeafy, start, pathStart, cast(uint) paths.length - pathStart));
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
    uint horosphere;
    SiteFrame site;
    int segment;
    bool isEdge;
    bool isRestoring;
}

struct PlannedTile {
    TileKey key;
    uint start;
    uint pathStart;
    uint pathLength;
    uint horosphere;
    SiteFrame site;
    int segment;
    bool isEdge;
}

struct PlanResult {
    uint candidate;
    uint tileStart;
    uint tileCount;
    bool isBlocked;
}

struct MeasuredRise {
    uint horosphere;
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

    bool hasMeasure(uint horosphere) const {
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

bool isTiledBy(ref const Graph graph, ref const TileCalls calls, uint horosphere) {
    return callFor(graph, calls, horosphere).tile !is null;
}

const(TileCall)* callFor(ref const Graph graph, ref const TileCalls calls, uint horosphere) {
    ubyte kind = graph.horospheres.kindOf(horosphere);
    if (kind == NO_RISE) {
        return &calls.root;
    } else {
        return &calls.kinds.ptr[kind - 1];
    }
}

Risen risenOf(ref const Graph graph, uint horosphere, int segment) {
    if (horosphere == ROOT) {
        return Risen(Site.init, 0, 0, 0, 0, NO_KIND, segment);
    } else {
        const(Horosphere)* found = &graph.horospheres.horosphere(horosphere);
        return Risen(siteOf(found.foot), found.edges, found.ground, found.below, found.balance, graph.horospheres.tagOf(found.parent), segment);
    }
}

TileKey faceKey(ref GraphView view, uint face, Face label) {
    return TileKey(view.idAt(face), label);
}

TileKey segmentKey(ref GraphView view, SiteFrame site) {
    return TileKey(view.idAt(site.node), cast(ubyte)(FACE_COUNT + site.corner));
}

TileKey edgeKey(ref GraphView view, SiteFrame site) {
    return TileKey(view.idAt(site.node), cast(ubyte)(FACE_COUNT + CORNER_COUNT + site.corner * 3 + sideAxis(site.corner, site.zSide())));
}

struct TileHost {
    TilePainter painter;
    PlanOutputs plan;
    GraphView* view;
    const(TileCalls)* calls;
    Api api;
    SplitMix random;
    const(char)* refusal;
    uint horosphere;
    bool isTaskFailed;
    bool hasFailed;
    char[MESSAGE_CAPACITY] failure;

    void fail(const(char)* message) {
        isTaskFailed = true;
        if (!hasFailed) {
            hasFailed = true;
            size_t length = lowerOf(strlen(message), failure.length - 1);
            memcpy(failure.ptr, message, length);
            failure[length] = 0;
        }
    }

    void refuse(const(char)* message) {
        if (refusal is null) {
            refusal = message;
        }
    }

    void takeRefusal() {
        if (refusal !is null) {
            fail(refusal);
            refusal = null;
        }
    }

    ubyte dimension() const {
        return view.layout.dimension;
    }

    Column column() const {
        return Column(-cast(int) dimension(), dimension() - 1);
    }

    double cellLength() const {
        return edgeLength(view.layout).value / edgeCells(dimension());
    }

    void run(ref const Graph graph, GraphView* threadView, ref const TileTask task, const(Face)[] path, uint index) {
        view = threadView;
        uint node = task.start;
        foreach (side; path) {
            node = view.ensureNeighborSlot(node, side);
        }
        painter.begin(index, task.isRestoring);
        random = SplitMix(task.key.node.spice() ^ task.key.feature);
        horosphere = task.horosphere;
        isTaskFailed = false;
        const(TileCall)* call = &calls.edge;
        if (!task.isEdge) {
            call = callFor(graph, *calls, task.horosphere);
        }
        Risen risen = risenOf(graph, task.horosphere, task.segment);
        SiteFrame site = task.site;
        site.node = node;
        call.tile(&api, siteOf(site), &risen, call.data.ptr);
        takeRefusal();
        painter.finish(isTaskFailed);
    }

    void paint(Site site, Material material, Box area, ApiRhythm rhythm, bool isIntoAirOnly) {
        const(char)* wrong = boxRefusal(area, rhythm, column());
        if (wrong !is null) {
            refuse(wrong);
        } else {
            PaintResult result = painter.paint(*view, frameOf(site), CellBox(area.low, area.high), engineRhythm(rhythm), material, isIntoAirOnly);
            if (result == PaintResult.endless) {
                refuse("a placed structure paints bounded heights: give the box a z range");
            } else if (result == PaintResult.behind) {
                refuse("paints ground that is already built: a tile paints only near its face");
            }
        }
    }

    void stop(Site site, Spot spot, bool isEntrance) {
        painter.stop(*view, frameOf(site), ColumnSpot(spot.x, spot.y, spot.z), isEntrance);
    }

    PenFrame penAt(Site site) {
        SiteFrame frame = frameOf(site);
        return PenFrame(sitePlacement(frame, view.layout).as!double(), unitNormal((*view).planeOfHorosphereIn(horosphere, frame.node)), frame.node);
    }

    void draw(Pen pen, double cells, double fromRadius, double toRadius, Material material, bool isLeafy) {
        if (!(cells >= 0) || !(fromRadius > 0) || !(toRadius > 0)) {
            refuse("a pen draws a length of at least zero with radii above zero");
        } else {
            double cell = cellLength();
            painter.stroke(*view, PenFrame.fromPen(pen), cells * cell, cast(float)(fromRadius * cell), cast(float)(toRadius * cell), material, isLeafy);
        }
    }

    uint rising(Site site) {
        SiteFrame at = (*view).atLevel(frameOf(site), 0);
        Rise rise = (*view).riseAt(at.node, at.corner, horosphere);
        if (rise.kind == NO_RISE) {
            return NO_KIND;
        } else {
            return view.horospheres.kinds.ptr[rise.kind - 1].tag;
        }
    }

    void planCandidate(ref const Graph graph, GraphView* threadView, uint candidate, uint index) {
        view = threadView;
        uint tileStart = cast(uint) plan.tiles.length;
        if (!graph.isFinished(candidate)) {
            if (isTiledBy(graph, *calls, ROOT)) {
                planRing(graph, (*view).groundRing((*view).groundNodeOf(candidate, ROOT), Face.f0), Face.f0, ROOT);
            }
            foreach (near; (*view).ensureHorospheresAt(candidate)) {
                bool wanted = !view.isBlocked && isTiledBy(graph, *calls, near.horosphere);
                if (wanted && view.horospheres.isUpright(near.horosphere)) {
                    planSegments(graph, near);
                } else if (wanted && (*view).isPaintedBy(candidate, near)) {
                    Face label = graph.horospheres.horosphere(near.horosphere).label;
                    planRing(graph, (*view).groundRing((*view).groundNodeOf(candidate, near.horosphere), label), label, near.horosphere);
                }
            }
            if (calls.hasEdge) {
                foreach (site; (*view).edgeSitesOf(candidate)) {
                    planTile(graph, (*view).edgeKey(site), site, ROOT, 0, true);
                }
            }
        }
        if (view.isBlocked) {
            plan.tiles.length = tileStart;
            plan.results.append(PlanResult(index, tileStart, 0, true));
            view.forget();
        } else {
            plan.results.append(PlanResult(index, tileStart, cast(uint) plan.tiles.length - tileStart, false));
            measureRises(graph, tileStart);
        }
    }

    void measureRises(ref const Graph graph, uint tileStart) {
        foreach (index; tileStart .. plan.tiles.length) {
            uint over = plan.tiles.ptr[index].horosphere;
            if (over != ROOT && !graph.horospheres.horosphere(over).isMeasured && !plan.hasMeasure(over)) {
                RiseMeasure measure = (*view).measureOf(over);
                if (view.isBlocked) {
                    view.forget();
                } else {
                    plan.measures.append(MeasuredRise(over, measure));
                }
            }
        }
    }

    void planTile(ref const Graph graph, TileKey key, SiteFrame site, uint over, int segment, bool isEdge) {
        const(uint)* known = graph.structures.tiledFaces.find(key);
        if (known !is null) {
            plan.usedRecords.append(*known);
        }
        if (known is null || graph.structures.blueprint.tiles.ptr[*known].isDropped) {
            uint pathStart = cast(uint) plan.paths.length;
            uint start = view.pathTo(site.node, plan.paths);
            plan.tiles.append(PlannedTile(key, start, pathStart, cast(uint) plan.paths.length - pathStart, over, site, segment, isEdge));
        }
    }

    void planRing(ref const Graph graph, uint[GROUND_RING] ring, Face label, uint over) {
        foreach (face; ring) {
            planTile(graph, (*view).faceKey(face, label), faceSite(face, label), over, 0, false);
        }
    }

    void planSegments(ref const Graph graph, ref const HorosphereRef near) {
        int[2] segments = (*view).segmentsNear(near);
        foreach (segment; segments[0] .. segments[1] + 1) {
            SiteFrame site = (*view).segmentSite(near.horosphere, segment);
            planTile(graph, (*view).segmentKey(site), site, near.horosphere, segment, false);
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
    api.failure = &tileFailure;
    api.fail = &tileFail;
    api.forward = &tileForward;
    api.turned = &tileTurned;
    api.column = &tileColumn;
    api.edgeCells = &tileEdgeCells;
    api.pick = &tilePick;
    api.random = &tileRandom;
    api.hash = &tileHash;
    api.paint = &tilePaint;
    api.fill = &tileFill;
    api.stop = &tileStop;
    api.entrance = &tileEntrance;
    api.place = &tilePlace;
    api.claim = &tileClaim;
    api.isClaimed = &tileIsClaimed;
    api.tile = &tileTile;
    api.tileEdges = &tileTileEdges;
    api.horosphere = &tileHorosphere;
    api.openHorosphere = &tileOpenHorosphere;
    api.rooted = &tileRooted;
    api.invertGravity = &tileInvertGravity;
    api.fog = &tileFog;
    api.rising = &tileRising;
    api.balance = &tileBalance;
    api.pen = &tilePen;
    api.penForward = &tilePenForward;
    api.penTurn = &tilePenTurn;
    api.penRoll = &tilePenRoll;
    api.penLift = &tilePenLift;
    api.penRise = &tilePenRise;
    api.penHeight = &tilePenHeight;
    api.limb = &tileLimb;
    api.leaves = &tileLeaves;
    api.build = &tileBuild;
    api.look = &tileLook;
    api.risingKinds = &tileRisingKinds;
    api.landmark = &tileLandmark;
    return api;
}

const(char)* tileFailure(const(Api)* api) {
    TileHost* host = tileHost(api);
    const(char)* refusal = host.refusal;
    host.refusal = null;
    return refusal;
}

void tileFail(const(Api)* api, const(char)* message) {
    tileHost(api).refuse(message);
}

Site tileForward(const(Api)* api, Site site, int edges) {
    return siteOf(forwarded(frameOf(site), edges));
}

Site tileTurned(const(Api)* api, Site site, Turn turn) {
    return siteOf((*tileHost(api).view).turned(frameOf(site), turn));
}

Column tileColumn(const(Api)* api) {
    return tileHost(api).column();
}

int tileEdgeCells(const(Api)* api) {
    return edgeCells(tileHost(api).dimension());
}

uint tilePick(const(Api)* api, uint count) {
    return cast(uint)(tileHost(api).random.next() % count);
}

double tileRandom(const(Api)* api) {
    return tileHost(api).random.unit();
}

ulong tileHash(const(Api)* api, Site site, SitePart part) {
    return (*tileHost(api).view).siteHash(frameOf(site), part);
}

void tilePaint(const(Api)* api, Site site, Material material, Box area, ApiRhythm rhythm) {
    tileHost(api).paint(site, material, area, rhythm, false);
}

void tileFill(const(Api)* api, Site site, Material material, Box area, ApiRhythm rhythm) {
    tileHost(api).paint(site, material, area, rhythm, true);
}

void tileStop(const(Api)* api, Site site, Spot spot) {
    tileHost(api).stop(site, spot, false);
}

void tileEntrance(const(Api)* api, Site site, Spot spot) {
    tileHost(api).stop(site, spot, true);
}

bool tilePlace(const(Api)* api, Site site, Structure structure, const(void)* data, size_t size) {
    tileHost(api).refuse("a tile cannot place: tiles run in any order, so decide from site:hash");
    return true;
}

bool tileClaim(const(Api)* api, Site site, SitePart part) {
    tileHost(api).refuse("a tile cannot claim: tiles run in any order, so decide from site:hash");
    return true;
}

bool tileIsClaimed(const(Api)* api, Site site, SitePart part) {
    tileHost(api).refuse("a tile cannot read claims: tiles run in any order, so decide from site:hash");
    return false;
}

void tileTile(const(Api)* api, Tile tile, const(void)* data, size_t size) {
    tileHost(api).refuse("only the world's own structure tiles the ground, and only once");
}

uint tileHorosphere(const(Api)* api, double odds, HorosphereForm form, uint tag, Tile tile, const(void)* data, size_t size) {
    tileHost(api).refuse("only the world's own structure gives horospheres their kinds");
    return 0;
}

void tileOpenHorosphere(const(Api)* api, Site site, uint kind, uint edges) {
    tileHost(api).refuse("only the world's own structure opens horospheres");
}

void tileRooted(const(Api)* api, uint kind) {
    tileHost(api).refuse("only the world's own structure gives the root its kind");
}

void tileTileEdges(const(Api)* api, Tile tile, const(void)* data, size_t size) {
    tileHost(api).refuse("only the world's own structure tiles the edges, and only once");
}

void tileInvertGravity(const(Api)* api) {
    tileHost(api).refuse("only the world's own structure turns gravity around");
}

void tileFog(const(Api)* api, double units) {
    tileHost(api).refuse("only the world's own structure sets the fog");
}

uint tileRising(const(Api)* api, Site site) {
    return tileHost(api).rising(site);
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
        return (*host.view).balanceAlong((*host.view).turned(frameOf(site), Turn.pitchUp), host.horosphere, most);
    }
}

Pen tilePen(const(Api)* api, Site site) {
    return tileHost(api).penAt(site).toPen();
}

Pen tilePenForward(const(Api)* api, Pen pen, double cells) {
    return PenFrame.fromPen(pen).moved(cells * tileHost(api).cellLength()).toPen();
}

Pen tilePenTurn(const(Api)* api, Pen pen, double yaw, double pitch) {
    return PenFrame.fromPen(pen).turned(axisOf(AHEAD), axisOf(ACROSS), yaw).turned(axisOf(AHEAD), axisOf(UP), pitch).toPen();
}

Pen tilePenRoll(const(Api)* api, Pen pen, double degrees) {
    return PenFrame.fromPen(pen).turned(axisOf(ACROSS), axisOf(UP), degrees).toPen();
}

Pen tilePenLift(const(Api)* api, Pen pen, double degrees) {
    return PenFrame.fromPen(pen).lifted(degrees).toPen();
}

double tilePenRise(const(Api)* api, Pen pen) {
    return asin(PenFrame.fromPen(pen).up()[AHEAD]) / RADIANS_PER_DEGREE;
}

double tilePenHeight(const(Api)* api, Pen pen) {
    PenFrame frame = PenFrame.fromPen(pen);
    return asinh(frame.ground.minkowski(frame.frame.m.column(3))) / tileHost(api).cellLength();
}

void tileLimb(const(Api)* api, Pen pen, Material material, double cells, double fromRadius, double toRadius) {
    tileHost(api).draw(pen, cells, fromRadius, toRadius, material, false);
}

void tileLeaves(const(Api)* api, Pen pen, Material material, double radius) {
    tileHost(api).draw(pen, 0, radius, radius, material, true);
}

bool tileBuild(const(Api)* api, const(char)* world, Site site) {
    Structure found = worldNamed(world);
    if (found is null) {
        tileHost(api).refuse("builds a world no plugin has");
        return false;
    } else {
        found(api, site, null);
        return true;
    }
}

void tileLook(const(Api)* api, uint kind, const(Look)* look) {
    tileHost(api).refuse("only the world's own structure sets how it looks");
}

void tileRisingKinds(const(Api)* api, double odds) {
    tileHost(api).refuse("only the world's own structure gives horospheres their kinds");
}

bool tileLandmark(const(Api)* api, uint index, Site site) {
    tileHost(api).refuse("a tile cannot place: tiles run in any order, so decide from site:hash");
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
    bool hasFailed;
    char[MESSAGE_CAPACITY] failure;

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
        bool isMade = true;
        uint round = 0;
        while (!hasFailed && planning.length > 0 && isMade && round < PLAN_ROUNDS && tasks.length < budget) {
            isMade = planCandidates(target, executor);
            blocked.clear();
            size_t index = 0;
            while (index < planning.length && tasks.length < budget) {
                const(TileHost)* host = hosts.ptr[outputOf.ptr[index].host];
                PlanResult result = host.plan.results.ptr[outputOf.ptr[index].output];
                if (result.isBlocked) {
                    blocked.append(planning.ptr[index]);
                } else {
                    foreach (tile; host.plan.tiles.ptr[result.tileStart .. result.tileStart + result.tileCount]) {
                        addTask(target, tile.key, tile.start, host.plan.paths.ptr[tile.pathStart .. tile.pathStart + tile.pathLength], tile.horosphere, tile.site, tile.segment, tile.isEdge);
                    }
                    covered.append(planning.ptr[index]);
                }
                index += 1;
            }
            planning.clear();
            planning.appendAll(blocked.slice());
            round += 1;
        }
        size_t painted = tasks.length;
        preparedTiles += cast(uint) painted;
        if (runTasks(target, executor)) {
            foreach (slot; covered.slice()) {
                target.structures.at(slot).isCovered = true;
            }
        }
        if (painted >= TILE_TASK_LEAST) {
            msPerTask = (nowMilliseconds() - start) / painted;
        }
    }

    bool planCandidates(ref Graph target, Executor executor) {
        foreach (host; hosts.slice()) {
            host.plan.clear();
        }
        target.threadViews.begin(target, executor.workers);
        TileJob context = TileJob(&target, hosts.ptr, null, null, planning.ptr);
        ParallelJob job = ParallelJob(&planCandidateTask, &context, double.infinity, planning.length);
        executor.run(&job);
        bool isMade = target.threadViews.finish(target);
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
        return isMade;
    }

    void takeFailure(const(TileHost)* host) {
        hasFailed = true;
        failure = host.failure;
    }

    void clearTasks() {
        tasks.clear();
        paths.clear();
        taskOf.clear();
    }

    void addTask(ref Graph target, TileKey key, uint start, const(Face)[] path, uint horosphere, SiteFrame site, int segment, bool isEdge) {
        if (taskOf.find(key) is null) {
            const(uint)* known = target.structures.tiledFaces.find(key);
            uint record = NO_RECORD;
            bool isRestoring = false;
            if (known is null) {
                record = target.structures.blueprint.addTile(key.node, key.feature, horosphere);
                target.structures.tiledFaces.insert(key, record);
            } else if (target.structures.blueprint.tiles.ptr[*known].isDropped) {
                record = *known;
                target.structures.blueprint.tiles.ptr[record].horosphere = horosphere;
                isRestoring = true;
            }
            if (record != NO_RECORD) {
                if (horosphere != ROOT) {
                    target.horospheres.horospheres.ptr[horosphere - 1].tiles += 1;
                    target.measuredHorosphere(horosphere);
                }
                taskOf.insert(key, cast(uint) tasks.length);
                tasks.append(TileTask(key, start, cast(uint) paths.length, cast(uint) path.length, record, horosphere, site, segment, isEdge, isRestoring));
                paths.appendAll(path);
            }
        }
    }

    bool runTasks(ref Graph target, Executor executor) {
        ensureHosts(executor.workers);
        if (tasks.length > 0 && !hasFailed) {
            foreach (host; hosts.slice()) {
                host.painter.clear();
            }
            target.threadViews.begin(target, executor.workers);
            TileJob context = TileJob(&target, hosts.ptr, tasks.ptr, paths.ptr, null);
            ParallelJob job = ParallelJob(&runTileTask, &context, double.infinity, tasks.length);
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
                if (output.isFailed) {
                    takeFailure(host);
                } else {
                    apply(target, tasks.ptr[index], host.painter, output);
                }
                index += 1;
            }
        }
        clearTasks();
        return !hasFailed;
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
            spec.node = NO_SLOT;
            uint index = blueprint.lineOf(spec, line.key.node);
            LineSpec* stored = &blueprint.lines.ptr[index];
            stored.lowest = lowerOf(stored.lowest, line.lowest);
            stored.highest = higherOf(stored.highest, line.highest);
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
            brush.paint.material = blueprint.paintOf(made.material);
            blueprint.addBrush(task.record, lines[made.line - output.lineStart], brush);
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
        if (!task.isRestoring) {
            useEdges(blueprint, task.record, painted, lines, output.lineStart);
        }
        foreach (stop; painter.stops.ptr[output.stopStart .. output.stopStart + output.stopCount]) {
            uint slot = slotAlong(target, painter, stop.start, stop.pathStart, stop.pathLength);
            SiteFrame site = stop.site;
            site.node = slot;
            if (!stop.isEntrance) {
                blueprint.route.append(RouteStop(site, stop.spot));
                target.reference(slot);
            } else if (!blueprint.hasEntrance) {
                blueprint.entrance = RouteStop(site, stop.spot);
                blueprint.hasEntrance = true;
                target.reference(slot);
            }
        }
        foreach (drawn; painter.strokes.ptr[output.strokeStart .. output.strokeStart + output.strokeCount]) {
            uint slot = slotAlong(target, painter, drawn.start, drawn.pathStart, drawn.pathLength);
            target.structures.addStroke(target.view, task.record, slot, Stroke.make(drawn.frame, drawn.length, drawn.startRadius, drawn.endRadius, drawn.material, drawn.isLeafy));
        }
        blueprint.reviveTile(task.record);
        blueprint.useTile(task.record);
        if (task.isRestoring) {
            blueprint.restoredTiles += 1;
        }
    }

    void useEdges(Blueprint* blueprint, uint tile, const(BrushOutput)[] painted, const(uint)[] lines, uint lineStart) {
        Array!TileEdge* edges = &blueprint.tiles.ptr[tile].edges;
        foreach (ref made; painted) {
            uint line = lines[made.line - lineStart];
            foreach (level; edgeOf(made.brush.box.low[2], blueprint.dimension) .. edgeOf(made.brush.box.high[2], blueprint.dimension) + 1) {
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
