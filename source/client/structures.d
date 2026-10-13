module client.structures;

import core.stdc.math : asin, asinh, atan2, cos, cosh, sin, sinh, sqrt;
import core.stdc.stdio : snprintf;
import core.stdc.stdlib : free, malloc;
import core.stdc.string : memcpy, strlen;
import bindings.lua : luaL_checkinteger, luaL_checklstring, luaL_checknumber, luaL_checktype, luaL_checkudata, luaL_error, luaL_loadbufferx, luaL_loadfilex, luaL_newmetatable, luaL_ref, luaL_setmetatable, luaL_testudata, luaL_unref, lua_CFunction, lua_Integer, lua_State, lua_close, lua_createtable, lua_getfield, lua_getglobal, lua_gettop, lua_newuserdatauv, lua_pcallk, lua_pushboolean, lua_pushcclosure, lua_pushinteger, lua_pushlightuserdata, lua_pushnumber, lua_pushvalue, lua_rawgeti, lua_rawseti, lua_setfield, lua_settop, lua_tointegerx, lua_tolstring, lua_touserdata, lua_type;
import client.game : Game;
import client.lua : LUA_BELOW_TOP, LUA_FIRST_UPVALUE, LUA_NO_REF, LUA_REGISTRY, LUA_SECOND_UPVALUE, LUA_STATUS_OK, LUA_TOP, LUA_TYPE_FUNCTION, LUA_TYPE_TABLE, LuaLookup, LuaName, SELF, TRACEBACK_INDEX, isNoneOrNil, luaTraceback, newSafeState, registerMethod, setPackagePath;
import base.array : Array;
import base.names : ENUM_NAMES;
import base.parallel : Executor;
import client.tiles : TileWork;
import common.graph : Graph;
import common.material : Material;
import common.worldgen.store : Grower;
import common.worldgen.blueprint : BlueprintBuilder, CellBox, EVERY_HEIGHT, PaintResult, Rhythm, TileRecord;
import common.worldgen.embedded : EMBEDDED_MODULES, EMBEDDED_STRUCTURES, EmbeddedLua, embeddedIndex, isLuaPath;
import common.worldgen.generation : STRUCTURE_NAME_CAPACITY, SplitMix, StructureWorld, Worldgen;
import common.worldgen.plane : Plane;
import common.worldgen.sky : LOWEST_SKY_EDGES, PLANET, SkyChoice, SkyGround, SkyKind, Skies, World, balanceAlong, ensureWorldsAt, isPaintedBySky, measuredWorld, openSky, worldGroundNodeOf;
import common.worldgen.strokes : Stroke;
import common.worldgen.structure : ClaimKey, ColumnSpot, GROUND_RING, PLACE_SLACK, RootedCorner, SiteFrame, SitePart, Turn, anchorBits, claimKeyOf, edgeCells, edgeLength, faceSite, forwarded, groundRing, rootSite, siteHash, siteOrigin, sitePlacement, turned;
import geometry.honeycomb : Face;
import geometry.lorentz : Motion, Vec4;

enum size_t MESSAGE_CAPACITY = 1024;
enum int CHUNK_RESULTS = 1;
enum int STRUCTURE_ARGUMENTS = 1;
enum int DEFAULT_SPAN = 1;
enum int COLUMN_RESULTS = 2;
enum int TURN_UPVALUES = 2;
enum int PLACED_FUNCTION = 1;
enum int SKY_TILE = SELF + 3;
enum int SKY_FIELDS = 5;
enum string SITE_TYPE = "mined.site";
enum string PEN_TYPE = "mined.pen";
enum string AIR = "air";
enum double RADIANS_PER_DEGREE = 0.017453292519943295;
enum double HALF_TURN = 3.141592653589793;
enum double VERTICAL_TOLERANCE = 1e-9;
enum uint RANDOM_DISCARDED_BITS = 11;
enum double RANDOM_UNIT = 1.0 / (1UL << 53);
enum size_t ACROSS = 0;
enum size_t UP = 1;
enum size_t AHEAD = 2;

struct Pen {
    Motion!double frame;
    Vec4!double ground;
    uint node;

    double[3] up() const {
        Vec4!double local = frame.inverse() * ground;
        double length = sqrt(local.c[0] * local.c[0] + local.c[1] * local.c[1] + local.c[2] * local.c[2]);
        return [local.c[0] / length, local.c[1] / length, local.c[2] / length];
    }

