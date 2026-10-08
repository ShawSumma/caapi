module client.structures;

import core.stdc.stdio : snprintf;
import core.stdc.string : memcpy, strlen;
import bindings.lua : luaL_checkinteger, luaL_checklstring, luaL_checknumber, luaL_checktype, luaL_error, luaL_loadbufferx, luaL_loadfilex, luaL_newmetatable, luaL_setmetatable, lua_CFunction, lua_Integer, lua_State, lua_close, lua_createtable, lua_getfield, lua_getglobal, lua_gettop, lua_pcallk, lua_pushcclosure, lua_pushinteger, lua_rawgeti, lua_rawseti, lua_setfield, lua_settop, lua_tointegerx, lua_tolstring, lua_touserdata, lua_type;
import client.game : Game;
import client.lua : LUA_BELOW_TOP, LUA_FIRST_UPVALUE, LUA_STATUS_OK, LUA_TOP, LUA_TYPE_FUNCTION, LUA_TYPE_TABLE, LuaLookup, SELF, TRACEBACK_INDEX, isNoneOrNil, luaTraceback, newSafeState, registerMethod, setPackagePath;
import common.dodeca : SIDE_COUNT, Side, VERTEX_COUNT, Vertex;
import common.graph : Graph;
import common.material : Material;
import common.worldgen.blueprint : BlueprintBuilder, CellBox, EVERY_HEIGHT, Rhythm;
import common.worldgen.embedded : EMBEDDED_MODULES, EMBEDDED_STRUCTURES, EmbeddedLua, embeddedIndex, isLuaPath;
import common.worldgen.generation : STRUCTURE_NAME_CAPACITY, SplitMix, Worldgen;
import common.worldgen.structure : ColumnSpot, FACE_CORNERS, SiteFrame, anchorBits, branched, edgeCells, faceCorners, rootSite, shifted, sideAxis, turned;

enum size_t MESSAGE_CAPACITY = 1024;
enum int CHUNK_RESULTS = 1;
enum int STRUCTURE_ARGUMENTS = 1;
enum int SITE_FIELDS = 8;
enum int DEFAULT_SPAN = 1;
enum int COLUMN_RESULTS = 2;
enum string SITE_TYPE = "mined.site";
enum string AIR = "air";

enum BranchAxis : ubyte {
    across,
    along,
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

struct StructureHost {
    BlueprintBuilder builder;
    SplitMix random;

    StructureProblem build(const(char)[] name, SiteFrame root) {
        lua_State* lua = newSafeState();
        registerModules(lua);
        registerSiteType(lua);
        lua_pushcclosure(lua, cast(lua_CFunction) &luaTraceback, 0);
        immutable int status = loadStructureChunk(lua, name);
        StructureProblem problem = void;
        if (status != LUA_STATUS_OK) {
            problem = StructureProblem.fromMessage(name, lua_tolstring(lua, LUA_TOP, null));
        } else {
            problem = runChunk(lua, name, root);
        }
        lua_close(lua);
        return problem;
    }

    StructureProblem runChunk(lua_State* lua, const(char)[] name, SiteFrame root) {
        immutable int status = lua_pcallk(lua, 0, CHUNK_RESULTS, TRACEBACK_INDEX, 0, null);
        if (status != LUA_STATUS_OK) {
            return StructureProblem.fromMessage(name, lua_tolstring(lua, LUA_TOP, null));
        } else if (lua_type(lua, LUA_TOP) != LUA_TYPE_FUNCTION) {
            return StructureProblem.fromMessage(name, "does not return a function of a site");
        } else {
            lua.pushSite(root);
            immutable int built = lua_pcallk(lua, STRUCTURE_ARGUMENTS, 0, TRACEBACK_INDEX, 0, null);
            if (built != LUA_STATUS_OK) {
                return StructureProblem.fromMessage(name, lua_tolstring(lua, LUA_TOP, null));
            } else {
                return StructureProblem.init;
            }
        }
    }

