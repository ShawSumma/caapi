module client.structures;

import core.stdc.math : asin, asinh, atan2, cos, cosh, sin, sinh, sqrt;
import core.stdc.stdio : snprintf;
import core.stdc.stdlib : free, malloc;
import core.stdc.string : memcpy, strlen;
import base.array : Array;
import base.numbers : RADIANS_PER_DEGREE, clamped, higherOf;
import base.parallel : Executor;
import base.splitmix : SplitMix;
import client.game : Game;
import client.plugins : registry;
import client.tiles : TileCall, TileCalls, TileWork, edgeKey, faceKey, isTiledBy, segmentKey;
import common.graph : Graph;
import common.worldgen.blueprint : BlueprintBuilder, CellBox, PLACED_RECORD, PaintResult, Rhythm;
import common.worldgen.generation : StructureWorld, Worldgen;
import common.worldgen.horospheres : HorosphereKind, HorosphereRef, Horospheres, LOWEST_RISE_EDGES, NO_RISE, ROOT, Rise, ensureHorospheresAt, groundNodeOf, isPaintedBy, openHorosphere, riseAt, segmentSite, segmentsNear;
import common.worldgen.plane : Plane;
import common.worldgen.store : Grower, TileKey;
import common.worldgen.strokes : Stroke;
import common.worldgen.structure : ClaimKey, ColumnSpot, GROUND_RING, PLACE_SLACK, RootedCorner, SiteFrame, anchorBits, atLevel, claimKeyOf, edgeCells, edgeLength, edgeSitesOf, faceSite, forwarded, frameOf, groundRing, rootSite, siteHash, siteOf, siteOrigin, sitePlacement, turned;
import geometry.honeycomb : Face;
import geometry.lorentz : Motion, Vec4;
import plugins.api.api : Api, Box, Column, HorosphereForm, Look, Material, NO_KIND, Pen, RisingKind, Site, SitePart, Spot, Structure, Tile, Turn;
import plugins.api.api : ApiRhythm = Rhythm;

enum size_t MESSAGE_CAPACITY = 1024;
enum double HALF_TURN = 3.141592653589793;
enum double VERTICAL_TOLERANCE = 1e-9;
enum size_t ACROSS = 0;
enum size_t UP = 1;
enum size_t AHEAD = 2;

struct StructureProblem {
    char[MESSAGE_CAPACITY] text;
    bool isPresent;

    static StructureProblem fromMessage(const(char)[] name, const(char)* message) {
        StructureProblem problem = StructureProblem(' ', true);
        snprintf(problem.text.ptr, problem.text.length, "structure %.*s: %s", cast(int) name.length, name.ptr, message);
        return problem;
    }
}

struct QueuedStructure {
    SiteFrame site;
    Array!uint held;
    Array!ubyte data;
    Structure structure;
    uint key;
}

struct PenFrame {
    Motion!double frame;
    Vec4!double ground;
    uint node;

    static PenFrame fromPen(Pen pen) {
        PenFrame made;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                made.frame.m.c[col][row] = pen.frame[col * 4 + row];
            }
        }
        made.ground = Vec4!double(pen.ground);
        made.node = pen.node;
        return made;
    }

    Pen toPen() const {
        Pen pen;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                pen.frame[col * 4 + row] = frame.m.c[col][row];
            }
        }
        pen.ground = ground.c;
        pen.node = node;
        return pen;
    }

    double[3] up() const {
        Vec4!double local = frame.inverse() * ground;
        double length = sqrt(local.c[0] * local.c[0] + local.c[1] * local.c[1] + local.c[2] * local.c[2]);
        return [local.c[0] / length, local.c[1] / length, local.c[2] / length];
    }

    PenFrame moved(double distance) const {
        return PenFrame((frame * Motion!double.shift([0, 0, distance])).orthonormalized(), ground, node);
    }

    PenFrame turned(double[3] from, double[3] toward, double degrees) const {
        return PenFrame(frame * planeRotation(from, toward, degrees * RADIANS_PER_DEGREE), ground, node);
    }

    PenFrame lifted(double degrees) const {
        double[3] rising = up();
        double side = sqrt(rising[0] * rising[0] + rising[1] * rising[1]);
        if (side < VERTICAL_TOLERANCE) {
            return this;
        } else {
            double toUp = atan2(side, rising[AHEAD]);
            double angle = clamped(degrees * RADIANS_PER_DEGREE, toUp - HALF_TURN, toUp);
            return PenFrame(frame * planeRotation(axisOf(AHEAD), [rising[0] / side, rising[1] / side, 0], angle), ground, node);
        }
    }
}

