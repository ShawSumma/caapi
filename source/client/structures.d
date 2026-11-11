module client.structures;

import core.stdc.math : asin, asinh, atan2, cos, cosh, sin, sinh, sqrt;
import core.stdc.stdlib : free, malloc;
import core.stdc.string : memcpy, strlen;
import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : RADIANS_PER_DEGREE, clamped, higherOf;
import base.parallel : Executor;
import base.splitmix : SplitMix, unitOf;
import base.stdio : snprintf;
import base.vector3 : Vec3;
import client.game : Game;
import client.plugins : registry, worldCount;
import client.tiles : TileCall, TileCalls, TileSpan, TileWork, isTiledBy, visitTilesAt;
import common.graph : Graph;
import common.look : Look, lookNamed;
import common.node : ChunkLayout;
import common.view : GraphView;
import common.worldgen.blueprint : BlueprintBuilder, CellBox, Cover, PaintOwner, PaintResult, Rhythm, Under;
import common.worldgen.generation : StructureWorld, Worldgen;
import common.worldgen.horospheres : GravityPull, HorosphereId, HorosphereKind, Horospheres, LOWEST_RISE_EDGES, ROOT, Rise, ensureColumnSite, ensureRise, openHorosphere;
import common.worldgen.plane : Plane;
import common.worldgen.store : Grower, TileKey;
import common.worldgen.strokes : Stroke, StrokeForm;
import common.worldgen.structure : ClaimKey, ColumnSpot, PLACE_SLACK, RootedCorner, SiteFrame, anchorBits, calmAt, edgeCells, edgeLength, ensureClaimKey, ensureSiteHash, ensureSiteOrigin, forwarded, frameOf, moveToLevel, rootSite, siteOf, sitePlacement, turnSite;
import geometry.lorentz : Motion, Vec4;
import plugins.api.api : Api, Box, ColumnCell, HorosphereForm, KindId, KindTag, Material, Pen, Repeat, RisingKind, Site, SitePart, Span, Spot, Structure, Tile, Turn;
import plugins.api.api : ApiRhythm = Rhythm;

enum size_t MESSAGE_CAPACITY = 1024;
enum string UNBOUNDED_PAINT = "paints bounded heights: give the box a z range";
enum string UNKNOWN_LOOK = "names a look that no mod defines";
enum string BAD_PEN_DRAW = "a pen draws a length of at least zero with radii above zero";
enum string ONLY_WORLD_TILES_GROUND = "only the world's own structure tiles the ground, and only once";
enum string ONLY_WORLD_TILES_EDGES = "only the world's own structure tiles the edges, and only once";
enum string ONLY_WORLD_FLATTENS = "only the world's own structure flattens the ground";
enum string ONLY_WORLD_TURNS_GRAVITY = "only the world's own structure turns gravity around";
enum string ONLY_WORLD_SETS_FOG = "only the world's own structure sets the fog";
enum string ONLY_WORLD_GIVES_KINDS = "only the world's own structure gives horospheres their kinds";
enum string ONLY_WORLD_SETS_LOOK = "only the world's own structure sets how it looks";
enum string ONLY_WORLD_OPENS = "only the world's own structure opens horospheres";
enum string ONLY_WORLD_ROOTS = "only the world's own structure gives the root its kind, and only once";
enum string ONLY_WORLD_SHAPES_GROUND = "only the world's own structure gives a ground its crust or its ports";
enum string NOT_AN_EDGE_CLAIM = "a site claims its vertex or face, not its edge";
enum ulong PORT_SALT = 0x504F_5254_5F31;
enum string UNKNOWN_KIND = "unknown kind of horosphere";
enum double HALF_TURN = 3.141592653589793;
enum double VERTICAL_TOLERANCE = 1e-9;
enum Vec3!double ACROSS = Vec3!double(1, 0, 0);
enum Vec3!double UP = Vec3!double(0, 1, 0);
enum Vec3!double AHEAD = Vec3!double(0, 0, 1);

struct StructureProblem {
    char[MESSAGE_CAPACITY] text = 0;

    bool isPresent() const {
        return text[0] != 0;
    }

