module client.script;

import core.stdc.math : floor;
import core.stdc.stdio : FILE, fclose, fopen, fprintf;
import core.stdc.string : strlen;
import bindings.lua : luaL_checkinteger, luaL_checklstring, luaL_checknumber, luaL_checktype, luaL_error, luaL_loadfilex, luaL_newstate, luaL_openselectedlibs, luaL_optnumber, luaL_ref, luaL_traceback, luaL_unref, lua_CFunction, lua_Integer, lua_State, lua_callk, lua_close, lua_createtable, lua_getglobal, lua_gettop, lua_pcallk, lua_pushboolean, lua_pushcclosure, lua_pushinteger, lua_pushlightuserdata, lua_pushlstring, lua_pushnil, lua_pushnumber, lua_pushstring, lua_pushvalue, lua_rawgeti, lua_setfield, lua_setglobal, lua_settop, lua_tolstring, lua_touserdata, lua_type;
import client.game : FrameInput, Game, KEY_COUNT, Key, MATERIAL_PALETTE, StairWaypoint;
import client.world : TargetMaterial;
import common.array : Array;
import common.character.controller : MovementMode;
import common.graph : NodeId;
import common.names : ENUM_NAMES;
import common.units : Angle, AngularSpeed, Length, Time;
import common.vector3 : dot, magnitude, rejectAlong;
import common.worldgen.generation : PlaneWorld, StructureKind, StructureWorld, Worldgen, WorldgenKind;

enum int LUA_REGISTRY = -(int.max / 2 + 1000);
enum int LUA_FIRST_UPVALUE = LUA_REGISTRY - 1;
enum int LUA_NO_REF = -2;
enum int LUA_TOP = -1;
enum int LUA_BELOW_TOP = -2;
enum int LUA_TRACEBACK_LEVEL = 1;
enum int LUA_STATUS_OK = 0;
enum int LUA_TYPE_TABLE = 5;
enum int LUA_TYPE_FUNCTION = 6;
enum int LUA_LIBRARY_BASE = 1 << 0;
enum int LUA_LIBRARY_PACKAGE = 1 << 1;
enum int LUA_LIBRARY_COROUTINE = 1 << 2;
enum int LUA_LIBRARY_MATH = 1 << 5;
enum int LUA_LIBRARY_STRING = 1 << 7;
enum int LUA_LIBRARY_TABLE = 1 << 8;
enum int LUA_LIBRARY_UTF8 = 1 << 9;
enum int LUA_SAFE_LIBRARIES = LUA_LIBRARY_BASE | LUA_LIBRARY_PACKAGE | LUA_LIBRARY_COROUTINE | LUA_LIBRARY_MATH | LUA_LIBRARY_STRING | LUA_LIBRARY_TABLE | LUA_LIBRARY_UTF8;
enum int SELF = 1;
enum int TRACEBACK_INDEX = 1;
enum int CHUNK_RESULTS = 1;
enum int SCRIPT_ARGUMENTS = 1;
enum Time DEFAULT_TIMESTEP = Time(0.016f);
enum Time ONE_SECOND = Time(1.0f);
enum double RADIANS_PER_DEGREE = 0.017453292519943295;
enum string MODULE_PATTERN = "?.lua";
enum size_t LUA_NAME_CAPACITY = 32;
enum char LUA_NAME_SEPARATOR = '_';

alias LuaFunction = extern (C) int function(lua_State*);

struct LuaName {
    char[LUA_NAME_CAPACITY] text;
    size_t length;

    static LuaName fromMember(string member) {
        LuaName name;
        foreach (c; member) {
            if (isUpperCase(c)) {
                name.text[name.length] = LUA_NAME_SEPARATOR;
                name.text[name.length + 1] = lowerCase(c);
                name.length += 2;
            } else {
                name.text[name.length] = c;
                name.length += 1;
            }
        }
        return name;
    }