double[3] axisOf(size_t axis) {
    double[3] unit = [0, 0, 0];
    unit[axis] = 1;
    return unit;
}

Motion!double planeRotation(double[3] from, double[3] toward, double angle) {
    Motion!double rotation = Motion!double.identity();
    double turn = sin(angle);
    double shrink = cos(angle) - 1;
    foreach (col; 0 .. 3) {
        foreach (row; 0 .. 3) {
            rotation.m.c[col][row] += turn * (toward[row] * from[col] - from[row] * toward[col]) + shrink * (from[row] * from[col] + toward[row] * toward[col]);
        }
    }
    return rotation;
}

Vec4!double unitNormal(Plane plane) {
    double stretch = cosh(plane.height);
    return Vec4!double([plane.up[0] * stretch, plane.up[1] * stretch, plane.up[2] * stretch, -sinh(plane.height)]);
}

bool isWithin(Box area, Column column) {
    bool isInside = true;
    foreach (axis; 0 .. 2) {
        isInside = isInside && area.low[axis] >= column.low && area.high[axis] <= column.high;
    }
    return isInside;
}

bool isOrdered(Box area) {
    return area.low[0] <= area.high[0] && area.low[1] <= area.high[1] && area.low[2] <= area.high[2];
}

const(char)* boxRefusal(Box area, ApiRhythm rhythm, Column column) {
    if (!isOrdered(area)) {
        return "a box runs from high to low";
    } else if (!area.isWithin(column)) {
        return "a box leaves the site's column";
    } else if (rhythm.every < 0 || (rhythm.every > 0 && rhythm.span <= 0)) {
        return "a rhythm needs a positive every and span";
    } else {
        return null;
    }
}

Rhythm engineRhythm(ApiRhythm rhythm) {
    return Rhythm(rhythm.every, rhythm.from, rhythm.span);
}

Array!ubyte copied(const(void)* data, size_t size) {
    Array!ubyte bytes;
    bytes.resize(size);
    if (size > 0) {
        memcpy(bytes.ptr, data, size);
    }
    return bytes;
}

Structure worldNamed(const(char)* name) {
    return registry().find(name[0 .. strlen(name)]);
}

struct StructureHost {
    BlueprintBuilder builder;
    Array!(Array!QueuedStructure) queue;
    TileCalls calls;
    TileWork tiles;
    Executor executor;
    SplitMix random;
    Api api;
    const(char)* refusal;
    StructureWorld name;
    uint key;
    uint nextKey;
    StructureProblem problem;

    static StructureHost make(ref Graph graph) {
        StructureHost host;
        host.builder = BlueprintBuilder.make(graph);
        host.random = SplitMix(graph.anchorBits(graph.anchorSlot));
        host.name = StructureWorld.fromName(graph.worldgen.structureName());
        return host;
    }

    bool hasCover() const {
        uint tiled = 0;
        foreach (call; calls.kinds.slice()) {
            if (call.tile !is null) {
                tiled += 1;
            }
        }
        return calls.root.tile !is null || calls.edge.tile !is null || tiled > 0;
    }

    void build(SiteFrame root) {
        api = mainApi(&this);
        tiles.calls = &calls;
        Structure world = registry().find(name.name());
        if (world is null) {
            fail("no plugin has a world by this name");
        } else {
            world(&api, siteOf(root), null);
            takeRefusal();
        }
    }

