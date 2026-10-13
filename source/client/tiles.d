module client.tiles;

import core.stdc.stdlib : calloc, free;
import core.stdc.string : memcpy, strlen;
import client.structures : MESSAGE_CAPACITY, RANDOM_DISCARDED_BITS, RANDOM_UNIT, boxRefusal, engineRhythm, worldNamed;
import base.array : Array;
import base.hashmap : HashMap;
import base.numbers : higherOf, lowerOf;
import base.parallel : Executor, ParallelJob;
import common.graph : Graph, NO_SLOT, NodeId;
import common.view : GraphView;
import common.worldgen.blueprint : Blueprint, Brush, CellBox, LevelRange, LineEdge, LineKey, LineSpec, Paint, PaintResult, Rhythm, RouteStop, TileRecord, canonicalBox, canonicalRhythm, edgeOf;
import common.worldgen.generation : SplitMix;
import common.worldgen.sky : PLANET, SkyMeasure, World, balanceAlong, ensureWorldsAt, isPaintedBySky, measureOf, measuredWorld, storeMeasure, worldGroundNodeOf;
import common.worldgen.structure : CanonicalSite, ColumnSpot, EDGE_NODES, GROUND_RING, LineTouch, LineTransform, SiteFrame, SlotTouch, addPendingTouch, aroundEdge, canonicalOf, edgeCells, faceSite, forwarded, frameOf, groundRing, seedTouch, siteHash, siteOf, turned, walkedTouch;
import geometry.honeycomb : Face;
import plugins.api.api : Api, Box, Column, Material, Pen, Site, SitePart, Sky, SkyGround, Spot, Structure, Tile, Turn;
import plugins.api.api : ApiRhythm = Rhythm;

enum uint NO_RECORD = uint.max;
enum size_t TILE_TASK_BUDGET = 256;
enum uint PLAN_ROUNDS = 4;

struct TileCall {
    Tile tile;
    Array!ubyte data;
}

struct TileCalls {
    TileCall planet;
    Array!TileCall skies;
    bool hasPlanet;

    void release() {
        planet.data.release();
        foreach (ref call; skies.slice()) {
            call.data.release();
        }
        skies.release();
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
    bool isFailed;
}

struct TileLine {
    SiteFrame site;
    LineTransform transform;
    uint line;
    LevelRange open;
    LevelRange touched;
}

struct TilePainter {
    Array!TileLine known;
    Array!LineOutput lines;
    Array!BrushOutput brushes;
    Array!TouchOutput touches;
    Array!StopOutput stops;
    Array!Face paths;
    Array!TileOutput outputs;
    TileOutput current;
    bool isRestoring;

    void clear() {
        lines.clear();
        brushes.clear();
        touches.clear();
        stops.clear();
        paths.clear();
        outputs.clear();
    }

    void begin(uint task, bool restoring) {
        known.clear();
        isRestoring = restoring;
        current = TileOutput(task, cast(uint) lines.length, 0, cast(uint) brushes.length, 0, cast(uint) touches.length, 0, cast(uint) stops.length, 0, false);
    }

    void finish(bool isFailed) {
        current.lineCount = cast(uint) lines.length - current.lineStart;
        current.brushCount = cast(uint) brushes.length - current.brushStart;
        current.touchCount = cast(uint) touches.length - current.touchStart;
        current.stopCount = cast(uint) stops.length - current.stopStart;
        current.isFailed = isFailed;
        outputs.append(current);
    }

    TileLine* lineOf(ref GraphView view, SiteFrame site) {
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
            known.append(TileLine(site, canonical.transform, line));
        }
        return &known.ptr[index];
    }

