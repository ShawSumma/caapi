module client.tiles;

import core.stdc.stdlib : calloc, free;
import core.stdc.string : memcpy, strlen;
import bindings.lua : luaL_checkinteger, luaL_checklstring, luaL_checknumber, luaL_checktype, luaL_checkudata, luaL_error, luaL_newmetatable, lua_CFunction, lua_Integer, lua_State, lua_close, lua_createtable, lua_gettop, lua_pcallk, lua_pushboolean, lua_pushcclosure, lua_pushinteger, lua_pushlightuserdata, lua_rawgeti, lua_setfield, lua_settop, lua_tointegerx, lua_tolstring, lua_touserdata, lua_type;
import client.lua : LUA_BELOW_TOP, LUA_FIRST_UPVALUE, LUA_REGISTRY, LUA_SECOND_UPVALUE, LUA_STATUS_OK, LUA_TOP, LUA_TYPE_FUNCTION, LuaName, SELF, TRACEBACK_INDEX, isNoneOrNil, luaTraceback, newSafeState, registerMethod;
import client.structures : AIR, CHUNK_RESULTS, COLUMN_RESULTS, MESSAGE_CAPACITY, PLACED_FUNCTION, SITE_TYPE, SKY_FIELDS, SKY_TILE, STRUCTURE_ARGUMENTS, StructureProblem, TURN_UPVALUES, TileCall, boxArgument, columnOf, loadStructureChunk, materialArgument, packedCall, partArgument, pushSite, registerModules, rhythmArgument, siteArgument, spotArgument;
import base.array : Array;
import base.hashmap : HashMap;
import base.names : ENUM_NAMES;
import base.numbers : higherOf, lowerOf;
import base.parallel : Executor, ParallelJob;
import common.graph : Graph, NO_SLOT, NodeId, ROOT_NODE;
import common.material : Material;
import common.view : GraphView, VIRTUAL;
import common.worldgen.blueprint : Blueprint, Brush, CellBox, LevelRange, LineEdge, LineKey, LineSpec, Paint, PaintResult, Rhythm, RouteStop, TileRecord, canonicalBox, canonicalRhythm, edgeOf;
import common.worldgen.generation : SplitMix, StructureWorld;
import common.worldgen.sky : PLANET, SkyMeasure, World, balanceAlong, ensureWorldsAt, isPaintedBySky, measureOf, measuredWorld, storeMeasure, worldGroundNodeOf;
import common.worldgen.structure : CanonicalSite, ColumnSpot, EDGE_NODES, GROUND_RING, LineTouch, LineTransform, SiteFrame, SlotTouch, Turn, addPendingTouch, aroundEdge, canonicalOf, edgeCells, faceSite, forwarded, groundRing, seedTouch, siteHash, turned, walkedTouch;
import geometry.honeycomb : Face;

enum uint NO_RECORD = uint.max;
enum size_t TILE_TASK_BUDGET = 256;
enum uint PLAN_ROUNDS = 4;

// A tile paints from site hashes alone, so any thread can run it against a read-only view of the graph. What it
// paints is kept here keyed by node and line identity, and the main thread applies it afterwards.
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

    // Nodes only gain structure on the main thread between phases, so levels found open stay open for the whole tile.
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

// One per thread that runs tiles: its own Lua state, which ran the world's structure once to register the same tile
// functions. It reads the graph through the view of whichever thread runs its current call.
struct TileHost {
    TilePainter painter;
    PlanOutputs plan;
    GraphView* view;
    Array!TileCall skyTiles;
    TileCall planetTile;
    SplitMix random;
    lua_State* lua;
    uint sky;
    bool isReplaying;
    bool hasPlanetTile;
    bool hasFailed;
    char[MESSAGE_CAPACITY] failure;

    void build(GraphView* threadView, StructureWorld name, SiteFrame root, ulong seed) {
        view = threadView;
        lua = newSafeState();
        registerModules(lua);
        registerSiteType();
        lua_pushcclosure(lua, cast(lua_CFunction) &luaTraceback, 0);
        isReplaying = true;
        random = SplitMix(seed);
        if (loadStructureChunk(lua, name.name()) != LUA_STATUS_OK || lua_pcallk(lua, 0, CHUNK_RESULTS, TRACEBACK_INDEX, 0, null) != LUA_STATUS_OK) {
            fail();
        } else if (lua_type(lua, LUA_TOP) == LUA_TYPE_FUNCTION) {
            lua.pushSite(root);
            if (lua_pcallk(lua, STRUCTURE_ARGUMENTS, 0, TRACEBACK_INDEX, 0, null) != LUA_STATUS_OK) {
                fail();
            }
        }
        lua_settop(lua, TRACEBACK_INDEX);
        isReplaying = false;
    }