    Pen moved(double distance) const {
        return Pen((frame * Motion!double.shift([0, 0, distance])).orthonormalized(), ground, node);
    }

    Pen turned(double[3] from, double[3] toward, double degrees) const {
        return Pen(frame * planeRotation(from, toward, degrees * RADIANS_PER_DEGREE), ground, node);
    }

    Pen lifted(double degrees) const {
        double[3] rising = up();
        double side = sqrt(rising[0] * rising[0] + rising[1] * rising[1]);
        if (side < VERTICAL_TOLERANCE) {
            return this;
        } else {
            double toUp = atan2(side, rising[AHEAD]);
            double angle = degrees * RADIANS_PER_DEGREE;
            if (angle > toUp) {
                angle = toUp;
            } else if (angle < toUp - HALF_TURN) {
                angle = toUp - HALF_TURN;
            }
            return Pen(frame * planeRotation(axisOf(AHEAD), [rising[0] / side, rising[1] / side, 0], angle), ground, node);
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
    uint key;
    int reference;
    int argumentCount;
}

struct TileCall {
    int reference;
    int argumentCount;
}

struct StructureHost {
    BlueprintBuilder builder;
    Array!(Array!QueuedStructure) queue;
    Array!TileCall skyTiles;
    TileWork tiles;
    Executor executor;
    SplitMix random;
    lua_State* lua;
    StructureWorld name;
    uint key;
    uint nextKey;
    int tileReference;
    int tileArgumentCount;
    StructureProblem problem;

    static StructureHost make(ref Graph graph) {
        StructureHost host;
        host.builder = BlueprintBuilder.make(graph);
        host.random = SplitMix(graph.anchorBits(graph.anchorSlot));
        host.name = StructureWorld.fromName(graph.worldgen.structureName());
        host.tileReference = LUA_NO_REF;
        host.tiles.name = host.name;
        host.tiles.root = rootSite(graph.anchorSlot);
        host.tiles.seed = graph.anchorBits(graph.anchorSlot);
        return host;
    }

    bool hasTile() const {
        return tileReference != LUA_NO_REF;
    }

    bool hasCover() const {
        return hasTile() || skyTiles.length > 0;
    }

    void build(SiteFrame root) {
        lua = newSafeState();
        registerModules(lua);
        registerSiteType();
        registerPenType();
        lua_pushcclosure(lua, cast(lua_CFunction) &luaTraceback, 0);
        immutable int status = loadStructureChunk(lua, name.name());
        if (status != LUA_STATUS_OK) {
            fail();
        } else {
            runChunk(root);
        }
        lua_settop(lua, TRACEBACK_INDEX);
    }

    void runChunk(SiteFrame root) {
        immutable int status = lua_pcallk(lua, 0, CHUNK_RESULTS, TRACEBACK_INDEX, 0, null);
        if (status != LUA_STATUS_OK) {
            fail();
        } else if (lua_type(lua, LUA_TOP) != LUA_TYPE_FUNCTION) {
            problem = StructureProblem.fromMessage(name.name(), "does not return a function of a site");
        } else {
            lua.pushSite(root);
            immutable int built = lua_pcallk(lua, STRUCTURE_ARGUMENTS, 0, TRACEBACK_INDEX, 0, null);
            if (built != LUA_STATUS_OK) {
                fail();
            }
        }
    }

    void fail() {
        problem = StructureProblem.fromMessage(name.name(), lua_tolstring(lua, LUA_TOP, null));
    }

    void grow(ref Graph graph, int through) {
        builder.graph = &graph;
        while (!problem.isPresent && hasQueued() && cast(int) nextKey <= through) {
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
        immutable int reference = queued.reference;
        call(reference, queued.argumentCount, queued.site);
        luaL_unref(lua, LUA_REGISTRY, reference);
    }

    void call(int reference, int argumentCount, SiteFrame site) {
        lua_rawgeti(lua, LUA_REGISTRY, reference);
        int placed = lua_gettop(lua);
        lua_rawgeti(lua, placed, PLACED_FUNCTION);
        lua.pushSite(site);
        foreach (index; 0 .. argumentCount) {
            lua_rawgeti(lua, placed, PLACED_FUNCTION + 1 + index);
        }
        immutable int status = lua_pcallk(lua, STRUCTURE_ARGUMENTS + argumentCount, 0, TRACEBACK_INDEX, 0, null);
        if (status != LUA_STATUS_OK) {
            fail();
        }
        lua_settop(lua, TRACEBACK_INDEX);
    }

    void cover(ref Graph graph, uint slot) {
        builder.graph = &graph;
        if (!problem.isPresent && hasCover()) {
            if (hasTile()) {
                coverRing(graph, graph.view.groundRing(graph.view.worldGroundNodeOf(slot, PLANET), Face.f0), Face.f0, PLANET);
            }
            foreach (sky; graph.view.ensureWorldsAt(slot)) {
                if (graph.view.isPaintedBySky(slot, sky)) {
                    Face label = graph.skies.world(sky.world).label;
                    coverRing(graph, graph.view.groundRing(graph.view.worldGroundNodeOf(slot, sky.world), label), label, sky.world);
                }
            }
            runTiles(graph);
        }
    }

    void coverRing(ref Graph graph, uint[GROUND_RING] ring, Face label, uint sky) {
        foreach (face; ring) {
            const(uint)* known = graph.structures.tiledFaces.find(graph.idAt(face));
            if (known !is null && !graph.structures.blueprint.tiles.ptr[*known].isDropped) {
                graph.structures.blueprint.tiles.ptr[*known].lastUse = graph.structures.blueprint.travel;
            } else {
                tiles.addTask(graph, graph.idAt(face), face, null, label, sky);
            }
        }
    }

    void runTiles(ref Graph graph) {
        tiles.fallbackTiles += cast(uint) tiles.tasks.length;
        if (!tiles.runTasks(graph, executor)) {
            problem = StructureProblem.fromMessage(name.name(), tiles.failure.ptr);
        }
    }

    void paintAhead(ref Graph graph, const(uint)[] candidates, Executor chosen) {
        executor = chosen;
        builder.graph = &graph;
        if (!problem.isPresent && hasCover()) {
            tiles.paintAhead(graph, candidates, executor);
            if (tiles.hasFailed) {
                problem = StructureProblem.fromMessage(name.name(), tiles.failure.ptr);
            }
        }
    }

    void referenceArguments(int reference, int argumentCount, ref Array!uint held) {
        lua_rawgeti(lua, LUA_REGISTRY, reference);
        int placed = lua_gettop(lua);
        foreach (index; 0 .. argumentCount) {
            lua_rawgeti(lua, placed, PLACED_FUNCTION + 1 + index);
            const(SiteFrame)* site = cast(const(SiteFrame)*) luaL_testudata(lua, LUA_TOP, SITE_TYPE.ptr);
            if (site !is null && builder.graph.isLive(site.node)) {
                builder.graph.reference(site.node);
                held.append(site.node);
            }
            lua_settop(lua, placed);
        }
        lua_settop(lua, placed - 1);
    }

    void enqueue(QueuedStructure queued) {
        while (queue.length <= queued.key) {
            queue.append(Array!QueuedStructure.init);
        }
        builder.graph.reference(queued.site.node);
        queued.held.append(queued.site.node);
        referenceArguments(queued.reference, queued.argumentCount, queued.held);
        queue.ptr[queued.key].append(queued);
    }

    void keepTile(TileCall tile) {
        Array!uint held;
        referenceArguments(tile.reference, tile.argumentCount, held);
        held.release();
    }

    bool hasQueued() const {
        return nextKey < queue.length;
    }

    void registerSiteType() {
        luaL_newmetatable(lua, SITE_TYPE.ptr);
        lua_createtable(lua, 0, 0);
        lua.registerMethod(&this, "forward", &luaSiteForward);
        registerTurns();
        lua.registerMethod(&this, "column", &luaSiteColumn);
        lua.registerMethod(&this, "edge_cells", &luaSiteEdgeCells);
        lua.registerMethod(&this, "pick", &luaSitePick);
        lua.registerMethod(&this, "paint", &luaSitePaint);
        lua.registerMethod(&this, "fill", &luaSiteFill);
        lua.registerMethod(&this, "stop", &luaSiteStop);
        lua.registerMethod(&this, "entrance", &luaSiteEntrance);
        lua.registerMethod(&this, "place", &luaSitePlace);
        lua.registerMethod(&this, "claim", &luaSiteClaim);
        lua.registerMethod(&this, "is_claimed", &luaSiteIsClaimed);
        lua.registerMethod(&this, "tile", &luaSiteTile);
        lua.registerMethod(&this, "sky", &luaSiteSky);
        lua.registerMethod(&this, "open_sky", &luaSiteOpenSky);
        lua.registerMethod(&this, "balance", &luaSiteBalance);
        lua.registerMethod(&this, "hash", &luaSiteHash);
        lua.registerMethod(&this, "pen", &luaSitePen);
        lua_setfield(lua, LUA_BELOW_TOP, "__index");
        lua_settop(lua, LUA_BELOW_TOP);
    }

    void registerPenType() {
        luaL_newmetatable(lua, PEN_TYPE.ptr);
        lua_createtable(lua, 0, 0);
        lua.registerMethod(&this, "forward", &luaPenForward);
        lua.registerMethod(&this, "turn", &luaPenTurn);
        lua.registerMethod(&this, "roll", &luaPenRoll);
        lua.registerMethod(&this, "lift", &luaPenLift);
        lua.registerMethod(&this, "rise", &luaPenRise);
        lua.registerMethod(&this, "height", &luaPenHeight);
        lua.registerMethod(&this, "limb", &luaPenLimb);
        lua.registerMethod(&this, "leaves", &luaPenLeaves);
        lua.registerMethod(&this, "random", &luaPenRandom);
        lua_setfield(lua, LUA_BELOW_TOP, "__index");
        lua_settop(lua, LUA_BELOW_TOP);
    }

    double cellLength() const {
        return edgeLength(builder.graph.layout).value / edgeCells(dimension());
    }

    void draw(Pen pen, double cells, double fromRadius, double toRadius, Material material, bool isLeafy) {
        Graph* graph = builder.graph;
        double cell = cellLength();
        graph.structures.strokes.add(graph.view, pen.node, Stroke.make(pen.frame, cells * cell, cast(float)(fromRadius * cell), cast(float)(toRadius * cell), material, isLeafy));
    }

    void registerTurns() {
        foreach (index, member; ENUM_NAMES!Turn) {
            LuaName turnName = LuaName.fromMember(member);
            turnName.text[turnName.length] = 0;
            lua_pushlightuserdata(lua, &this);
            lua_pushinteger(lua, cast(lua_Integer) index);
            lua_pushcclosure(lua, cast(lua_CFunction) &luaSiteTurn, TURN_UPVALUES);
            lua_setfield(lua, LUA_BELOW_TOP, turnName.text.ptr);
        }
    }

    ubyte dimension() const {
        return builder.graph.layout.dimension;
    }

    void release() {
        if (lua !is null) {
            lua_close(lua);
        }
        foreach (ref bucket; queue.slice()) {
            foreach (ref queued; bucket.slice()) {
                queued.held.release();
            }
            bucket.release();
        }
        queue.release();
        skyTiles.release();
        tiles.release();
        builder.release();
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
        if (problem.isPresent || !(host.hasQueued() || host.hasCover())) {
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

void registerModules(lua_State* lua) {
    lua_getglobal(lua, "package");
    lua_getfield(lua, LUA_TOP, "preload");
    lua.preloadAll(EMBEDDED_MODULES[]);
    lua.preloadAll(EMBEDDED_STRUCTURES[]);
    lua_settop(lua, -3);
}

void preloadAll(lua_State* lua, const(EmbeddedLua)[] modules) {
    foreach (embedded; modules) {
        luaL_loadbufferx(lua, embedded.source.ptr, embedded.source.length, embedded.name.ptr, null);
        lua_setfield(lua, LUA_BELOW_TOP, embedded.name.ptr);
    }
}

int loadStructureChunk(lua_State* lua, const(char)[] name) {
    if (isLuaPath(name)) {
        char[STRUCTURE_NAME_CAPACITY + 1] path = 0;
        memcpy(path.ptr, name.ptr, name.length);
        lua.setPackagePath(name);
        return luaL_loadfilex(lua, path.ptr, null);
    } else {
        EmbeddedLua embedded = EMBEDDED_STRUCTURES[embeddedIndex(name)];
        return luaL_loadbufferx(lua, embedded.source.ptr, embedded.source.length, embedded.name.ptr, null);
    }
}

StructureHost* structureHost(lua_State* lua) {
    luaL_checkudata(lua, SELF, SITE_TYPE.ptr);
    return cast(StructureHost*) lua_touserdata(lua, LUA_FIRST_UPVALUE);
}

int integerAt(lua_State* lua, int index, const(char)* what) {
    int isNumber = 0;
    lua_Integer value = lua_tointegerx(lua, index, &isNumber);
    if (isNumber == 0) {
        luaL_error(lua, "%s must be an integer", what);
    }
    return cast(int) value;
}

int integerField(lua_State* lua, int table, const(char)* name, int fallback) {
    lua_getfield(lua, table, name);
    int value = fallback;
    if (!isNoneOrNil(lua, LUA_TOP)) {
        value = integerAt(lua, LUA_TOP, name);
    }
    lua_settop(lua, LUA_BELOW_TOP);
    return value;
}

int requiredField(lua_State* lua, int table, const(char)* name) {
    lua_getfield(lua, table, name);
    if (isNoneOrNil(lua, LUA_TOP)) {
        luaL_error(lua, "missing %s", name);
    }
    int value = integerAt(lua, LUA_TOP, name);
    lua_settop(lua, LUA_BELOW_TOP);
    return value;
}

int[2] rangeField(lua_State* lua, int table, const(char)* name, int[2] whole) {
    int[2] range = whole;
    lua_getfield(lua, table, name);
    if (!isNoneOrNil(lua, LUA_TOP)) {
        int pair = lua_gettop(lua);
        if (lua_type(lua, pair) != LUA_TYPE_TABLE) {
            luaL_error(lua, "%s must be {low, high}", name);
        }
        lua_rawgeti(lua, pair, 1);
        range[0] = integerAt(lua, LUA_TOP, name);
        lua_rawgeti(lua, pair, 2);
        range[1] = integerAt(lua, LUA_TOP, name);
        if (range[0] > range[1]) {
            luaL_error(lua, "%s runs from %d down to %d", name, range[0], range[1]);
        }
        if (range[0] < whole[0] || range[1] > whole[1]) {
            luaL_error(lua, "%s {%d, %d} leaves the site's column {%d, %d}", name, range[0], range[1], whole[0], whole[1]);
        }
        lua_settop(lua, pair);
    }
    lua_settop(lua, LUA_BELOW_TOP);
    return range;
}

int[2] columnOf(ubyte dimension) {
    return [-cast(int) dimension, dimension - 1];
}

CellBox boxArgument(lua_State* lua, int index, ubyte dimension) {
    luaL_checktype(lua, index, LUA_TYPE_TABLE);
    int[2] x = rangeField(lua, index, "x", columnOf(dimension));
    int[2] y = rangeField(lua, index, "y", columnOf(dimension));
    int[2] z = rangeField(lua, index, "z", [int.min, int.max]);
    return CellBox.make(x[0], x[1], y[0], y[1], z[0], z[1]);
}

Rhythm rhythmArgument(lua_State* lua, int index) {
    if (isNoneOrNil(lua, index)) {
        return EVERY_HEIGHT;
    } else {
        luaL_checktype(lua, index, LUA_TYPE_TABLE);
        Rhythm rhythm = Rhythm(requiredField(lua, index, "every"), integerField(lua, index, "from", 0), integerField(lua, index, "span", DEFAULT_SPAN));
        if (rhythm.period <= 0 || rhythm.span <= 0) {
            luaL_error(lua, "a rhythm needs a positive every and span");
        }
        return rhythm;
    }
}

Material materialArgument(lua_State* lua, int index) {
    const(char)* text = luaL_checklstring(lua, index, null);
    const(char)[] name = text[0 .. strlen(text)];
    LuaLookup!Material lookup = LuaLookup!Material.fromName(name);
    if (name == AIR) {
        return Material.none;
    } else if (!lookup.isFound || lookup.value == Material.none) {
        luaL_error(lua, "unknown material '%s'", text);
        return Material.none;
    } else {
        return lookup.value;
    }
}

void pushSite(lua_State* lua, SiteFrame site) {
    *cast(SiteFrame*) lua_newuserdatauv(lua, SiteFrame.sizeof, 0) = site;
    luaL_setmetatable(lua, SITE_TYPE.ptr);
}

SiteFrame siteArgument(lua_State* lua) {
    return *cast(const(SiteFrame)*) luaL_checkudata(lua, SELF, SITE_TYPE.ptr);
}

ColumnSpot spotArgument(lua_State* lua, int first) {
    return ColumnSpot(cast(float) luaL_checknumber(lua, first), cast(float) luaL_checknumber(lua, first + 1), cast(float) luaL_checknumber(lua, first + 2));
}

extern (C) int luaSiteForward(lua_State* lua) {
    structureHost(lua);
    lua.pushSite(forwarded(siteArgument(lua), cast(int) luaL_checkinteger(lua, SELF + 1)));
    return 1;
}

extern (C) int luaSiteTurn(lua_State* lua) {
    StructureHost* host = structureHost(lua);
    Turn turn = cast(Turn) lua_tointegerx(lua, LUA_SECOND_UPVALUE, null);
    lua.pushSite(host.builder.graph.view.turned(siteArgument(lua), turn));
    return 1;
}

extern (C) int luaSiteColumn(lua_State* lua) {
    int[2] column = columnOf(structureHost(lua).dimension());
    lua_pushinteger(lua, column[0]);
    lua_pushinteger(lua, column[1]);
    return COLUMN_RESULTS;
}

extern (C) int luaSiteEdgeCells(lua_State* lua) {
    lua_pushinteger(lua, edgeCells(structureHost(lua).dimension()));
    return 1;
}

extern (C) int luaSitePick(lua_State* lua) {
    StructureHost* host = structureHost(lua);
    lua_Integer count = luaL_checkinteger(lua, SELF + 1);
    if (count < 1) {
        luaL_error(lua, "pick needs at least one choice");
    }
    lua_pushinteger(lua, cast(lua_Integer)(host.random.next() % cast(ulong) count) + 1);
    return 1;
}

extern (C) int luaSitePaint(lua_State* lua) {
    return lua.paintWith(false);
}

extern (C) int luaSiteFill(lua_State* lua) {
    return lua.paintWith(true);
}

int paintWith(lua_State* lua, bool isIntoAirOnly) {
    StructureHost* host = structureHost(lua);
    Material material = materialArgument(lua, SELF + 1);
    CellBox box = boxArgument(lua, SELF + 2, host.dimension());
    PaintResult result = host.builder.paint(siteArgument(lua), box, rhythmArgument(lua, SELF + 3), material, isIntoAirOnly);
    if (result == PaintResult.endless) {
        luaL_error(lua, "a placed structure paints bounded heights: give the box a z range");
    } else if (result == PaintResult.behind) {
        luaL_error(lua, "paints too far behind its site: a placed structure stays near where it was placed");
    }
    return 0;
}

extern (C) int luaSiteStop(lua_State* lua) {
    structureHost(lua).builder.stop(siteArgument(lua), spotArgument(lua, SELF + 1));
    return 0;
}

extern (C) int luaSiteEntrance(lua_State* lua) {
    structureHost(lua).builder.enter(siteArgument(lua), spotArgument(lua, SELF + 1));
    return 0;
}

int packedCall(lua_State* lua, int first) {
    int count = lua_gettop(lua) - first + 1;
    lua_createtable(lua, count, 0);
    foreach (index; 0 .. count) {
        lua_pushvalue(lua, first + index);
        lua_rawseti(lua, LUA_BELOW_TOP, PLACED_FUNCTION + index);
    }
    return luaL_ref(lua, LUA_REGISTRY);
}

extern (C) int luaSitePlace(lua_State* lua) {
    StructureHost* host = structureHost(lua);
    SiteFrame site = siteArgument(lua);
    luaL_checktype(lua, SELF + 1, LUA_TYPE_FUNCTION);
    RootedCorner origin = host.builder.graph.view.siteOrigin(site);
    bool isAhead = cast(int) origin.depth + PLACE_SLACK >= cast(int) host.key;
    if (isAhead) {
        int count = lua_gettop(lua) - SELF;
        uint queuedKey = host.key;
        if (origin.depth > queuedKey) {
            queuedKey = origin.depth;
        }
        host.enqueue(QueuedStructure(site, Array!uint.init, queuedKey, packedCall(lua, SELF + 1), count - PLACED_FUNCTION));
    }
    lua_pushboolean(lua, isAhead);
    return 1;
}

extern (C) int luaSiteTile(lua_State* lua) {
    StructureHost* host = structureHost(lua);
    luaL_checktype(lua, SELF + 1, LUA_TYPE_FUNCTION);
    if (host.builder.isGrowing || host.hasTile()) {
        luaL_error(lua, "only the world's own structure tiles the ground, and only once");
    }
    host.tileArgumentCount = lua_gettop(lua) - SELF - PLACED_FUNCTION;
    host.tileReference = packedCall(lua, SELF + 1);
    host.keepTile(TileCall(host.tileReference, host.tileArgumentCount));
    return 0;
}

extern (C) int luaSiteSky(lua_State* lua) {
    StructureHost* host = structureHost(lua);
    double odds = luaL_checknumber(lua, SELF + 1);
    const(char)* ground = luaL_checklstring(lua, SELF + 2, null);
    LuaLookup!SkyGround lookup = LuaLookup!SkyGround.fromName(ground[0 .. strlen(ground)]);
    luaL_checktype(lua, SKY_TILE, LUA_TYPE_FUNCTION);
    Skies* skies = &host.builder.graph.skies;
    if (host.builder.isGrowing) {
        luaL_error(lua, "only the world's own structure opens skies");
    } else if (!lookup.isFound) {
        luaL_error(lua, "a sky's ground is terrain or flat, not '%s'", ground);
    } else if (!(odds >= 0) || skies.totalOdds() + odds > 1) {
        luaL_error(lua, "sky odds are chances per ground vertex, and all kinds together add up to at most 1");
    }
    skies.kinds.append(SkyKind(odds, lookup.value));
    host.skyTiles.append(TileCall(packedCall(lua, SKY_TILE), lua_gettop(lua) - SKY_TILE));
    host.keepTile(host.skyTiles.ptr[host.skyTiles.length - 1]);
    lua_pushinteger(lua, cast(lua_Integer) skies.kinds.length);
    return 1;
}

extern (C) int luaSiteOpenSky(lua_State* lua) {
    StructureHost* host = structureHost(lua);
    SiteFrame site = siteArgument(lua);
    lua_Integer kind = luaL_checkinteger(lua, SELF + 1);
    lua_Integer edges = LOWEST_SKY_EDGES;
    if (!isNoneOrNil(lua, SELF + 2)) {
        edges = luaL_checkinteger(lua, SELF + 2);
    }
    if (host.builder.isGrowing) {
        luaL_error(lua, "only the world's own structure opens skies");
    } else if (kind < 1 || kind > cast(lua_Integer) host.builder.graph.skies.kinds.length) {
        luaL_error(lua, "unknown sky kind %d", cast(int) kind);
    } else if (edges < LOWEST_SKY_EDGES || edges > ubyte.max) {
        luaL_error(lua, "a sky stands at least %d edges up", cast(int) LOWEST_SKY_EDGES);
    } else {
        immutable bool isOpened = (*host.builder.graph).openSky(site, SkyChoice(cast(ubyte) kind, cast(ubyte) edges));
        if (!isOpened) {
            luaL_error(lua, "a sky beside another sky would cross it");
        }
    }
    return 0;
}

extern (C) int luaSiteBalance(lua_State* lua) {
    structureHost(lua);
    luaL_checkinteger(lua, SELF + 1);
    luaL_error(lua, "only a sky's tiles have another world to balance against");
    return 0;
}

extern (C) int luaSiteClaim(lua_State* lua) {
    StructureHost* host = structureHost(lua);
    ClaimKey key = claimArgument(lua, *host.builder.graph);
    immutable bool isNewlyClaimed = host.builder.claim(key);
    lua_pushboolean(lua, isNewlyClaimed);
    return 1;
}

extern (C) int luaSiteIsClaimed(lua_State* lua) {
    StructureHost* host = structureHost(lua);
    lua_pushboolean(lua, host.builder.blueprint.isClaimed(claimArgument(lua, *host.builder.graph)));
    return 1;
}

extern (C) int luaSiteHash(lua_State* lua) {
    StructureHost* host = structureHost(lua);
    lua_pushinteger(lua, cast(lua_Integer) host.builder.graph.view.siteHash(siteArgument(lua), partArgument(lua, SELF + 1)));
    return 1;
}

extern (C) int luaSitePen(lua_State* lua) {
    StructureHost* host = structureHost(lua);
    SiteFrame site = siteArgument(lua);
    Graph* graph = host.builder.graph;
    lua.pushPen(Pen(sitePlacement(site, graph.layout).as!double(), unitNormal(graph.ensureState(site.node).surface), site.node));
    return 1;
}

void pushPen(lua_State* lua, Pen pen) {
    *cast(Pen*) lua_newuserdatauv(lua, Pen.sizeof, 0) = pen;
    luaL_setmetatable(lua, PEN_TYPE.ptr);
}

StructureHost* penHost(lua_State* lua) {
    luaL_checkudata(lua, SELF, PEN_TYPE.ptr);
    return cast(StructureHost*) lua_touserdata(lua, LUA_FIRST_UPVALUE);
}

Pen penArgument(lua_State* lua) {
    return *cast(const(Pen)*) luaL_checkudata(lua, SELF, PEN_TYPE.ptr);
}

extern (C) int luaPenForward(lua_State* lua) {
    StructureHost* host = penHost(lua);
    Pen pen = penArgument(lua);
    lua.pushPen(pen.moved(luaL_checknumber(lua, SELF + 1) * host.cellLength()));
    return 1;
}

extern (C) int luaPenTurn(lua_State* lua) {
    penHost(lua);
    Pen pen = penArgument(lua);
    double yaw = luaL_checknumber(lua, SELF + 1);
    double pitch = luaL_checknumber(lua, SELF + 2);
    lua.pushPen(pen.turned(axisOf(AHEAD), axisOf(ACROSS), yaw).turned(axisOf(AHEAD), axisOf(UP), pitch));
    return 1;
}

extern (C) int luaPenRoll(lua_State* lua) {
    penHost(lua);
    lua.pushPen(penArgument(lua).turned(axisOf(ACROSS), axisOf(UP), luaL_checknumber(lua, SELF + 1)));
    return 1;
}

extern (C) int luaPenLift(lua_State* lua) {
    penHost(lua);
    lua.pushPen(penArgument(lua).lifted(luaL_checknumber(lua, SELF + 1)));
    return 1;
}

extern (C) int luaPenRise(lua_State* lua) {
    penHost(lua);
    lua_pushnumber(lua, asin(penArgument(lua).up()[AHEAD]) / RADIANS_PER_DEGREE);
    return 1;
}

extern (C) int luaPenHeight(lua_State* lua) {
    StructureHost* host = penHost(lua);
    Pen pen = penArgument(lua);
    lua_pushnumber(lua, asinh(pen.ground.minkowski(pen.frame.m.column(3))) / host.cellLength());
    return 1;
}

extern (C) int luaPenLimb(lua_State* lua) {
    StructureHost* host = penHost(lua);
    Pen pen = penArgument(lua);
    Material material = materialArgument(lua, SELF + 1);
    double cells = luaL_checknumber(lua, SELF + 2);
    double fromRadius = luaL_checknumber(lua, SELF + 3);
    double toRadius = luaL_checknumber(lua, SELF + 4);
    host.drawWith(lua, pen, cells, fromRadius, toRadius, material, false);
    lua.pushPen(pen.moved(cells * host.cellLength()));
    return 1;
}

extern (C) int luaPenLeaves(lua_State* lua) {
    StructureHost* host = penHost(lua);
    Pen pen = penArgument(lua);
    Material material = materialArgument(lua, SELF + 1);
    double radius = luaL_checknumber(lua, SELF + 2);
    host.drawWith(lua, pen, 0, radius, radius, material, true);
    return 0;
}

extern (C) int luaPenRandom(lua_State* lua) {
    lua_pushnumber(lua, (penHost(lua).random.next() >> RANDOM_DISCARDED_BITS) * RANDOM_UNIT);
    return 1;
}

void drawWith(StructureHost* host, lua_State* lua, Pen pen, double cells, double fromRadius, double toRadius, Material material, bool isLeafy) {
    if (host.builder.isGrowing) {
        luaL_error(lua, "only the world's own structure draws with a pen");
    } else if (!(cells >= 0) || !(fromRadius > 0) || !(toRadius > 0)) {
        luaL_error(lua, "a pen draws a length of at least zero with radii above zero");
    }
    host.draw(pen, cells, fromRadius, toRadius, material, isLeafy);
}

SitePart partArgument(lua_State* lua, int index) {
    if (isNoneOrNil(lua, index)) {
        return SitePart.vertex;
    } else {
        const(char)* text = luaL_checklstring(lua, index, null);
        LuaLookup!SitePart lookup = LuaLookup!SitePart.fromName(text[0 .. strlen(text)]);
        if (!lookup.isFound) {
            luaL_error(lua, "a site part is a vertex, face or edge, not '%s'", text);
        }
        return lookup.value;
    }
}

ClaimKey claimArgument(lua_State* lua, ref Graph graph) {
    SitePart part = partArgument(lua, SELF + 1);
    if (part == SitePart.edge) {
        luaL_error(lua, "a site claims its vertex or face, not its edge");
    }
    return graph.view.claimKeyOf(siteArgument(lua), part);
}