    PaintResult paint(ref GraphView view, SiteFrame site, CellBox box, Rhythm rhythm, Material material, bool isIntoAirOnly) {
        TileLine* found = lineOf(view, site);
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

    bool isAhead(ref GraphView view, ref TileLine found, int lowEdge, int highEdge) {
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

    void record(ref GraphView view, ref TileLine found, int lowEdge, int highEdge) {
        LineOutput* line = &lines.ptr[found.line];
        if (!found.touched.contains(lowEdge, highEdge)) {
            const(uint)* existing = view.blueprint.lineIndex.find(line.key);
            SlotTouch edge = seedTouch(line.spec, found.line);
            foreach (level; lowEdge .. highEdge + 1) {
                if (existing is null || view.blueprint.touchedEdges.find(LineEdge(*existing, level)) is null) {
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

    void release() {
        known.release();
        lines.release();
        brushes.release();
        touches.release();
        stops.release();
        paths.release();
        outputs.release();
    }
}

struct TileTask {
    NodeId face;
    uint start;
    uint pathStart;
    uint pathLength;
    uint record;
    uint sky;
    Face label;
    bool isRestoring;
}

struct PlannedFace {
    NodeId face;
    uint start;
    uint pathStart;
    uint pathLength;
    uint sky;
    Face label;
}

struct PlanResult {
    uint candidate;
    uint faceStart;
    uint faceCount;
    bool isBlocked;
}

struct MeasuredSky {
    uint sky;
    SkyMeasure measure;
}

struct PlanOutputs {
    Array!PlannedFace faces;
    Array!Face paths;
    Array!PlanResult results;
    Array!uint usedRecords;
    Array!MeasuredSky measures;

    void clear() {
        faces.clear();
        paths.clear();
        results.clear();
        usedRecords.clear();
        measures.clear();
    }

    bool hasMeasure(uint sky) const {
        uint index = 0;
        while (index < measures.length && measures.ptr[index].sky != sky) {
            index += 1;
        }
        return index < measures.length;
    }

    void release() {
        faces.release();
        paths.release();
        results.release();
        usedRecords.release();
        measures.release();
    }
}

struct TileHost {
    TilePainter painter;
    PlanOutputs plan;
    GraphView* view;
    const(TileCalls)* calls;
    Api api;
    SplitMix random;
    const(char)* refusal;
    uint sky;
    bool isTaskFailed;
    bool hasFailed;
    char[MESSAGE_CAPACITY] failure;

    void fail(const(char)* message) {
        isTaskFailed = true;
        if (!hasFailed) {
            hasFailed = true;
            size_t length = strlen(message);
            if (length >= failure.length) {
                length = failure.length - 1;
            }
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

    void run(ref const Graph graph, GraphView* threadView, ref const TileTask task, const(Face)[] path, uint index) {
        view = threadView;
        uint face = task.start;
        foreach (side; path) {
            face = view.ensureNeighborSlot(face, side);
        }
        painter.begin(index, task.isRestoring);
        random = SplitMix(task.face.spice());
        sky = task.sky;
        isTaskFailed = false;
        const(TileCall)* call = &calls.planet;
        Sky over;
        const(Sky)* skyOver = null;
        if (task.sky != PLANET) {
            const(World)* world = &graph.skies.world(task.sky);
            call = &calls.skies.ptr[world.kind];
            over = Sky(siteOf(world.foot), world.edges, world.ground, world.below, world.balance);
            skyOver = &over;
        }
        call.tile(&api, siteOf(faceSite(face, task.label)), skyOver, call.data.ptr);
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

    void planCandidate(ref const Graph graph, GraphView* threadView, uint candidate, uint index) {
        view = threadView;
        uint faceStart = cast(uint) plan.faces.length;
        if (!graph.isFinished(candidate)) {
            if (calls.hasPlanet) {
                planRing(graph, (*view).groundRing((*view).worldGroundNodeOf(candidate, PLANET), Face.f0), Face.f0, PLANET);
            }
            foreach (near; (*view).ensureWorldsAt(candidate)) {
                if (!view.isBlocked && (*view).isPaintedBySky(candidate, near)) {
                    Face label = graph.skies.world(near.world).label;
                    planRing(graph, (*view).groundRing((*view).worldGroundNodeOf(candidate, near.world), label), label, near.world);
                }
            }
        }
        if (view.isBlocked) {
            plan.faces.length = faceStart;
            plan.results.append(PlanResult(index, faceStart, 0, true));
            view.forget();
        } else {
            plan.results.append(PlanResult(index, faceStart, cast(uint) plan.faces.length - faceStart, false));
            measureSkies(graph, faceStart);
        }
    }

    void measureSkies(ref const Graph graph, uint faceStart) {
        foreach (index; faceStart .. plan.faces.length) {
            uint over = plan.faces.ptr[index].sky;
            if (over != PLANET && !graph.skies.world(over).isMeasured && !plan.hasMeasure(over)) {
                SkyMeasure measure = (*view).measureOf(over);
                if (view.isBlocked) {
                    view.forget();
                } else {
                    plan.measures.append(MeasuredSky(over, measure));
                }
            }
        }
    }

    void planRing(ref const Graph graph, uint[GROUND_RING] ring, Face label, uint world) {
        foreach (face; ring) {
            NodeId id = view.idAt(face);
            const(uint)* known = graph.structures.tiledFaces.find(id);
            if (known !is null) {
                plan.usedRecords.append(*known);
            }
            if (known is null || graph.structures.blueprint.tiles.ptr[*known].isDropped) {
                uint pathStart = cast(uint) plan.paths.length;
                uint start = view.pathTo(face, plan.paths);
                plan.faces.append(PlannedFace(id, start, pathStart, cast(uint) plan.paths.length - pathStart, world, label));
            }
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
    api.sky = &tileSky;
    api.openSky = &tileOpenSky;
    api.balance = &tileBalance;
    api.pen = &tilePen;
    api.penForward = &tilePenMoved;
    api.penTurn = &tilePenTurn;
    api.penRoll = &tilePenTurned;
    api.penLift = &tilePenTurned;
    api.penRise = &tilePenMeasure;
    api.penHeight = &tilePenMeasure;
    api.limb = &tileLimb;
    api.leaves = &tileLeaves;
    api.build = &tileBuild;
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
    return (tileHost(api).random.next() >> RANDOM_DISCARDED_BITS) * RANDOM_UNIT;
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

uint tileSky(const(Api)* api, double odds, SkyGround ground, Tile tile, const(void)* data, size_t size) {
    tileHost(api).refuse("only the world's own structure opens skies");
    return 0;
}

void tileOpenSky(const(Api)* api, Site site, uint kind, uint edges) {
    tileHost(api).refuse("only the world's own structure opens skies");
}

int tileBalance(const(Api)* api, Site site, int most) {
    TileHost* host = tileHost(api);
    if (host.sky == PLANET) {
        host.refuse("only a sky's tiles have another world to balance against");
        return 0;
    } else if (most < 1) {
        host.refuse("balance looks at least one cell up");
        return 0;
    } else {
        return (*host.view).balanceAlong((*host.view).turned(frameOf(site), Turn.pitchUp), host.sky, most);
    }
}

Pen tilePen(const(Api)* api, Site site) {
    tileHost(api).refuse("only the world's own structure draws with a pen");
    return Pen.init;
}

Pen tilePenMoved(const(Api)* api, Pen pen, double amount) {
    return pen;
}

Pen tilePenTurn(const(Api)* api, Pen pen, double yaw, double pitch) {
    return pen;
}

Pen tilePenTurned(const(Api)* api, Pen pen, double degrees) {
    return pen;
}

double tilePenMeasure(const(Api)* api, Pen pen) {
    return 0;
}

void tileLimb(const(Api)* api, Pen pen, Material material, double cells, double fromRadius, double toRadius) {
    tileHost(api).refuse("only the world's own structure draws with a pen");
}

void tileLeaves(const(Api)* api, Pen pen, Material material, double radius) {
    tileHost(api).refuse("only the world's own structure draws with a pen");
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
    Array!uint covered;
    Array!uint planning;
    Array!uint blocked;
    HashMap!(NodeId, uint) taskOf;
    const(TileCalls)* calls;
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

    void paintAhead(ref Graph target, const(uint)[] candidates, Executor executor) {
        ensureHosts(executor.workers);
        covered.clear();
        planning.clear();
        planning.appendAll(candidates);
        bool isWorldMade = true;
        uint round = 0;
        while (!hasFailed && planning.length > 0 && isWorldMade && round < PLAN_ROUNDS && tasks.length < TILE_TASK_BUDGET) {
            isWorldMade = planCandidates(target, executor);
            blocked.clear();
            size_t index = 0;
            while (index < planning.length && tasks.length < TILE_TASK_BUDGET) {
                const(TileHost)* host = hosts.ptr[outputOf.ptr[index].host];
                PlanResult result = host.plan.results.ptr[outputOf.ptr[index].output];
                if (result.isBlocked) {
                    blocked.append(planning.ptr[index]);
                } else {
                    foreach (face; host.plan.faces.ptr[result.faceStart .. result.faceStart + result.faceCount]) {
                        addTask(target, face.face, face.start, host.plan.paths.ptr[face.pathStart .. face.pathStart + face.pathLength], face.label, face.sky);
                    }
                    covered.append(planning.ptr[index]);
                }
                index += 1;
            }
            planning.clear();
            planning.appendAll(blocked.slice());
            round += 1;
        }
        preparedTiles += cast(uint) tasks.length;
        if (runTasks(target, executor)) {
            foreach (slot; covered.slice()) {
                target.structures.at(slot).isCovered = true;
            }
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
        bool isWorldMade = target.threadViews.finish(target);
        outputOf.resize(planning.length);
        foreach (hostIndex, host; hosts.slice()) {
            foreach (record; host.plan.usedRecords.slice()) {
                target.structures.blueprint.tiles.ptr[record].lastUse = target.structures.blueprint.travel;
            }
            foreach (measured; host.plan.measures.slice()) {
                if (!target.skies.world(measured.sky).isMeasured) {
                    target.storeMeasure(measured.sky, measured.measure);
                }
            }
            foreach (resultIndex, result; host.plan.results.slice()) {
                outputOf.ptr[result.candidate] = TaskOutput(cast(uint) hostIndex, cast(uint) resultIndex);
            }
        }
        return isWorldMade;
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

    bool hasTask(NodeId face) const {
        return taskOf.find(face) !is null;
    }

    void addTask(ref Graph target, NodeId face, uint start, const(Face)[] path, Face label, uint sky) {
        if (taskOf.find(face) is null) {
            const(uint)* known = target.structures.tiledFaces.find(face);
            uint record = NO_RECORD;
            bool isRestoring = false;
            if (known is null) {
                record = target.structures.blueprint.addTile(face);
                target.structures.tiledFaces.insert(face, record);
                if (sky != PLANET) {
                    target.skies.worlds.ptr[sky - 1].isTiled = true;
                }
            } else if (target.structures.blueprint.tiles.ptr[*known].isDropped) {
                record = *known;
                isRestoring = true;
            }
            if (record != NO_RECORD) {
                if (sky != PLANET) {
                    target.measuredWorld(sky);
                }
                taskOf.insert(face, cast(uint) tasks.length);
                tasks.append(TileTask(face, start, cast(uint) paths.length, cast(uint) path.length, record, sky, label, isRestoring));
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
        uint first = blueprint.takeOrders(output.brushCount);
        blueprint.tiles.ptr[task.record].painted.brushes.reserve(output.brushCount);
        foreach (local; 0 .. output.lineCount) {
            foreach (index, made; painted) {
                if (made.line - output.lineStart == local) {
                    Brush brush = made.brush;
                    brush.order = first + cast(uint) index;
                    brush.paint.material = blueprint.paintOf(made.material);
                    blueprint.addBrush(task.record, lines[local], brush);
                }
            }
        }
        foreach (touched; painter.touches.ptr[output.touchStart .. output.touchStart + output.touchCount]) {
            uint line = lines[touched.line - output.lineStart];
            if (blueprint.touchedEdges.find(LineEdge(line, touched.level)) is null) {
                blueprint.touchedEdges.insert(LineEdge(line, touched.level), true);
                foreach (corner; 0 .. EDGE_NODES) {
                    LineTouch touch = touched.touches[corner];
                    touch.line = line;
                    target.addPendingTouch(touched.nodes[corner], touch);
                }
            }
        }
        foreach (stop; painter.stops.ptr[output.stopStart .. output.stopStart + output.stopCount]) {
            uint slot = stop.start;
            foreach (side; painter.paths.ptr[stop.pathStart .. stop.pathStart + stop.pathLength]) {
                slot = target.ensureNeighborSlot(slot, side);
            }
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
        TileRecord* record = &blueprint.tiles.ptr[task.record];
        record.lastUse = blueprint.travel;
        record.isDropped = false;
        if (task.isRestoring) {
            blueprint.restoredTiles += 1;
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
        covered.release();
        planning.release();
        blocked.release();
        taskOf.release();
    }
}