    const(char)[] slice() const return {
        return text[0 .. length];
    }
}

struct LuaLookup(E) {
    E value;
    bool isFound;

    static LuaLookup fromName(const(char)[] name) {
        uint index = 0;
        while (index < ENUM_NAMES!E.length && LuaName.fromMember(ENUM_NAMES!E[index]).slice() != name) {
            index += 1;
        }
        if (index < ENUM_NAMES!E.length) {
            return LuaLookup(cast(E) index, true);
        } else {
            return LuaLookup(E.init, false);
        }
    }
}

bool isUpperCase(char c) {
    return c >= 'A' && c <= 'Z';
}

char lowerCase(char c) {
    return cast(char)(c - 'A' + 'a');
}

void pushLuaName(E)(lua_State* lua, E value) {
    LuaName name = LuaName.fromMember(ENUM_NAMES!E[value]);
    lua_pushlstring(lua, name.text.ptr, name.length);
}

struct ScriptHost {
    lua_State* lua;
    Game* game;
    FILE* report;
    Time timestep = DEFAULT_TIMESTEP;
    AngularSpeed yawRate;
    AngularSpeed pitchRate;
    uint steps;
    int stepHook = LUA_NO_REF;
    int worldRef = LUA_NO_REF;
    bool[KEY_COUNT] isHeld;
    bool isStepping;

    static ScriptHost make(Game* game, FILE* report) {
        return ScriptHost(null, game, report);
    }

    bool run(const(char)* path) {
        lua = luaL_newstate();
        luaL_openselectedlibs(lua, LUA_SAFE_LIBRARIES, 0);
        lua_pushnil(lua);
        lua_setglobal(lua, "print");
        lua_pushnil(lua);
        lua_setglobal(lua, "warn");
        setPackagePath(path[0 .. strlen(path)]);
        createWorld();
        lua_pushcclosure(lua, cast(lua_CFunction) &luaTraceback, 0);
        immutable int status = luaL_loadfilex(lua, path, null);
        if (status != LUA_STATUS_OK) {
            reportError();
            return false;
        } else {
            return runChunk(path);
        }
    }

    bool runChunk(const(char)* path) {
        immutable int status = lua_pcallk(lua, 0, CHUNK_RESULTS, TRACEBACK_INDEX, 0, null);
        if (status != LUA_STATUS_OK) {
            reportError();
            return false;
        } else if (lua_type(lua, LUA_TOP) != LUA_TYPE_FUNCTION) {
            fprintf(report, "script error: %s does not return a function of the world\n", path);
            return false;
        } else {
            return runScript();
        }
    }

    bool runScript() {
        lua_rawgeti(lua, LUA_REGISTRY, worldRef);
        immutable int status = lua_pcallk(lua, SCRIPT_ARGUMENTS, 0, TRACEBACK_INDEX, 0, null);
        if (status != LUA_STATUS_OK) {
            reportError();
            return false;
        } else {
            return true;
        }
    }

    void close() {
        lua_close(lua);
        lua = null;
    }

    void reportError() {
        fprintf(report, "script error: %s\n", lua_tolstring(lua, LUA_TOP, null));
    }

    void setPackagePath(const(char)[] scriptPath) {
        Array!char searchPath;
        foreach_reverse (i, c; scriptPath) {
            if (c == '/') {
                searchPath.appendAll(scriptPath[0 .. i + 1]);
                searchPath.appendAll(MODULE_PATTERN ~ ";");
            }
        }
        searchPath.appendAll(MODULE_PATTERN);
        lua_getglobal(lua, "package");
        lua_pushlstring(lua, searchPath.ptr, searchPath.length);
        lua_setfield(lua, LUA_BELOW_TOP, "path");
        lua_settop(lua, LUA_BELOW_TOP);
        searchPath.release();
    }