    void fail(const(char)* message) {
        if (!problem.isPresent) {
            problem = StructureProblem.fromMessage(name.name(), message);
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

    void grow(ref Graph graph, int through) {
        builder.graph = &graph;
        while (!problem.isPresent && nextKey < queue.length && cast(int) nextKey <= through) {
            size_t index = 0;
            while (!problem.isPresent && index < queue.ptr[nextKey].length) {
                run(queue.ptr[nextKey].ptr[index]);
                index += 1;
            }
            if (!problem.isPresent) {
                queue.ptr[nextKey].release();
                nextKey += 1;
            }
        }
    }

    void run(ref QueuedStructure queued) {
        key = queued.key;
        builder.growFrom(queued.key);
        foreach (slot; queued.held.slice()) {
            builder.graph.unreference(slot);
        }
        queued.held.release();
        queued.structure(&api, siteOf(queued.site), queued.data.ptr);
        queued.data.release();
        takeRefusal();
    }

    void cover(ref Graph graph, uint slot) {
        builder.graph = &graph;
        if (!problem.isPresent && hasCover()) {
            if (isTiledBy(graph, calls, ROOT)) {
                coverRing(graph, graph.view.groundRing(graph.view.groundNodeOf(slot, ROOT), Face.f0), Face.f0, ROOT);
            }
            foreach (near; graph.view.ensureHorospheresAt(slot)) {
                if (!isTiledBy(graph, calls, near.horosphere)) {
                    continue;
                } else if (graph.horospheres.isUpright(near.horosphere)) {
                    coverSegments(graph, near);
                } else if (graph.view.isPaintedBy(slot, near)) {
                    Face label = graph.horospheres.horosphere(near.horosphere).label;
                    coverRing(graph, graph.view.groundRing(graph.view.groundNodeOf(slot, near.horosphere), label), label, near.horosphere);
                }
            }
            if (calls.hasEdge) {
                foreach (site; graph.view.edgeSitesOf(slot)) {
                    coverTile(graph, graph.view.edgeKey(site), site, ROOT, 0, true);
                }
            }
            runTiles(graph);
        }
    }

    void coverTile(ref Graph graph, TileKey key, SiteFrame site, uint over, int segment, bool isEdge) {
        const(uint)* known = graph.structures.tiledFaces.find(key);
        if (known !is null && !graph.structures.blueprint.tiles.ptr[*known].isDropped) {
            graph.structures.blueprint.useTile(*known);
        } else {
            tiles.addTask(graph, key, site.node, null, over, site, segment, isEdge);
        }
    }

    void coverRing(ref Graph graph, uint[GROUND_RING] ring, Face label, uint over) {
        foreach (face; ring) {
            coverTile(graph, graph.view.faceKey(face, label), faceSite(face, label), over, 0, false);
        }
    }

    void coverSegments(ref Graph graph, ref const HorosphereRef near) {
        int[2] segments = graph.view.segmentsNear(near);
        foreach (segment; segments[0] .. segments[1] + 1) {
            SiteFrame site = graph.view.segmentSite(near.horosphere, segment);
            coverTile(graph, graph.view.segmentKey(site), site, near.horosphere, segment, false);
        }
    }

    void runTiles(ref Graph graph) {
        tiles.fallbackTiles += cast(uint) tiles.tasks.length;
        if (!tiles.runTasks(graph, executor)) {
            fail(tiles.failure.ptr);
        }
    }

    void paintAhead(ref Graph graph, const(uint)[] candidates, Executor chosen) {
        executor = chosen;
        builder.graph = &graph;
        if (!problem.isPresent && hasCover()) {
            tiles.paintAhead(graph, candidates, executor);
            if (tiles.hasFailed) {
                fail(tiles.failure.ptr);
            }
        }
    }

    void enqueue(QueuedStructure queued) {
        while (queue.length <= queued.key) {
            queue.append(Array!QueuedStructure.init);
        }
        builder.graph.reference(queued.site.node);
        queued.held.append(queued.site.node);
        queue.ptr[queued.key].append(queued);
    }

    ubyte dimension() const {
        return builder.graph.layout.dimension;
    }

    Column column() const {
        return Column(-cast(int) dimension(), dimension() - 1);
    }

    double cellLength() const {
        return edgeLength(builder.graph.layout).value / edgeCells(dimension());
    }

    void paint(Site site, Material material, Box area, ApiRhythm rhythm, bool isIntoAirOnly) {
        const(char)* wrong = boxRefusal(area, rhythm, column());
        if (wrong !is null) {
            refuse(wrong);
        } else {
            PaintResult result = builder.paint(frameOf(site), CellBox(area.low, area.high), engineRhythm(rhythm), material, isIntoAirOnly);
            if (result == PaintResult.endless) {
                refuse("a placed structure paints bounded heights: give the box a z range");
            } else if (result == PaintResult.behind) {
                refuse("paints too far behind its site: a placed structure stays near where it was placed");
            }
        }
    }

    bool place(Site site, Structure structure, const(void)* data, size_t size) {
        SiteFrame frame = frameOf(site);
        RootedCorner origin = builder.graph.view.siteOrigin(frame);
        bool isAhead = cast(int) origin.depth + PLACE_SLACK >= cast(int) key;
        if (isAhead) {
            enqueue(QueuedStructure(frame, Array!uint.init, copied(data, size), structure, higherOf(origin.depth, key)));
        }
        return isAhead;
    }

    ClaimKey claimKey(Site site, SitePart part) {
        return builder.graph.view.claimKeyOf(frameOf(site), part);
    }

    bool claim(Site site, SitePart part) {
        if (part == SitePart.edge) {
            refuse("a site claims its vertex or face, not its edge");
            return false;
        } else {
            return builder.claim(claimKey(site, part));
        }
    }

    bool isClaimed(Site site, SitePart part) {
        if (part == SitePart.edge) {
            refuse("a site claims its vertex or face, not its edge");
            return false;
        } else {
            return builder.blueprint.isClaimed(claimKey(site, part));
        }
    }

    void tile(Tile tile, const(void)* data, size_t size) {
        if (builder.isGrowing || calls.hasRoot) {
            refuse("only the world's own structure tiles the ground, and only once");
        } else {
            calls.root = TileCall(tile, copied(data, size));
            calls.hasRoot = true;
        }
    }

    void tileEdges(Tile tile, const(void)* data, size_t size) {
        if (builder.isGrowing || calls.hasEdge) {
            refuse("only the world's own structure tiles the edges, and only once");
        } else {
            calls.edge = TileCall(tile, copied(data, size));
            calls.hasEdge = true;
        }
    }

    void invertGravity() {
        if (builder.isGrowing) {
            refuse("only the world's own structure turns gravity around");
        } else {
            builder.graph.horospheres.isGravityInverted = true;
        }
    }

    void fog(double units) {
        if (builder.isGrowing) {
            refuse("only the world's own structure sets the fog");
        } else if (!(units > 0)) {
            refuse("the fog closes in past a distance above zero");
        } else {
            builder.graph.structures.blueprint.fog = cast(float) units;
        }
    }

    uint horosphere(double odds, HorosphereForm form, uint tag, Tile tile, const(void)* data, size_t size) {
        Horospheres* horospheres = &builder.graph.horospheres;
        if (builder.isGrowing) {
            refuse("only the world's own structure gives horospheres their kinds");
            return 0;
        } else if (!(odds >= 0) || horospheres.totalOdds() + odds > 1) {
            refuse("horosphere odds are chances per vertex, and all kinds together add up to at most 1");
            return 0;
        } else if (horospheres.kinds.length == ubyte.max) {
            refuse("too many kinds of horosphere");
            return 0;
        } else {
            horospheres.kinds.append(HorosphereKind(odds, form, tag));
            calls.kinds.append(TileCall(tile, copied(data, size)));
            return cast(uint) horospheres.kinds.length;
        }
    }

    void look(uint kind, ref const Look chosen) {
        if (builder.isGrowing) {
            refuse("only the world's own structure sets how it looks");
        } else if (kind == NO_KIND) {
            builder.graph.structures.blueprint.look = chosen;
        } else if (!isKnownKind(kind)) {
            refuse("unknown kind of horosphere");
        } else {
            builder.graph.horospheres.kinds.ptr[kind - 1].look = chosen;
        }
    }

    void addRisingKinds(double odds) {
        foreach (ref kind; registry().risingKinds[0 .. registry().kindCount]) {
            uint made = horosphere(odds * kind.share, kind.form, kind.tag, kind.tile, kind.data, kind.size);
            if (refusal is null) {
                look(made, kind.look);
            }
        }
    }

    bool isKnownKind(uint kind) const {
        return kind >= 1 && kind <= builder.graph.horospheres.kinds.length;
    }

    void openHorosphereAt(Site site, uint kind, uint edges) {
        if (builder.isGrowing) {
            refuse("only the world's own structure opens horospheres");
        } else if (!isKnownKind(kind)) {
            refuse("unknown kind of horosphere");
        } else if (edges < LOWEST_RISE_EDGES || edges > ubyte.max) {
            refuse("a horosphere rises at least two edges");
        } else if (!(*builder.graph).openHorosphere(frameOf(site), Rise(cast(ubyte) kind, cast(ubyte) edges))) {
            refuse("a horosphere beside another one would cross it");
        }
    }

    void rooted(uint kind) {
        Horospheres* horospheres = &builder.graph.horospheres;
        if (builder.isGrowing || horospheres.rootKind != NO_RISE) {
            refuse("only the world's own structure gives the root its kind, and only once");
        } else if (!isKnownKind(kind)) {
            refuse("unknown kind of horosphere");
        } else if (horospheres.isUprightKind(cast(ubyte) kind)) {
            refuse("the root is a plane, so it cannot be an upright kind");
        } else {
            horospheres.rootKind = cast(ubyte) kind;
        }
    }

    uint rising(Site site) {
        Graph* graph = builder.graph;
        SiteFrame at = graph.view.atLevel(frameOf(site), 0);
        Rise rise = graph.view.riseAt(at.node, at.corner, ROOT);
        if (rise.kind == NO_RISE) {
            return NO_KIND;
        } else {
            return graph.horospheres.kinds.ptr[rise.kind - 1].tag;
        }
    }

    PenFrame penAt(Site site) {
        Graph* graph = builder.graph;
        SiteFrame frame = frameOf(site);
        return PenFrame(sitePlacement(frame, graph.layout).as!double(), unitNormal(graph.ensureState(frame.node).surface), frame.node);
    }

    void draw(Pen pen, double cells, double fromRadius, double toRadius, Material material, bool isLeafy) {
        if (builder.isGrowing) {
            refuse("only the world's own structure draws with a pen");
        } else if (!(cells >= 0) || !(fromRadius > 0) || !(toRadius > 0)) {
            refuse("a pen draws a length of at least zero with radii above zero");
        } else {
            Graph* graph = builder.graph;
            double cell = cellLength();
            PenFrame frame = PenFrame.fromPen(pen);
            graph.structures.addStroke(graph.view, PLACED_RECORD, frame.node, Stroke.make(frame.frame, cells * cell, cast(float)(fromRadius * cell), cast(float)(toRadius * cell), material, isLeafy));
        }
    }

    void release() {
        foreach (ref bucket; queue.slice()) {
            foreach (ref queued; bucket.slice()) {
                queued.held.release();
                queued.data.release();
            }
            bucket.release();
        }
        queue.release();
        calls.release();
        tiles.release();
        builder.release();
    }
}

StructureHost* mainHost(const(Api)* api) {
    return cast(StructureHost*) api.host;
}

Api mainApi(StructureHost* host) {
    Api api;
    api.host = host;
    api.failure = &mainFailure;
    api.fail = &mainFail;
    api.forward = &mainForward;
    api.turned = &mainTurned;
    api.column = &mainColumn;
    api.edgeCells = &mainEdgeCells;
    api.pick = &mainPick;
    api.random = &mainRandom;
    api.hash = &mainHash;
    api.paint = &mainPaint;
    api.fill = &mainFill;
    api.stop = &mainStop;
    api.entrance = &mainEntrance;
    api.place = &mainPlace;
    api.claim = &mainClaim;
    api.isClaimed = &mainIsClaimed;
    api.tile = &mainTile;
    api.tileEdges = &mainTileEdges;
    api.horosphere = &mainHorosphere;
    api.openHorosphere = &mainOpenHorosphere;
    api.rooted = &mainRooted;
    api.invertGravity = &mainInvertGravity;
    api.fog = &mainFog;
    api.rising = &mainRising;
    api.balance = &mainBalance;
    api.pen = &mainPen;
    api.penForward = &mainPenForward;
    api.penTurn = &mainPenTurn;
    api.penRoll = &mainPenRoll;
    api.penLift = &mainPenLift;
    api.penRise = &mainPenRise;
    api.penHeight = &mainPenHeight;
    api.limb = &mainLimb;
    api.leaves = &mainLeaves;
    api.build = &mainBuild;
    api.look = &mainLook;
    api.risingKinds = &mainRisingKinds;
    api.landmark = &mainLandmark;
    return api;
}

const(char)* mainFailure(const(Api)* api) {
    StructureHost* host = mainHost(api);
    const(char)* refusal = host.refusal;
    host.refusal = null;
    return refusal;
}

void mainFail(const(Api)* api, const(char)* message) {
    mainHost(api).refuse(message);
}

Site mainForward(const(Api)* api, Site site, int edges) {
    return siteOf(forwarded(frameOf(site), edges));
}

Site mainTurned(const(Api)* api, Site site, Turn turn) {
    return siteOf(mainHost(api).builder.graph.view.turned(frameOf(site), turn));
}

Column mainColumn(const(Api)* api) {
    return mainHost(api).column();
}

int mainEdgeCells(const(Api)* api) {
    return edgeCells(mainHost(api).dimension());
}

uint mainPick(const(Api)* api, uint count) {
    return cast(uint)(mainHost(api).random.next() % count);
}

double mainRandom(const(Api)* api) {
    return mainHost(api).random.unit();
}

ulong mainHash(const(Api)* api, Site site, SitePart part) {
    return mainHost(api).builder.graph.view.siteHash(frameOf(site), part);
}

void mainPaint(const(Api)* api, Site site, Material material, Box area, ApiRhythm rhythm) {
    mainHost(api).paint(site, material, area, rhythm, false);
}

void mainFill(const(Api)* api, Site site, Material material, Box area, ApiRhythm rhythm) {
    mainHost(api).paint(site, material, area, rhythm, true);
}

void mainStop(const(Api)* api, Site site, Spot spot) {
    mainHost(api).builder.stop(frameOf(site), ColumnSpot(spot.x, spot.y, spot.z));
}

void mainEntrance(const(Api)* api, Site site, Spot spot) {
    mainHost(api).builder.enter(frameOf(site), ColumnSpot(spot.x, spot.y, spot.z));
}

bool mainPlace(const(Api)* api, Site site, Structure structure, const(void)* data, size_t size) {
    return mainHost(api).place(site, structure, data, size);
}

bool mainClaim(const(Api)* api, Site site, SitePart part) {
    return mainHost(api).claim(site, part);
}

bool mainIsClaimed(const(Api)* api, Site site, SitePart part) {
    return mainHost(api).isClaimed(site, part);
}

void mainTile(const(Api)* api, Tile tile, const(void)* data, size_t size) {
    mainHost(api).tile(tile, data, size);
}

uint mainHorosphere(const(Api)* api, double odds, HorosphereForm form, uint tag, Tile tile, const(void)* data, size_t size) {
    return mainHost(api).horosphere(odds, form, tag, tile, data, size);
}

void mainOpenHorosphere(const(Api)* api, Site site, uint kind, uint edges) {
    mainHost(api).openHorosphereAt(site, kind, edges);
}

void mainRooted(const(Api)* api, uint kind) {
    mainHost(api).rooted(kind);
}

void mainTileEdges(const(Api)* api, Tile tile, const(void)* data, size_t size) {
    mainHost(api).tileEdges(tile, data, size);
}

void mainInvertGravity(const(Api)* api) {
    mainHost(api).invertGravity();
}

void mainFog(const(Api)* api, double units) {
    mainHost(api).fog(units);
}

uint mainRising(const(Api)* api, Site site) {
    return mainHost(api).rising(site);
}

int mainBalance(const(Api)* api, Site site, int most) {
    mainHost(api).refuse("only a horosphere's tiles have a plane below to balance against");
    return 0;
}

Pen mainPen(const(Api)* api, Site site) {
    return mainHost(api).penAt(site).toPen();
}

Pen mainPenForward(const(Api)* api, Pen pen, double cells) {
    return PenFrame.fromPen(pen).moved(cells * mainHost(api).cellLength()).toPen();
}

Pen mainPenTurn(const(Api)* api, Pen pen, double yaw, double pitch) {
    return PenFrame.fromPen(pen).turned(axisOf(AHEAD), axisOf(ACROSS), yaw).turned(axisOf(AHEAD), axisOf(UP), pitch).toPen();
}

Pen mainPenRoll(const(Api)* api, Pen pen, double degrees) {
    return PenFrame.fromPen(pen).turned(axisOf(ACROSS), axisOf(UP), degrees).toPen();
}

Pen mainPenLift(const(Api)* api, Pen pen, double degrees) {
    return PenFrame.fromPen(pen).lifted(degrees).toPen();
}

double mainPenRise(const(Api)* api, Pen pen) {
    return asin(PenFrame.fromPen(pen).up()[AHEAD]) / RADIANS_PER_DEGREE;
}

double mainPenHeight(const(Api)* api, Pen pen) {
    PenFrame frame = PenFrame.fromPen(pen);
    return asinh(frame.ground.minkowski(frame.frame.m.column(3))) / mainHost(api).cellLength();
}

void mainLimb(const(Api)* api, Pen pen, Material material, double cells, double fromRadius, double toRadius) {
    mainHost(api).draw(pen, cells, fromRadius, toRadius, material, false);
}

void mainLeaves(const(Api)* api, Pen pen, Material material, double radius) {
    mainHost(api).draw(pen, 0, radius, radius, material, true);
}

bool mainBuild(const(Api)* api, const(char)* world, Site site) {
    Structure found = worldNamed(world);
    if (found is null) {
        mainHost(api).refuse("builds a world no plugin has");
        return false;
    } else {
        found(api, site, null);
        return true;
    }
}

void mainLook(const(Api)* api, uint kind, const(Look)* look) {
    mainHost(api).look(kind, *look);
}

void mainRisingKinds(const(Api)* api, double odds) {
    mainHost(api).addRisingKinds(odds);
}

bool mainLandmark(const(Api)* api, uint index, Site site) {
    if (index >= registry().landmarkCount) {
        return false;
    } else {
        registry().landmarks[index](api, site, null);
        return true;
    }
}

StructureProblem placeWorldStructure(ref Graph graph) {
    if (!graph.worldgen.hasStructure()) {
        return StructureProblem.init;
    } else {
        StructureHost* host = cast(StructureHost*) malloc(StructureHost.sizeof);
        *host = StructureHost.make(graph);
        host.build(rootSite(graph.anchorSlot));
        StructureProblem problem = host.problem;
        if (problem.isPresent || !(host.nextKey < host.queue.length || host.hasCover())) {
            releaseStructureHost(host);
        } else {
            graph.structures.grower = Grower(&growStructures, &coverStructures, &paintStructuresAhead, &releaseStructureHost, host);
        }
        return problem;
    }
}

void growStructures(void* context, ref Graph graph, int through) {
    (cast(StructureHost*) context).grow(graph, through);
}

void coverStructures(void* context, ref Graph graph, uint slot) {
    (cast(StructureHost*) context).cover(graph, slot);
}

void paintStructuresAhead(void* context, ref Graph graph, const(uint)[] candidates, Executor executor) {
    (cast(StructureHost*) context).paintAhead(graph, candidates, executor);
}

void releaseStructureHost(void* context) {
    StructureHost* host = cast(StructureHost*) context;
    host.release();
    free(host);
}

uint[2] tileCounts(ref const Graph graph) {
    if (graph.structures.grower.context is null) {
        return [0, 0];
    } else {
        const(TileWork)* tiles = &(cast(const(StructureHost)*) graph.structures.grower.context).tiles;
        return [tiles.preparedTiles, tiles.fallbackTiles];
    }
}

StructureProblem growthProblem(ref const Graph graph) {
    if (graph.structures.grower.context is null) {
        return StructureProblem.init;
    } else {
        return (cast(const(StructureHost)*) graph.structures.grower.context).problem;
    }
}

StructureProblem placeStructure(ref Game game) {
    StructureProblem problem = placeWorldStructure(game.world.graph);
    if (problem.isPresent) {
        return problem;
    } else {
        game.placeAtSpawn();
        return growthProblem(game.world.graph);
    }
}

StructureProblem restartGame(ref Game game, Worldgen worldgen) {
    game.rebuildWorld(worldgen);
    return placeStructure(game);
}