    void registerSiteType(lua_State* lua) {
        luaL_newmetatable(lua, SITE_TYPE.ptr);
        lua_createtable(lua, 0, 0);
        lua.registerMethod(&this, "up", &luaSiteUp);
        lua.registerMethod(&this, "turn", &luaSiteTurn);
        lua.registerMethod(&this, "branch", &luaSiteBranch);
        lua.registerMethod(&this, "face", &luaSiteFace);
        lua.registerMethod(&this, "column", &luaSiteColumn);
        lua.registerMethod(&this, "edge_cells", &luaSiteEdgeCells);
        lua.registerMethod(&this, "pick", &luaSitePick);
        lua.registerMethod(&this, "paint", &luaSitePaint);
        lua.registerMethod(&this, "fill", &luaSiteFill);
        lua.registerMethod(&this, "stop", &luaSiteStop);
        lua.registerMethod(&this, "entrance", &luaSiteEntrance);
        lua_setfield(lua, LUA_BELOW_TOP, "__index");
        lua_settop(lua, LUA_BELOW_TOP);
    }

    ubyte dimension() const {
        return builder.blueprint.dimension;
    }
}

StructureProblem placeWorldStructure(ref Graph graph) {
    if (!graph.worldgen.hasStructure()) {
        return StructureProblem.init;
    } else {
        StructureHost host = StructureHost(BlueprintBuilder.make(graph), SplitMix(graph.anchorBits(graph.anchorSlot)));
        StructureProblem problem = host.build(graph.worldgen.structureName(), rootSite(graph.anchorSlot));
        if (problem.isPresent) {
            host.builder.release();
        } else {
            graph.place(host.builder.finish());
        }
        return problem;
    }
}

StructureProblem placeStructure(ref Game game) {
    StructureProblem problem = placeWorldStructure(game.world.graph);
    game.placeAtSpawn();
    return problem;
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
    luaL_checktype(lua, SELF, LUA_TYPE_TABLE);
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
    int[2] across = rangeField(lua, index, "across", columnOf(dimension));
    int[2] along = rangeField(lua, index, "along", columnOf(dimension));
    int[2] height = rangeField(lua, index, "height", [int.min, int.max]);
    return CellBox.make(across[0], across[1], along[0], along[1], height[0], height[1]);
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
    lua_createtable(lua, 0, SITE_FIELDS);
    lua_pushinteger(lua, site.level);
    lua_setfield(lua, LUA_BELOW_TOP, "level");
    lua_pushinteger(lua, site.node);
    lua_setfield(lua, LUA_BELOW_TOP, "node");
    lua_pushinteger(lua, site.vertex);
    lua_setfield(lua, LUA_BELOW_TOP, "vertex");
    lua_pushinteger(lua, site.acrossSide);
    lua_setfield(lua, LUA_BELOW_TOP, "across_side");
    lua_pushinteger(lua, site.alongSide);
    lua_setfield(lua, LUA_BELOW_TOP, "along_side");
    lua_pushinteger(lua, site.acrossSign);
    lua_setfield(lua, LUA_BELOW_TOP, "across_sign");
    lua_pushinteger(lua, site.alongSign);
    lua_setfield(lua, LUA_BELOW_TOP, "along_sign");
    lua_pushinteger(lua, site.heightSign);
    lua_setfield(lua, LUA_BELOW_TOP, "height_sign");
    luaL_setmetatable(lua, SITE_TYPE.ptr);
}

SiteFrame siteArgument(lua_State* lua, int index, ref const Graph graph) {
    luaL_checktype(lua, index, LUA_TYPE_TABLE);
    int node = requiredField(lua, index, "node");
    int vertex = requiredField(lua, index, "vertex");
    int across = requiredField(lua, index, "across_side");
    int along = requiredField(lua, index, "along_side");
    int acrossSign = requiredField(lua, index, "across_sign");
    int alongSign = requiredField(lua, index, "along_sign");
    int heightSign = requiredField(lua, index, "height_sign");
    bool isInTables = node >= 0 && node < graph.nodeCount && vertex >= 0 && vertex < VERTEX_COUNT && across >= 0 && across < SIDE_COUNT && along >= 0 && along < SIDE_COUNT;
    bool isOnVertex = isInTables && across != along && sideAxis(cast(Vertex) vertex, cast(Side) across) < 3 && sideAxis(cast(Vertex) vertex, cast(Side) along) < 3;
    if (!isOnVertex || !isSign(acrossSign) || !isSign(alongSign) || !isSign(heightSign)) {
        luaL_error(lua, "not a site: sites come from a structure's argument and the site methods");
    }
    return SiteFrame(requiredField(lua, index, "level"), cast(uint) node, cast(Vertex) vertex, cast(Side) across, cast(Side) along, cast(byte) acrossSign, cast(byte) alongSign, cast(byte) heightSign);
}

bool isSign(int value) {
    return value == 1 || value == -1;
}

ColumnSpot spotArgument(lua_State* lua, int first) {
    return ColumnSpot(cast(float) luaL_checknumber(lua, first), cast(float) luaL_checknumber(lua, first + 1), cast(float) luaL_checknumber(lua, first + 2));
}

extern (C) int luaSiteUp(lua_State* lua) {
    StructureHost* host = structureHost(lua);
    SiteFrame site = siteArgument(lua, SELF, *host.builder.graph);
    lua.pushSite(shifted(site, cast(int) luaL_checkinteger(lua, SELF + 1)));
    return 1;
}

extern (C) int luaSiteTurn(lua_State* lua) {
    StructureHost* host = structureHost(lua);
    SiteFrame site = siteArgument(lua, SELF, *host.builder.graph);
    lua.pushSite(turned(site, cast(int) luaL_checkinteger(lua, SELF + 1)));
    return 1;
}

extern (C) int luaSiteBranch(lua_State* lua) {
    StructureHost* host = structureHost(lua);
    SiteFrame site = siteArgument(lua, SELF, *host.builder.graph);
    const(char)* axis = luaL_checklstring(lua, SELF + 1, null);
    LuaLookup!BranchAxis lookup = LuaLookup!BranchAxis.fromName(axis[0 .. strlen(axis)]);
    if (!lookup.isFound) {
        luaL_error(lua, "a site branches across or along, not '%s'", axis);
    }
    lua.pushSite((*host.builder.graph).branched(site, 0, lookup.value == BranchAxis.along));
    return 1;
}

extern (C) int luaSiteFace(lua_State* lua) {
    StructureHost* host = structureHost(lua);
    SiteFrame site = siteArgument(lua, SELF, *host.builder.graph);
    SiteFrame[FACE_CORNERS] corners = (*host.builder.graph).faceCorners(site);
    lua_createtable(lua, FACE_CORNERS, 0);
    foreach (index, corner; corners) {
        lua.pushSite(corner);
        lua_rawseti(lua, LUA_BELOW_TOP, cast(lua_Integer)(index + 1));
    }
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
    SiteFrame site = siteArgument(lua, SELF, *host.builder.graph);
    Material material = materialArgument(lua, SELF + 1);
    CellBox box = boxArgument(lua, SELF + 2, host.dimension());
    host.builder.paint(site, box, rhythmArgument(lua, SELF + 3), material, isIntoAirOnly);
    return 0;
}

extern (C) int luaSiteStop(lua_State* lua) {
    StructureHost* host = structureHost(lua);
    host.builder.stop(siteArgument(lua, SELF, *host.builder.graph), spotArgument(lua, SELF + 1));
    return 0;
}

extern (C) int luaSiteEntrance(lua_State* lua) {
    StructureHost* host = structureHost(lua);
    host.builder.enter(siteArgument(lua, SELF, *host.builder.graph), spotArgument(lua, SELF + 1));
    return 0;
}