    void createWorld() {
        lua_createtable(lua, 0, 0);
        registerMethod("wait", &luaWait);
        registerMethod("step", &luaStep);
        registerMethod("timestep", &luaTimestep);
        registerMethod("time", &luaTime);
        registerMethod("worldgen", &luaWorldgen);
        registerMethod("on_step", &luaOnStep);
        registerMethod("hold", &luaHold);
        registerMethod("release", &luaRelease);
        registerMethod("release_all", &luaReleaseAll);
        registerMethod("press", &luaPress);
        registerMethod("look", &luaLook);
        registerMethod("turn_rate", &luaTurnRate);
        registerMethod("turn", &luaTurn);
        registerMethod("mode", &luaMode);
        registerMethod("material", &luaMaterial);
        registerMethod("break_block", &luaBreakBlock);
        registerMethod("place_block", &luaPlaceBlock);
        registerMethod("target_material", &luaTargetMaterial);
        registerMethod("enter_structure", &luaEnterStructure);
        registerMethod("enter_stairs", &luaEnterStairs);
        registerMethod("stair_waypoint", &luaStairWaypoint);
        registerMethod("traveled", &luaTraveled);
        registerMethod("is_on_ground", &luaIsOnGround);
        registerMethod("altitude", &luaAltitude);
        registerMethod("speed", &luaSpeed);
        registerMethod("horizontal_speed", &luaHorizontalSpeed);
        registerMethod("vertical_speed", &luaVerticalSpeed);
        registerMethod("camera_vertical_acceleration", &luaCameraVerticalAcceleration);
        worldRef = luaL_ref(lua, LUA_REGISTRY);
    }

    void registerMethod(const(char)* name, LuaFunction fn) {
        lua_pushlightuserdata(lua, &this);
        lua_pushcclosure(lua, cast(lua_CFunction) fn, 1);
        lua_setfield(lua, LUA_BELOW_TOP, name);
    }

    void step(Time dt) {
        if (!(dt.value > 0)) {
            luaL_error(lua, "the timestep must be positive");
        } else if (isStepping) {
            luaL_error(lua, "a step hook cannot advance time");
        } else {
            game.step(FrameInput(yawRate * dt, pitchRate * dt, isHeld), dt);
            steps += 1;
            runStepHook();
        }
    }

    void runStepHook() {
        if (stepHook != LUA_NO_REF) {
            isStepping = true;
            lua_rawgeti(lua, LUA_REGISTRY, stepHook);
            lua_callk(lua, 0, 0, 0, null);
            isStepping = false;
        }
    }

    void wait(double seconds, Time dt) {
        if (!(seconds >= 0)) {
            luaL_error(lua, "cannot wait a negative time");
        } else if (!(dt.value > 0)) {
            luaL_error(lua, "the timestep must be positive");
        } else {
            foreach (_; 0 .. cast(ulong) floor(seconds / dt.value + 0.5)) {
                step(dt);
            }
        }
    }

    void setKeys(int firstArgument, bool isPressed) {
        foreach (index; firstArgument .. lua_gettop(lua) + 1) {
            const(char)* name = luaL_checklstring(lua, index, null);
            LuaLookup!Key lookup = LuaLookup!Key.fromName(name[0 .. strlen(name)]);
            if (lookup.isFound) {
                isHeld[lookup.value] = isPressed;
            } else {
                luaL_error(lua, "unknown key '%s'", name);
            }
        }
    }
}

ScriptHost* methodHost(lua_State* lua) {
    luaL_checktype(lua, SELF, LUA_TYPE_TABLE);
    return cast(ScriptHost*) lua_touserdata(lua, LUA_FIRST_UPVALUE);
}

bool isNoneOrNil(lua_State* lua, int index) {
    return lua_type(lua, index) <= 0;
}

Angle degreesArgument(lua_State* lua, int index) {
    return Angle(cast(float)(luaL_checknumber(lua, index) * RADIANS_PER_DEGREE));
}