    void fail() {
        hasFailed = true;
        const(char)* message = lua_tolstring(lua, LUA_TOP, null);
        size_t length = strlen(message);
        if (length >= failure.length) {
            length = failure.length - 1;
        }
        memcpy(failure.ptr, message, length);
        failure[length] = 0;
    }

    void registerSiteType() {
        luaL_newmetatable(lua, SITE_TYPE.ptr);
        lua_createtable(lua, 0, 0);
        lua.registerMethod(&this, "forward", &tileForward);
        foreach (index, member; ENUM_NAMES!Turn) {
            LuaName turnName = LuaName.fromMember(member);
            turnName.text[turnName.length] = 0;
            lua_pushlightuserdata(lua, &this);
            lua_pushinteger(lua, cast(lua_Integer) index);
            lua_pushcclosure(lua, cast(lua_CFunction) &tileTurn, TURN_UPVALUES);
            lua_setfield(lua, LUA_BELOW_TOP, turnName.text.ptr);
        }
        lua.registerMethod(&this, "column", &tileColumn);
        lua.registerMethod(&this, "edge_cells", &tileEdgeCells);
        lua.registerMethod(&this, "pick", &tilePick);
        lua.registerMethod(&this, "paint", &tilePaint);
        lua.registerMethod(&this, "fill", &tileFill);
        lua.registerMethod(&this, "stop", &tileStop);
        lua.registerMethod(&this, "entrance", &tileEntrance);
        lua.registerMethod(&this, "place", &tilePlace);
        lua.registerMethod(&this, "claim", &tileClaim);
        lua.registerMethod(&this, "is_claimed", &tileIsClaimed);
        lua.registerMethod(&this, "tile", &tileTile);
        lua.registerMethod(&this, "sky", &tileSky);
        lua.registerMethod(&this, "open_sky", &tileOpenSky);
        lua.registerMethod(&this, "balance", &tileBalance);
        lua.registerMethod(&this, "hash", &tileHash);
        lua_setfield(lua, LUA_BELOW_TOP, "__index");
        lua_settop(lua, LUA_BELOW_TOP);
    }

    ubyte dimension() const {
        return view.layout.dimension;
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
        TileCall call = planetTile;
        if (task.sky != PLANET) {
            call = skyTiles.ptr[graph.skies.world(task.sky).kind];
        }
        lua_rawgeti(lua, LUA_REGISTRY, call.reference);
        int placed = lua_gettop(lua);
        lua_rawgeti(lua, placed, PLACED_FUNCTION);
        lua.pushSite(faceSite(face, task.label));
        int pushed = STRUCTURE_ARGUMENTS;
        if (task.sky != PLANET) {
            pushSky(graph.skies.world(task.sky));
            pushed += 1;
        }
        foreach (argument; 0 .. call.argumentCount) {
            lua_rawgeti(lua, placed, PLACED_FUNCTION + 1 + argument);
        }
        bool isFailed = lua_pcallk(lua, pushed + call.argumentCount, 0, TRACEBACK_INDEX, 0, null) != LUA_STATUS_OK;
        if (isFailed && !hasFailed) {
            fail();
        }
        lua_settop(lua, TRACEBACK_INDEX);
        painter.finish(isFailed);
    }

    void pushSky(ref const World world) {
        lua_createtable(lua, 0, SKY_FIELDS);
        lua.pushSite(world.foot);
        lua_setfield(lua, LUA_BELOW_TOP, "foot");
        lua_pushinteger(lua, world.edges);
        lua_setfield(lua, LUA_BELOW_TOP, "edges");
        lua_pushinteger(lua, world.ground);
        lua_setfield(lua, LUA_BELOW_TOP, "ground");
        lua_pushinteger(lua, world.below);
        lua_setfield(lua, LUA_BELOW_TOP, "below");
        lua_pushinteger(lua, world.balance);
        lua_setfield(lua, LUA_BELOW_TOP, "balance");
    }