    static StructureProblem fromMessage(const(char)[] name, const(char)* message) {
        StructureProblem problem;
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

    Vec3!double up() const {
        Vec4!double local = frame.inverse() * ground;
        double length = sqrt(local.c[0] * local.c[0] + local.c[1] * local.c[1] + local.c[2] * local.c[2]);
        return Vec3!double(local.c[0] / length, local.c[1] / length, local.c[2] / length);
    }

    PenFrame moved(double distance) const {
        return PenFrame((frame * Motion!double.shift(Vec3!double(0, 0, distance))).orthonormalized(), ground, node);
    }

    PenFrame turned(Vec3!double from, Vec3!double toward, double degrees) const {
        return PenFrame(frame * planeRotation(from, toward, degrees * RADIANS_PER_DEGREE), ground, node);
    }

    PenFrame lifted(double degrees) const {
        Vec3!double rising = up();
        double side = sqrt(rising.x * rising.x + rising.y * rising.y);
        if (side < VERTICAL_TOLERANCE) {
            return this;
        } else {
            double toUp = atan2(side, rising.z);
            double angle = clamped(degrees * RADIANS_PER_DEGREE, toUp - HALF_TURN, toUp);
            return PenFrame(frame * planeRotation(AHEAD, Vec3!double(rising.x / side, rising.y / side, 0), angle), ground, node);
        }
    }
}

Motion!double planeRotation(Vec3!double from, Vec3!double toward, double angle) {
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
    return Vec4!double([plane.up.x * stretch, plane.up.y * stretch, plane.up.z * stretch, -sinh(plane.height)]);
}

Span columnOf(ubyte dimension) {
    return Span(-cast(int) dimension, dimension - 1);
}

double cellLengthOf(ref const ChunkLayout layout) {
    return edgeLength(layout).value / edgeCells(layout.dimension);
}

mixin template Refusing() {
    const(char)* refusal;

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
}

bool isWithin(Box area, Span column) {
    return area.low.x >= column.low && area.high.x <= column.high && area.low.y >= column.low && area.high.y <= column.high;
}

bool isOrdered(Box area) {
    return area.low.x <= area.high.x && area.low.y <= area.high.y && area.low.z <= area.high.z;
}

Vec3!int cellOf(ColumnCell cell) {
    return Vec3!int(cell.x, cell.y, cell.z);
}

CellBox cellBoxOf(Box area) {
    return CellBox(cellOf(area.low), cellOf(area.high), area.extent);
}

const(char)* boxRefusal(Box area, ApiRhythm rhythm, Span column) {
    if (!isOrdered(area)) {
        return "a box runs from high to low";
    } else if (!area.isWithin(column)) {
        return "a box leaves the site's column";
    } else if (rhythm.repeat == Repeat.rhythmic && (rhythm.every <= 0 || rhythm.span <= 0)) {
        return "a rhythm needs a positive every and span";
    } else {
        return null;
    }
}

Rhythm engineRhythm(ApiRhythm rhythm) {
    return Rhythm(rhythm.every, rhythm.from, rhythm.span, rhythm.repeat);
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

enum WorldStep : ubyte {
    previous,
    next,
}

uint steppedWorld(uint index, WorldStep direction) {
    uint count = worldCount();
    uint step = count - 1;
    if (direction == WorldStep.next) {
        step = 1;
    }
    return (index + step) % count;
}

Worldgen worldgenAt(uint index) {
    if (index == 0) {
        return Worldgen.makeTerrain();
    } else {
        return Worldgen.fromStructure(StructureWorld.fromName(registry().allNames()[index - 1]));
    }
}

bool probePort(ref GraphView view, Site site, HorosphereId over) {
    double odds = view.blueprint.portOdds;
    if (!(odds > 0)) {
        return false;
    } else {
        ulong hash = view.ensureSiteHash(frameOf(site), SitePart.vertex);
        if (!(unitOf(SplitMix(hash ^ PORT_SALT).next()) < odds) || hash == view.ensureSiteHash(startOf(view, over), SitePart.vertex)) {
            return false;
        } else {
            bool rising = view.ensureRisingTag(site, over).exists;
            return !rising;
        }
    }
}

SiteFrame startOf(ref GraphView view, HorosphereId over) {
    if (over == ROOT) {
        return rootSite(view.graph.anchorSlot);
    } else {
        return view.horospheres.horosphere(over).foot;
    }
}

KindTag ensureRisingTag(ref GraphView view, Site site, HorosphereId over) {
    SiteFrame at = view.moveToLevel(frameOf(site), 0);
    Rise rise = view.ensureRise(at.node, at.corner, over);
    if (rise.kind.exists) {
        return KindTag.of(view.horospheres.kinds.ptr[rise.kind.value].tag);
    } else {
        return KindTag.init;
    }
}

struct StructureHost {
    BlueprintBuilder builder;
    Array!(Array!QueuedStructure) queue;
    TileCalls calls;
    TileWork tiles;
    Executor executor;
    SplitMix random;
    Api api;
    StructureWorld name;
    uint key;
    uint nextKey;
    StructureProblem problem;

    mixin Refusing;

    static StructureHost make(ref Graph graph) {
        StructureHost host;
        host.builder = BlueprintBuilder.make(graph);
        host.random = SplitMix(graph.anchorBits(graph.anchorSlot));
        host.name = StructureWorld.fromName(graph.worldgen.structureName());
        return host;
    }

    bool hasCover() const {
        foreach (call; calls.kinds.slice()) {
            if (call.tile !is null) {
                return true;
            }
        }
        return calls.root.tile !is null || calls.edge.tile !is null;
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
            void onTile(TileKey key, SiteFrame site, HorosphereId over, int segment, TileSpan span) {
                coverTile(graph, key, site, over, segment, span);
            }
            visitTilesAt!onTile(graph.view, calls, slot);
            runTiles(graph);
        }
    }

    void coverTile(ref Graph graph, TileKey key, SiteFrame site, HorosphereId over, int segment, TileSpan span) {
        const(uint)* known = graph.structures.tiledFaces.find(key);
        if (known !is null && !graph.structures.blueprint.tiles.ptr[*known].isDropped) {
            graph.structures.blueprint.useTile(*known);
        } else {
            tiles.addTask(graph, key, site.node, null, over, site, segment, span);
        }
    }

    void runTiles(ref Graph graph) {
        tiles.fallbackTiles += cast(uint) tiles.tasks.length;
        tiles.runTasks(graph, executor);
        if (tiles.hasFailed) {
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

    ref GraphView hostView() {
        return builder.graph.view;
    }

    ubyte dimension() const {
        return builder.graph.layout.dimension;
    }

    Span column() const {
        return columnOf(dimension());
    }

    double cellLength() const {
        return cellLengthOf(builder.graph.layout);
    }

    void paint(Site site, Material material, Box area, ApiRhythm rhythm, Cover cover) {
        const(char)* wrong = boxRefusal(area, rhythm, column());
        if (wrong !is null) {
            refuse(wrong);
        } else {
            PaintResult result = builder.paint(frameOf(site), cellBoxOf(area), engineRhythm(rhythm), material, cover);
            if (result == PaintResult.endless) {
                refuse(UNBOUNDED_PAINT);
            } else if (result == PaintResult.behind) {
                refuse("paints too far behind its site: a placed structure stays near where it was placed");
            }
        }
    }

    bool place(Site site, Structure structure, const(void)* data, size_t size) {
        SiteFrame frame = frameOf(site);
        RootedCorner origin = builder.graph.view.ensureSiteOrigin(frame);
        if (cast(int) origin.depth + PLACE_SLACK >= cast(int) key) {
            enqueue(QueuedStructure(frame, Array!uint.init, copied(data, size), structure, higherOf(origin.depth, key)));
            return true;
        } else {
            return false;
        }
    }

    ClaimKey ensureClaimKeyAt(Site site, SitePart part) {
        return builder.graph.view.ensureClaimKey(frameOf(site), part);
    }

    bool claim(Site site, SitePart part) {
        if (part == SitePart.edge) {
            refuse(NOT_AN_EDGE_CLAIM);
            return false;
        } else {
            return builder.claim(ensureClaimKeyAt(site, part));
        }
    }

    bool probeClaimed(Site site, SitePart part) {
        if (part == SitePart.edge) {
            refuse(NOT_AN_EDGE_CLAIM);
            return false;
        } else {
            ClaimKey key = ensureClaimKeyAt(site, part);
            return builder.blueprint.isClaimed(key);
        }
    }

    void tile(Tile tile, const(void)* data, size_t size) {
        if (builder.isGrowing || calls.hasRoot) {
            refuse(ONLY_WORLD_TILES_GROUND);
        } else {
            calls.root = TileCall(tile, copied(data, size));
        }
    }

    void tileEdges(Tile tile, const(void)* data, size_t size) {
        if (builder.isGrowing || calls.hasEdge) {
            refuse(ONLY_WORLD_TILES_EDGES);
        } else {
            calls.edge = TileCall(tile, copied(data, size));
        }
    }

    void flatten(Site site) {
        if (builder.isGrowing) {
            refuse(ONLY_WORLD_FLATTENS);
        } else {
            SiteFrame at = builder.graph.view.moveToLevel(frameOf(site), 0);
            builder.graph.structures.blueprint.flats.append(at);
            builder.graph.reference(at.node);
            foreach (slot; 0 .. builder.graph.slotCount) {
                if (builder.graph.nodeAt(slot).hasState) {
                    builder.graph.states.at(slot).climate.calm = builder.graph.view.calmAt(slot);
                }
            }
        }
    }

    void invertGravity() {
        if (builder.isGrowing) {
            refuse(ONLY_WORLD_TURNS_GRAVITY);
        } else {
            builder.graph.horospheres.pull = GravityPull.up;
        }
    }

    void fog(double units) {
        if (builder.isGrowing) {
            refuse(ONLY_WORLD_SETS_FOG);
        } else if (!(units > 0)) {
            refuse("the fog closes in past a distance above zero");
        } else {
            builder.graph.structures.blueprint.fog = Maybe!float.of(cast(float) units);
        }
    }

    KindId horosphere(double odds, HorosphereForm form, uint tag, Tile tile, const(void)* data, size_t size) {
        Horospheres* horospheres = &builder.graph.horospheres;
        if (builder.isGrowing) {
            refuse(ONLY_WORLD_GIVES_KINDS);
            return KindId.init;
        } else if (!(odds >= 0) || horospheres.totalOdds() + odds > 1) {
            refuse("horosphere odds are chances per vertex, and all kinds together add up to at most 1");
            return KindId.init;
        } else if (horospheres.kinds.length == ubyte.max) {
            refuse("too many kinds of horosphere");
            return KindId.init;
        } else {
            horospheres.kinds.append(HorosphereKind(odds, form, tag));
            calls.kinds.append(TileCall(tile, copied(data, size)));
            return KindId.of(cast(uint) horospheres.kinds.length - 1);
        }
    }

    KindId sunken(double odds, uint under, uint tag, Tile tile, const(void)* data, size_t size) {
        KindId made = horosphere(odds, HorosphereForm.sunken, tag, tile, data, size);
        if (refusal is null) {
            builder.graph.horospheres.kinds.ptr[made.value].under = under;
        }
        return made;
    }

    void look(KindId kind, const(char)[] name) {
        Maybe!Look chosen = lookNamed(name);
        if (builder.isGrowing) {
            refuse(ONLY_WORLD_SETS_LOOK);
        } else if (!isKnownKind(kind)) {
            refuse(UNKNOWN_KIND);
        } else if (!chosen.exists) {
            refuse(UNKNOWN_LOOK);
        } else {
            builder.graph.horospheres.kinds.ptr[kind.value].look = chosen.value;
        }
    }

    void worldLook(const(char)[] name) {
        Maybe!Look chosen = lookNamed(name);
        if (builder.isGrowing) {
            refuse(ONLY_WORLD_SETS_LOOK);
        } else if (!chosen.exists) {
            refuse(UNKNOWN_LOOK);
        } else {
            builder.graph.structures.blueprint.look = chosen.value;
        }
    }

    void under(KindTag ground, const(char)[] name, double depth, double fog) {
        Maybe!Look chosen = lookNamed(name);
        if (builder.isGrowing) {
            refuse(ONLY_WORLD_SETS_LOOK);
        } else if (!chosen.exists) {
            refuse(UNKNOWN_LOOK);
        } else if (!(depth >= 0) || !(fog > 0)) {
            refuse("a ground looks different below a depth of at least zero edges, with fog closing in past a distance above zero");
        } else {
            builder.graph.structures.blueprint.unders.append(Under(ground, chosen.value, cast(float)(depth * edgeLength(builder.graph.layout).value), cast(float) fog));
        }
    }

    void crust(KindTag ground, double edges) {
        Horospheres* horospheres = &builder.graph.horospheres;
        float units = cast(float)(edges * edgeLength(builder.graph.layout).value);
        if (builder.isGrowing) {
            refuse(ONLY_WORLD_SHAPES_GROUND);
        } else if (!(edges > 0)) {
            refuse("a ground's crust is thicker than zero edges");
        } else if (!ground.exists) {
            horospheres.rootCrust = units;
        } else {
            foreach (ref kind; horospheres.kinds.slice()) {
                if (kind.tag == ground.value) {
                    kind.crust = units;
                }
            }
        }
    }

    void ports(double odds) {
        if (builder.isGrowing) {
            refuse(ONLY_WORLD_SHAPES_GROUND);
        } else if (!(odds >= 0) || odds > 1) {
            refuse("ports are a chance per vertex from 0 to 1");
        } else {
            builder.graph.structures.blueprint.portOdds = odds;
        }
    }

    bool probePortAt(Site site) {
        return builder.graph.view.probePort(site, ROOT);
    }

    void addRisingKinds(double odds) {
        foreach (ref kind; registry().risingKinds[0 .. registry().kindCount]) {
            KindId made = horosphere(odds * kind.share, kind.form, kind.tag, kind.tile, kind.data, kind.size);
            if (refusal is null) {
                builder.graph.horospheres.kinds.ptr[made.value].under = kind.under;
                look(made, kind.look);
            }
        }
    }

    bool isKnownKind(KindId kind) const {
        return kind.exists && kind.value < builder.graph.horospheres.kinds.length;
    }

    void openHorosphereAt(Site site, KindId kind, uint edges) {
        if (builder.isGrowing) {
            refuse(ONLY_WORLD_OPENS);
        } else if (!isKnownKind(kind)) {
            refuse(UNKNOWN_KIND);
        } else if (edges < LOWEST_RISE_EDGES || edges > ubyte.max) {
            refuse("a horosphere rises at least two edges");
        } else {
            bool opened = (*builder.graph).openHorosphere(frameOf(site), Rise(MaybeIndex!ubyte.of(cast(ubyte) kind.value), cast(ubyte) edges));
            if (!opened) {
                refuse("a horosphere beside another one would cross it");
            }
        }
    }

    void rooted(KindId kind) {
        Horospheres* horospheres = &builder.graph.horospheres;
        if (builder.isGrowing || horospheres.rootKind.exists) {
            refuse(ONLY_WORLD_ROOTS);
        } else if (!isKnownKind(kind)) {
            refuse(UNKNOWN_KIND);
        } else if (horospheres.isUprightKind(cast(ubyte) kind.value)) {
            refuse("the root is a plane, so it cannot be an upright kind");
        } else {
            horospheres.rootKind = MaybeIndex!ubyte.of(cast(ubyte) kind.value);
        }
    }

    KindTag ensureRisingTagAt(Site site) {
        return builder.graph.view.ensureRisingTag(site, ROOT);
    }

    PenFrame ensurePen(Site site) {
        Graph* graph = builder.graph;
        SiteFrame frame = frameOf(site);
        return PenFrame(sitePlacement(frame, graph.layout).as!double(), unitNormal(graph.ensureState(frame.node).surface), frame.node);
    }

    void draw(Pen pen, double cells, double fromRadius, double toRadius, Material material, StrokeForm form) {
        if (builder.isGrowing) {
            refuse("only the world's own structure draws with a pen");
        } else if (!(cells >= 0) || !(fromRadius > 0) || !(toRadius > 0)) {
            refuse(BAD_PEN_DRAW);
        } else {
            Graph* graph = builder.graph;
            double cell = cellLength();
            PenFrame frame = PenFrame.fromPen(pen);
            graph.structures.addStroke(graph.view, PaintOwner.init, frame.node, Stroke.make(frame.frame, cells * cell, cast(float)(fromRadius * cell), cast(float)(toRadius * cell), material, form));
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
    api.failure = &apiFailure!mainHost;
    api.fail = &apiFail!mainHost;
    api.forward = &apiForward;
    api.turn = &apiTurned!mainHost;
    api.column = &apiColumn!mainHost;
    api.edgeCells = &apiEdgeCells!mainHost;
    api.pick = &apiPick!mainHost;
    api.random = &apiRandom!mainHost;
    api.probeHash = &apiHash!mainHost;
    api.paint = &apiPaint!mainHost;
    api.fill = &apiFill!mainHost;
    api.stop = &mainStop;
    api.entrance = &mainEntrance;
    api.place = &mainPlace;
    api.claim = &mainClaim;
    api.probeClaimed = &mainProbeClaimed;
    api.tile = &mainTile;
    api.tileEdges = &mainTileEdges;
    api.horosphere = &mainHorosphere;
    api.sunken = &mainSunken;
    api.openHorosphere = &mainOpenHorosphere;
    api.columnSite = &mainColumnSite;
    api.flatten = &mainFlatten;
    api.rooted = &mainRooted;
    api.invertGravity = &mainInvertGravity;
    api.fog = &mainFog;
    api.probeRising = &apiRising!mainHost;
    api.probeBalance = &mainBalance;
    api.openPen = &apiPen!mainHost;
    api.penForward = &apiPenForward!mainHost;
    api.penTurn = &apiPenTurn;
    api.penRoll = &apiPenRoll;
    api.penLift = &apiPenLift;
    api.penRise = &apiPenRise;
    api.penHeight = &apiPenHeight!mainHost;
    api.limb = &apiLimb!mainHost;
    api.leaves = &apiLeaves!mainHost;
    api.build = &apiBuild!mainHost;
    api.look = &mainLook;
    api.worldLook = &mainWorldLook;
    api.risingKinds = &mainRisingKinds;
    api.landmark = &mainLandmark;
    api.under = &mainUnder;
    api.crust = &mainCrust;
    api.ports = &mainPorts;
    api.probePort = &apiPort!mainHost;
    return api;
}

const(char)* apiFailure(alias hostOf)(const(Api)* api) {
    const(char)* refusal = hostOf(api).refusal;
    hostOf(api).refusal = null;
    return refusal;
}

void apiFail(alias hostOf)(const(Api)* api, const(char)* message) {
    hostOf(api).refuse(message);
}

Site apiForward(const(Api)* api, Site site, int edges) {
    return siteOf(forwarded(frameOf(site), edges));
}

Site apiTurned(alias hostOf)(const(Api)* api, Site site, Turn turn) {
    return siteOf(hostOf(api).hostView.turnSite(frameOf(site), turn));
}

ulong apiHash(alias hostOf)(const(Api)* api, Site site, SitePart part) {
    return hostOf(api).hostView.ensureSiteHash(frameOf(site), part);
}

Span apiColumn(alias hostOf)(const(Api)* api) {
    return hostOf(api).column();
}

int apiEdgeCells(alias hostOf)(const(Api)* api) {
    return edgeCells(hostOf(api).dimension());
}

uint apiPick(alias hostOf)(const(Api)* api, uint count) {
    return cast(uint)(hostOf(api).random.next() % count);
}

double apiRandom(alias hostOf)(const(Api)* api) {
    return hostOf(api).random.unit();
}

void apiPaint(alias hostOf)(const(Api)* api, Site site, Material material, Box area, ApiRhythm rhythm) {
    hostOf(api).paint(site, material, area, rhythm, Cover.over);
}

void apiFill(alias hostOf)(const(Api)* api, Site site, Material material, Box area, ApiRhythm rhythm) {
    hostOf(api).paint(site, material, area, rhythm, Cover.intoAir);
}

KindTag apiRising(alias hostOf)(const(Api)* api, Site site) {
    return hostOf(api).ensureRisingTagAt(site);
}

Pen apiPen(alias hostOf)(const(Api)* api, Site site) {
    return hostOf(api).ensurePen(site).toPen();
}

Pen apiPenForward(alias hostOf)(const(Api)* api, Pen pen, double cells) {
    return PenFrame.fromPen(pen).moved(cells * hostOf(api).cellLength()).toPen();
}

Pen apiPenTurn(const(Api)* api, Pen pen, double yaw, double pitch) {
    return PenFrame.fromPen(pen).turned(AHEAD, ACROSS, yaw).turned(AHEAD, UP, pitch).toPen();
}

Pen apiPenRoll(const(Api)* api, Pen pen, double degrees) {
    return PenFrame.fromPen(pen).turned(ACROSS, UP, degrees).toPen();
}

Pen apiPenLift(const(Api)* api, Pen pen, double degrees) {
    return PenFrame.fromPen(pen).lifted(degrees).toPen();
}

double apiPenRise(const(Api)* api, Pen pen) {
    return asin(PenFrame.fromPen(pen).up().z) / RADIANS_PER_DEGREE;
}

double apiPenHeight(alias hostOf)(const(Api)* api, Pen pen) {
    PenFrame frame = PenFrame.fromPen(pen);
    return asinh(frame.ground.minkowski(frame.frame.m.column(3))) / hostOf(api).cellLength();
}

void apiLimb(alias hostOf)(const(Api)* api, Pen pen, Material material, double cells, double fromRadius, double toRadius) {
    hostOf(api).draw(pen, cells, fromRadius, toRadius, material, StrokeForm.solid);
}

void apiLeaves(alias hostOf)(const(Api)* api, Pen pen, Material material, double radius) {
    hostOf(api).draw(pen, 0, radius, radius, material, StrokeForm.leafy);
}

bool apiBuild(alias hostOf)(const(Api)* api, const(char)* world, Site site) {
    Structure found = worldNamed(world);
    if (found is null) {
        hostOf(api).refuse("builds a world no plugin has");
        return false;
    } else {
        found(api, site, null);
        return true;
    }
}

void mainStop(const(Api)* api, Site site, Spot spot) {
    mainHost(api).builder.stop(mainHost(api).builder.graph.view.moveToLevel(frameOf(site), 0), ColumnSpot(spot.x, spot.y, spot.z));
}

void mainEntrance(const(Api)* api, Site site, Spot spot) {
    mainHost(api).builder.enter(frameOf(site), ColumnSpot(spot.x, spot.y, spot.z));
}

bool mainPlace(const(Api)* api, Site site, Structure structure, const(void)* data, size_t size) {
    return mainHost(api).place(site, structure, data, size);
}

void mainFlatten(const(Api)* api, Site site) {
    mainHost(api).flatten(site);
}

bool mainClaim(const(Api)* api, Site site, SitePart part) {
    return mainHost(api).claim(site, part);
}

bool mainProbeClaimed(const(Api)* api, Site site, SitePart part) {
    return mainHost(api).probeClaimed(site, part);
}

void mainTile(const(Api)* api, Tile tile, const(void)* data, size_t size) {
    mainHost(api).tile(tile, data, size);
}

KindId mainHorosphere(const(Api)* api, double odds, HorosphereForm form, uint tag, Tile tile, const(void)* data, size_t size) {
    return mainHost(api).horosphere(odds, form, tag, tile, data, size);
}

KindId mainSunken(const(Api)* api, double odds, uint under, uint tag, Tile tile, const(void)* data, size_t size) {
    return mainHost(api).sunken(odds, under, tag, tile, data, size);
}

void mainOpenHorosphere(const(Api)* api, Site site, KindId kind, uint edges) {
    mainHost(api).openHorosphereAt(site, kind, edges);
}

Site mainColumnSite(const(Api)* api, Site site) {
    return siteOf((*mainHost(api).builder.graph).ensureColumnSite(frameOf(site)));
}

void mainRooted(const(Api)* api, KindId kind) {
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

int mainBalance(const(Api)* api, Site site, int most) {
    mainHost(api).refuse("only a horosphere's tiles have a plane below to balance against");
    return 0;
}

void mainLook(const(Api)* api, KindId kind, const(char)[] look) {
    mainHost(api).look(kind, look);
}

void mainWorldLook(const(Api)* api, const(char)[] look) {
    mainHost(api).worldLook(look);
}

void mainRisingKinds(const(Api)* api, double odds) {
    mainHost(api).addRisingKinds(odds);
}

void mainUnder(const(Api)* api, KindTag ground, const(char)[] look, double depth, double fog) {
    mainHost(api).under(ground, look, depth, fog);
}

void mainCrust(const(Api)* api, KindTag ground, double edges) {
    mainHost(api).crust(ground, edges);
}

void mainPorts(const(Api)* api, double odds) {
    mainHost(api).ports(odds);
}

bool apiPort(alias hostOf)(const(Api)* api, Site site) {
    return hostOf(api).probePortAt(site);
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

struct TileCounts {
    uint prepared;
    uint fallback;
}

TileCounts tileCounts(ref const Graph graph) {
    if (graph.structures.grower.context is null) {
        return TileCounts.init;
    } else {
        const(TileWork)* tiles = &(cast(const(StructureHost)*) graph.structures.grower.context).tiles;
        return TileCounts(tiles.preparedTiles, tiles.fallbackTiles);
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