Time timestepArgument(lua_State* lua, int index, Time fallback) {
    return Time(cast(float) luaL_optnumber(lua, index, fallback.value));
}

double degreesOf(Angle angle) {
    return angle.value / RADIANS_PER_DEGREE;
}

extern (C) int luaTraceback(lua_State* lua) {
    luaL_traceback(lua, lua, lua_tolstring(lua, 1, null), LUA_TRACEBACK_LEVEL);
    return 1;
}

extern (C) int luaWait(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    host.wait(luaL_checknumber(lua, SELF + 1), timestepArgument(lua, SELF + 2, host.timestep));
    return 0;
}

extern (C) int luaStep(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    host.step(timestepArgument(lua, SELF + 1, host.timestep));
    return 0;
}

extern (C) int luaTimestep(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    if (!isNoneOrNil(lua, SELF + 1)) {
        Time chosen = Time(cast(float) luaL_checknumber(lua, SELF + 1));
        if (!(chosen.value > 0)) {
            luaL_error(lua, "the timestep must be positive");
        } else {
            host.timestep = chosen;
        }
    }
    lua_pushnumber(lua, host.timestep.value);
    return 1;
}

extern (C) int luaTime(lua_State* lua) {
    lua_pushnumber(lua, methodHost(lua).game.time.value);
    return 1;
}

extern (C) int luaWorldgen(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    const(char)* name = luaL_checklstring(lua, SELF + 1, null);
    LuaLookup!WorldgenKind lookup = LuaLookup!WorldgenKind.fromName(name[0 .. strlen(name)]);
    if (host.steps > 0) {
        luaL_error(lua, "worldgen must be chosen before the first step");
    } else if (!lookup.isFound) {
        luaL_error(lua, "unknown worldgen '%s'", name);
    } else {
        host.game.setWorldgen(worldgenOfKind(lua, lookup.value));
    }
    return 0;
}

Worldgen worldgenOfKind(lua_State* lua, WorldgenKind kind) {
    Worldgen worldgen;
    final switch (kind) {
        case WorldgenKind.terrain:
            worldgen = Worldgen.makeTerrain();
            break;
        case WorldgenKind.plane:
            worldgen = Worldgen.fromPlane(PlaneWorld(cast(float)(luaL_optnumber(lua, SELF + 2, 0) * RADIANS_PER_DEGREE)));
            break;
        case WorldgenKind.structure:
            worldgen = Worldgen.fromStructure(StructureWorld(NodeId.init, structureArgument(lua)));
            break;
    }
    return worldgen;
}

StructureKind structureArgument(lua_State* lua) {
    const(char)* name = luaL_checklstring(lua, SELF + 2, null);
    LuaLookup!StructureKind lookup = LuaLookup!StructureKind.fromName(name[0 .. strlen(name)]);
    if (!lookup.isFound) {
        luaL_error(lua, "unknown structure '%s'", name);
    }
    return lookup.value;
}

extern (C) int luaEnterStructure(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    Length height = Length(cast(float) luaL_checknumber(lua, SELF + 1));
    if (host.game.world.graph.worldgen.kind != WorldgenKind.structure) {
        luaL_error(lua, "enter_structure needs the structure worldgen");
    } else {
        host.game.enterStructure(height);
    }
    return 0;
}

extern (C) int luaEnterStairs(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    if (host.game.world.graph.worldgen.kind != WorldgenKind.structure) {
        luaL_error(lua, "enter_stairs needs the structure worldgen");
    } else {
        host.game.enterStairs();
    }
    return 0;
}

extern (C) int luaStairWaypoint(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_Integer number = luaL_checkinteger(lua, SELF + 1);
    StairWaypoint waypoint;
    if (number >= 1) {
        waypoint = host.game.stairWaypoint(cast(size_t)(number - 1));
    }
    if (waypoint.isFound) {
        lua_pushnumber(lua, -degreesOf(waypoint.yaw));
        lua_pushnumber(lua, waypoint.horizontal.value);
        lua_pushnumber(lua, waypoint.rise.value);
        return 3;
    } else {
        lua_pushnil(lua);
        return 1;
    }
}