    // Works out which faces a node's cover needs painted, the same faces StructureHost.cover tiles on the main thread.
    void planCandidate(ref const Graph graph, GraphView* threadView, uint candidate, uint index) {
        view = threadView;
        uint faceStart = cast(uint) plan.faces.length;
        if (!graph.isFinished(candidate)) {
            if (hasPlanetTile) {
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

    // A sky's tiles read its measurements, which take many height samples, so they are taken here on any thread.
    void measureSkies(ref const Graph graph, uint faceStart) {
        foreach (index; faceStart .. plan.faces.length) {
            uint sky = plan.faces.ptr[index].sky;
            if (sky != PLANET && !graph.skies.world(sky).isMeasured && !plan.hasMeasure(sky)) {
                SkyMeasure measure = (*view).measureOf(sky);
                if (view.isBlocked) {
                    view.forget();
                } else {
                    plan.measures.append(MeasuredSky(sky, measure));
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
        skyTiles.release();
        if (lua !is null) {
            lua_close(lua);
        }
    }
}

TileHost* tileHost(lua_State* lua) {
    luaL_checkudata(lua, SELF, SITE_TYPE.ptr);
    return cast(TileHost*) lua_touserdata(lua, LUA_FIRST_UPVALUE);
}

extern (C) int tileForward(lua_State* lua) {
    tileHost(lua);
    lua.pushSite(forwarded(siteArgument(lua), cast(int) luaL_checkinteger(lua, SELF + 1)));
    return 1;
}

extern (C) int tileTurn(lua_State* lua) {
    TileHost* host = tileHost(lua);
    Turn turn = cast(Turn) lua_tointegerx(lua, LUA_SECOND_UPVALUE, null);
    lua.pushSite((*host.view).turned(siteArgument(lua), turn));
    return 1;
}

extern (C) int tileColumn(lua_State* lua) {
    int[2] column = columnOf(tileHost(lua).dimension());
    lua_pushinteger(lua, column[0]);
    lua_pushinteger(lua, column[1]);
    return COLUMN_RESULTS;
}

extern (C) int tileEdgeCells(lua_State* lua) {
    lua_pushinteger(lua, edgeCells(tileHost(lua).dimension()));
    return 1;
}

extern (C) int tilePick(lua_State* lua) {
    TileHost* host = tileHost(lua);
    lua_Integer count = luaL_checkinteger(lua, SELF + 1);
    if (count < 1) {
        luaL_error(lua, "pick needs at least one choice");
    }
    lua_pushinteger(lua, cast(lua_Integer)(host.random.next() % cast(ulong) count) + 1);
    return 1;
}

extern (C) int tilePaint(lua_State* lua) {
    return lua.tilePaintWith(false);
}

extern (C) int tileFill(lua_State* lua) {
    return lua.tilePaintWith(true);
}

int tilePaintWith(lua_State* lua, bool isIntoAirOnly) {
    TileHost* host = tileHost(lua);
    Material material = materialArgument(lua, SELF + 1);
    CellBox box = boxArgument(lua, SELF + 2, host.dimension());
    Rhythm rhythm = rhythmArgument(lua, SELF + 3);
    if (!host.isReplaying) {
        PaintResult result = host.painter.paint(*host.view, siteArgument(lua), box, rhythm, material, isIntoAirOnly);
        if (result == PaintResult.endless) {
            luaL_error(lua, "a placed structure paints bounded heights: give the box a z range");
        } else if (result == PaintResult.behind) {
            luaL_error(lua, "paints ground that is already built: a tile paints only near its face");
        }
    }
    return 0;
}

extern (C) int tileStop(lua_State* lua) {
    TileHost* host = tileHost(lua);
    ColumnSpot spot = spotArgument(lua, SELF + 1);
    if (!host.isReplaying) {
        host.painter.stop(*host.view, siteArgument(lua), spot, false);
    }
    return 0;
}

extern (C) int tileEntrance(lua_State* lua) {
    TileHost* host = tileHost(lua);
    ColumnSpot spot = spotArgument(lua, SELF + 1);
    if (!host.isReplaying) {
        host.painter.stop(*host.view, siteArgument(lua), spot, true);
    }
    return 0;
}

void refuseOutsideReplay(lua_State* lua, TileHost* host, const(char)* what) {
    if (!host.isReplaying) {
        luaL_error(lua, "a tile cannot %s: tiles run in any order, so decide from site:hash", what);
    }
}

extern (C) int tilePlace(lua_State* lua) {
    TileHost* host = tileHost(lua);
    luaL_checktype(lua, SELF + 1, LUA_TYPE_FUNCTION);
    refuseOutsideReplay(lua, host, "place");
    lua_pushboolean(lua, true);
    return 1;
}

extern (C) int tileClaim(lua_State* lua) {
    TileHost* host = tileHost(lua);
    refuseOutsideReplay(lua, host, "claim");
    lua_pushboolean(lua, true);
    return 1;
}

extern (C) int tileIsClaimed(lua_State* lua) {
    TileHost* host = tileHost(lua);
    refuseOutsideReplay(lua, host, "read claims");
    lua_pushboolean(lua, false);
    return 1;
}

extern (C) int tileTile(lua_State* lua) {
    TileHost* host = tileHost(lua);
    luaL_checktype(lua, SELF + 1, LUA_TYPE_FUNCTION);
    if (!host.isReplaying) {
        luaL_error(lua, "only the world's own structure tiles the ground, and only once");
    }
    host.planetTile = TileCall(packedCall(lua, SELF + 1), lua_gettop(lua) - SELF - PLACED_FUNCTION);
    host.hasPlanetTile = true;
    return 0;
}

extern (C) int tileSky(lua_State* lua) {
    TileHost* host = tileHost(lua);
    luaL_checktype(lua, SKY_TILE, LUA_TYPE_FUNCTION);
    if (!host.isReplaying) {
        luaL_error(lua, "only the world's own structure opens skies");
    }
    host.skyTiles.append(TileCall(packedCall(lua, SKY_TILE), lua_gettop(lua) - SKY_TILE));
    lua_pushinteger(lua, cast(lua_Integer) host.skyTiles.length);
    return 1;
}

extern (C) int tileOpenSky(lua_State* lua) {
    TileHost* host = tileHost(lua);
    if (!host.isReplaying) {
        luaL_error(lua, "only the world's own structure opens skies");
    }
    return 0;
}

extern (C) int tileBalance(lua_State* lua) {
    TileHost* host = tileHost(lua);
    lua_Integer most = luaL_checkinteger(lua, SELF + 1);
    if (host.sky == PLANET) {
        luaL_error(lua, "only a sky's tiles have another world to balance against");
    } else if (most < 1 || most > int.max) {
        luaL_error(lua, "balance looks at least one cell up");
    }
    lua_pushinteger(lua, (*host.view).balanceAlong((*host.view).turned(siteArgument(lua), Turn.pitchUp), host.sky, cast(int) most));
    return 1;
}

extern (C) int tileHash(lua_State* lua) {
    TileHost* host = tileHost(lua);
    lua_pushinteger(lua, cast(lua_Integer)(*host.view).siteHash(siteArgument(lua), partArgument(lua, SELF + 1)));
    return 1;
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

struct HostBuild {
    TileWork* work;
    size_t first;
}

void buildTileHost(void* context, size_t index, uint worker) {
    HostBuild* build = cast(HostBuild*) context;
    TileWork* work = build.work;
    TileHost* host = cast(TileHost*) calloc(1, TileHost.sizeof);
    *host = TileHost.init;
    host.build(&work.graph.threadViews[worker], work.name, work.root, work.seed);
    work.hosts.ptr[build.first + index] = host;
}

struct TaskOutput {
    uint host;
    uint output;
}

// Runs tiles on every thread at once: tasks are planned and made on the main thread, run in a parallel job that only
// reads the graph, and applied on the main thread in task order so a tile's brushes keep consecutive orders.
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
    Graph* graph;
    StructureWorld name;
    SiteFrame root;
    ulong seed;
    uint preparedTiles;
    uint fallbackTiles;
    bool hasFailed;
    char[MESSAGE_CAPACITY] failure;

    // Every thread that can run a job gets a host before the first tile, built in parallel since each one runs the
    // world's structure script.
    void ensureHosts(ref Graph target, Executor executor) {
        graph = &target;
        if (hosts.length < executor.workers) {
            HostBuild build = HostBuild(&this, hosts.length);
            hosts.resize(executor.workers);
            target.threadViews.begin(target, executor.workers);
            ParallelJob job = ParallelJob(&buildTileHost, &build, double.infinity, hosts.length - build.first);
            executor.run(&job);
            target.threadViews.finish(target);
            foreach (host; hosts.slice()) {
                if (host.hasFailed && !hasFailed) {
                    takeFailure(host);
                }
            }
        }
    }

    // Plans the cover of each candidate in parallel, makes tasks for the faces they need within the budget, and runs
    // them; candidates whose faces all got painted are marked covered. A candidate whose plan needed a world that did
    // not exist yet is planned again once this thread has made that world.
    void paintAhead(ref Graph target, const(uint)[] candidates, Executor executor) {
        ensureHosts(target, executor);
        covered.clear();
        planning.clear();
        planning.appendAll(candidates);
        bool isWorldMade = true;
        uint round = 0;
        while (planning.length > 0 && isWorldMade && round < PLAN_ROUNDS && tasks.length < TILE_TASK_BUDGET) {
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

    // Returns whether a world some plan stopped at was made, so planning it again can get further.
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

    // Returns false when a tile failed; the failure is kept for the structure's problem.
    bool runTasks(ref Graph target, Executor executor) {
        if (tasks.length > 0 && !hasFailed) {
            ensureHosts(target, executor);
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
        // Brushes keep the order they were painted in, but are stored a line at a time so each line gets one run.
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