extern (C) int luaTargetMaterial(lua_State* lua) {
    TargetMaterial target = methodHost(lua).game.world.targetMaterial();
    if (target.isFound) {
        pushLuaName(lua, target.material);
    } else {
        lua_pushnil(lua);
    }
    return 1;
}

extern (C) int luaOnStep(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    if (host.stepHook != LUA_NO_REF) {
        luaL_unref(lua, LUA_REGISTRY, host.stepHook);
        host.stepHook = LUA_NO_REF;
    }
    if (!isNoneOrNil(lua, SELF + 1)) {
        luaL_checktype(lua, SELF + 1, LUA_TYPE_FUNCTION);
        lua_pushvalue(lua, SELF + 1);
        host.stepHook = luaL_ref(lua, LUA_REGISTRY);
    }
    return 0;
}

extern (C) int luaHold(lua_State* lua) {
    methodHost(lua).setKeys(SELF + 1, true);
    return 0;
}

extern (C) int luaRelease(lua_State* lua) {
    methodHost(lua).setKeys(SELF + 1, false);
    return 0;
}

extern (C) int luaReleaseAll(lua_State* lua) {
    methodHost(lua).isHeld[] = false;
    return 0;
}

extern (C) int luaPress(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    double seconds = luaL_checknumber(lua, SELF + 1);
    host.setKeys(SELF + 2, true);
    host.wait(seconds, host.timestep);
    host.setKeys(SELF + 2, false);
    return 0;
}

extern (C) int luaLook(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    host.game.look(degreesArgument(lua, SELF + 1), degreesArgument(lua, SELF + 2));
    return 0;
}

extern (C) int luaTurnRate(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    if (!isNoneOrNil(lua, SELF + 1)) {
        host.yawRate = degreesArgument(lua, SELF + 1) / ONE_SECOND;
        host.pitchRate = AngularSpeed(0);
        if (!isNoneOrNil(lua, SELF + 2)) {
            host.pitchRate = degreesArgument(lua, SELF + 2) / ONE_SECOND;
        }
    }
    lua_pushnumber(lua, degreesOf(host.yawRate * ONE_SECOND));
    lua_pushnumber(lua, degreesOf(host.pitchRate * ONE_SECOND));
    return 2;
}

extern (C) int luaTurn(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    double seconds = luaL_checknumber(lua, SELF + 3);
    Time duration = Time(cast(float) seconds);
    AngularSpeed restingYaw = host.yawRate;
    AngularSpeed restingPitch = host.pitchRate;
    host.yawRate = degreesArgument(lua, SELF + 1) / duration;
    host.pitchRate = degreesArgument(lua, SELF + 2) / duration;
    host.wait(seconds, host.timestep);
    host.yawRate = restingYaw;
    host.pitchRate = restingPitch;
    return 0;
}

extern (C) int luaMode(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    if (!isNoneOrNil(lua, SELF + 1)) {
        const(char)* name = luaL_checklstring(lua, SELF + 1, null);
        LuaLookup!MovementMode lookup = LuaLookup!MovementMode.fromName(name[0 .. strlen(name)]);
        if (lookup.isFound) {
            host.game.mode = lookup.value;
        } else {
            luaL_error(lua, "unknown mode '%s'", name);
        }
    }
    pushLuaName(lua, host.game.mode);
    return 1;
}

extern (C) int luaMaterial(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    if (!isNoneOrNil(lua, SELF + 1)) {
        lua_Integer slot = luaL_checkinteger(lua, SELF + 1);
        if (slot < 1 || slot > MATERIAL_PALETTE.length) {
            luaL_error(lua, "material slot must be 1..%d", cast(int) MATERIAL_PALETTE.length);
        } else {
            host.game.materialIndex = cast(uint)(slot - 1);
        }
    }
    lua_pushinteger(lua, host.game.materialIndex + 1);
    return 1;
}

extern (C) int luaBreakBlock(lua_State* lua) {
    lua_pushboolean(lua, methodHost(lua).game.breakBlock());
    return 1;
}

extern (C) int luaPlaceBlock(lua_State* lua) {
    lua_pushboolean(lua, methodHost(lua).game.placeBlock());
    return 1;
}

extern (C) int luaTraveled(lua_State* lua) {
    lua_pushnumber(lua, methodHost(lua).game.traveled.value);
    return 1;
}

extern (C) int luaIsOnGround(lua_State* lua) {
    lua_pushboolean(lua, methodHost(lua).game.characterState.isOnGround);
    return 1;
}

extern (C) int luaAltitude(lua_State* lua) {
    lua_pushnumber(lua, methodHost(lua).game.altitude.value);
    return 1;
}

extern (C) int luaSpeed(lua_State* lua) {
    lua_pushnumber(lua, methodHost(lua).game.characterState.velocity.magnitude);
    return 1;
}

extern (C) int luaHorizontalSpeed(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, host.game.characterState.velocity.rejectAlong(host.game.characterState.up).magnitude);
    return 1;
}

extern (C) int luaVerticalSpeed(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, host.game.characterState.velocity.dot(host.game.characterState.up));
    return 1;
}

extern (C) int luaCameraVerticalAcceleration(lua_State* lua) {
    lua_pushnumber(lua, methodHost(lua).game.cameraVerticalAcceleration.value);
    return 1;
}

struct ScriptRecorder {
    FILE* file;
    Time pendingDt;
    uint pendingSteps;
    bool[KEY_COUNT] isHeld;

    bool open(const(char)* path) {
        file = fopen(path, "w");
        if (file is null) {
            return false;
        } else {
            fprintf(file, "return function(world)\n");
            return true;
        }
    }

    void recordFrame(FrameInput input, Time dt) {
        foreach (i; 0 .. KEY_COUNT) {
            if (input.isHeld[i] != isHeld[i]) {
                flush();
                LuaName name = LuaName.fromMember(ENUM_NAMES!Key[i]);
                fprintf(file, "  world:%s(\"%.*s\")\n", keyCall(input.isHeld[i]), cast(int) name.length, name.text.ptr);
            }
        }
        isHeld = input.isHeld;
        if (input.yaw.value != 0 || input.pitch.value != 0) {
            flush();
            fprintf(file, "  world:look(%.9g, %.9g)\n", degreesOf(input.yaw), degreesOf(input.pitch));
        }
        if (dt.value != pendingDt.value) {
            flush();
            pendingDt = dt;
        }
        pendingSteps += 1;
    }

    void recordCall(const(char)* call) {
        flush();
        fprintf(file, "  world:%s()\n", call);
    }

    void recordMode(MovementMode mode) {
        flush();
        LuaName name = LuaName.fromMember(ENUM_NAMES!MovementMode[mode]);
        fprintf(file, "  world:mode(\"%.*s\")\n", cast(int) name.length, name.text.ptr);
    }

    void recordMaterial(uint slot) {
        flush();
        fprintf(file, "  world:material(%u)\n", slot);
    }

    void flush() {
        if (pendingSteps > 0) {
            fprintf(file, "  world:wait(%.9g, %.9g)\n", pendingSteps * cast(double) pendingDt.value, cast(double) pendingDt.value);
        }
        pendingSteps = 0;
    }

    void close() {
        flush();
        fprintf(file, "end\n");
        fclose(file);
        file = null;
    }
}

immutable(char)* keyCall(bool isPressed) {
    if (isPressed) {
        return "hold";
    } else {
        return "release";
    }
}
