module client.script;

import core.stdc.stdio : FILE, fclose, fopen, fprintf, snprintf;
import core.stdc.string : strcmp, strlen;
import bindings.lua : luaL_checkany, luaL_checkinteger, luaL_checklstring, luaL_checknumber, luaL_checktype, luaL_error, luaL_loadbufferx, luaL_loadfilex, luaL_newstate, luaL_openselectedlibs, luaL_optlstring, luaL_optnumber, luaL_ref, luaL_traceback, luaL_unref, luaL_where, lua_CFunction, lua_Integer, lua_State, lua_close, lua_createtable, lua_error, lua_gettop, lua_pcallk, lua_pushboolean, lua_pushcclosure, lua_pushinteger, lua_pushlightuserdata, lua_pushnil, lua_pushnumber, lua_pushstring, lua_pushvalue, lua_rawgeti, lua_rotate, lua_setfield, lua_setglobal, lua_settop, lua_toboolean, lua_tolstring, lua_touserdata, lua_type;
import client.game : FrameInput, Game, KEY_COUNT, KEY_NAMES, KeyLookup, MATERIAL_PALETTE, characterAltitude, gameBreakBlock, gameLook, gamePlaceBlock, keyFromName, modeName, setMode, stepGame;
import common.vector3 : dot3, magnitude3, rejectAlong;

enum int LUA_REGISTRY = -(int.max / 2 + 1000);
enum int LUA_FIRST_UPVALUE = LUA_REGISTRY - 1;
enum int LUA_NO_REF = -2;
enum int LUA_TOP = -1;
enum int LUA_ROTATE_ONE = 1;
enum int LUA_TRACEBACK_LEVEL = 1;
enum int LUA_STATUS_OK = 0;
enum int LUA_TYPE_TABLE = 5;
enum int LUA_TYPE_FUNCTION = 6;
enum int LUA_LIBRARY_BASE = 1;
enum int LUA_LIBRARY_PACKAGE = 1 << 1;
enum int LUA_LIBRARY_COROUTINE = 1 << 2;
enum int LUA_LIBRARY_MATH = 1 << 5;
enum int LUA_LIBRARY_STRING = 1 << 7;
enum int LUA_LIBRARY_TABLE = 1 << 8;
enum int LUA_LIBRARY_UTF8 = 1 << 9;
enum int LUA_SAFE_LIBRARIES = LUA_LIBRARY_BASE | LUA_LIBRARY_PACKAGE | LUA_LIBRARY_COROUTINE | LUA_LIBRARY_MATH | LUA_LIBRARY_STRING | LUA_LIBRARY_TABLE | LUA_LIBRARY_UTF8;
enum int SELF = 1;
enum int PRELUDE_ARGUMENTS = 2;
enum int SCRIPT_ARGUMENTS = 1;
enum size_t SCRIPT_DIR_CAPACITY = 1024;
enum size_t FRAME_TEXT_CAPACITY = 64;
enum float DEFAULT_TIMESTEP_SECONDS = 0.016f;
enum double RADIANS_PER_DEGREE = 0.017453292519943295;

enum string PRELUDE = import("prelude.lua");

alias LuaFunction = extern (C) int function(lua_State*);

struct ScriptHost {
    lua_State* lua;
    Game* game;
    FILE* report;
    float timestepSeconds = DEFAULT_TIMESTEP_SECONDS;
    float yawRadiansPerSecond = 0;
    float pitchRadiansPerSecond = 0;
    uint frames;
    uint failures;
    int frameHook = LUA_NO_REF;
    int worldRef = LUA_NO_REF;
    bool[KEY_COUNT] held;
    bool stepping;
}

bool runScript(ScriptHost* host, const(char)* path) {
    host.lua = luaL_newstate();
    luaL_openselectedlibs(host.lua, LUA_SAFE_LIBRARIES, 0);
    lua_pushnil(host.lua);
    lua_setglobal(host.lua, "print");
    lua_pushnil(host.lua);
    lua_setglobal(host.lua, "warn");
    createWorld(host);
    char[SCRIPT_DIR_CAPACITY] directory;
    size_t length = strlen(path);
    size_t slash = length;
    while (slash > 0 && path[slash - 1] != '/') {
        slash -= 1;
    }
    if (slash > 0) {
        snprintf(directory.ptr, directory.length, "%.*s", cast(int)(slash - 1), path);
    } else {
        snprintf(directory.ptr, directory.length, ".");
    }
    bool ok = loaded(host, luaL_loadbufferx(host.lua, PRELUDE.ptr, PRELUDE.length, "=prelude", null));
    if (ok) {
        lua_rawgeti(host.lua, LUA_REGISTRY, host.worldRef);
        lua_pushstring(host.lua, directory.ptr);
        ok = protectedCall(host, PRELUDE_ARGUMENTS);
    }
    if (ok) {
        ok = loaded(host, luaL_loadfilex(host.lua, path, null));
    }
    if (ok) {
        lua_rawgeti(host.lua, LUA_REGISTRY, host.worldRef);
        ok = protectedCall(host, SCRIPT_ARGUMENTS);
    }
    return ok;
}

void closeScript(ScriptHost* host) {
    if (host.lua !is null) {
        lua_close(host.lua);
        host.lua = null;
    }
}

bool loaded(ScriptHost* host, int loadStatus) {
    bool ok = loadStatus == LUA_STATUS_OK;
    if (!ok) {
        reportError(host);
        lua_settop(host.lua, lua_gettop(host.lua) - 1);
    }
    return ok;
}

bool protectedCall(ScriptHost* host, int argumentCount) {
    int functionIndex = lua_gettop(host.lua) - argumentCount;
    lua_pushcclosure(host.lua, cast(lua_CFunction) &luaTraceback, 0);
    lua_rotate(host.lua, functionIndex, LUA_ROTATE_ONE);
    bool ok = lua_pcallk(host.lua, argumentCount, 0, functionIndex, 0, null) == LUA_STATUS_OK;
    if (!ok) {
        reportError(host);
    }
    lua_settop(host.lua, functionIndex - 1);
    return ok;
}

void reportError(ScriptHost* host) {
    if (host.report !is null) {
        fprintf(host.report, "script error: %s\n", lua_tolstring(host.lua, LUA_TOP, null));
    }
}

void createWorld(ScriptHost* host) {
    lua_createtable(host.lua, 0, 0);
    registerMethod(host, "frames", &luaFrames);
    registerMethod(host, "timestep", &luaTimestep);
    registerMethod(host, "time", &luaTime);
    registerMethod(host, "worldgen", &luaWorldgen);
    registerMethod(host, "every_frame", &luaEveryFrame);
    registerMethod(host, "check", &luaCheck);
    lua_createtable(host.lua, 0, 0);
    registerMethod(host, "hold", &luaHold);
    registerMethod(host, "release", &luaRelease);
    registerMethod(host, "release_all", &luaReleaseAll);
    registerMethod(host, "look", &luaLook);
    registerMethod(host, "turn_rate", &luaTurnRate);
    registerMethod(host, "mode", &luaMode);
    registerMethod(host, "material", &luaMaterial);
    registerMethod(host, "break_block", &luaBreakBlock);
    registerMethod(host, "place_block", &luaPlaceBlock);
    registerMethod(host, "traveled", &luaTraveled);
    registerMethod(host, "on_ground", &luaOnGround);
    registerMethod(host, "altitude", &luaAltitude);
    registerMethod(host, "speed", &luaSpeed);
    registerMethod(host, "horizontal_speed", &luaHorizontalSpeed);
    registerMethod(host, "vertical_speed", &luaVerticalSpeed);
    registerMethod(host, "camera_vertical_acceleration", &luaCameraVerticalAcceleration);
    lua_setfield(host.lua, -2, "player");
    host.worldRef = luaL_ref(host.lua, LUA_REGISTRY);
}

void registerMethod(ScriptHost* host, const(char)* name, LuaFunction fn) {
    lua_pushlightuserdata(host.lua, host);
    lua_pushcclosure(host.lua, cast(lua_CFunction) fn, 1);
    lua_setfield(host.lua, -2, name);
}

ScriptHost* methodHost(lua_State* lua) {
    luaL_checktype(lua, SELF, LUA_TYPE_TABLE);
    return cast(ScriptHost*) lua_touserdata(lua, LUA_FIRST_UPVALUE);
}

bool stepOnce(ScriptHost* host, float dt) {
    FrameInput input;
    input.held = host.held;
    input.yaw = host.yawRadiansPerSecond * dt;
    input.pitch = host.pitchRadiansPerSecond * dt;
    stepGame(host.game, input, dt);
    host.frames += 1;
    bool ok = true;
    if (host.frameHook != LUA_NO_REF) {
        host.stepping = true;
        lua_rawgeti(host.lua, LUA_REGISTRY, host.frameHook);
        ok = lua_pcallk(host.lua, 0, 0, 0, 0, null) == LUA_STATUS_OK;
        host.stepping = false;
    }
    return ok;
}

float metersPerAbsolute(const(ScriptHost)* host) {
    return 1.0f / host.game.simConfig.metersToAbsolute;
}

bool isNoneOrNil(lua_State* lua, int index) {
    return lua_type(lua, index) <= 0;
}

float degreesArgument(lua_State* lua, int index) {
    return cast(float)(luaL_checknumber(lua, index) * RADIANS_PER_DEGREE);
}

extern (C) int luaTraceback(lua_State* lua) {
    luaL_traceback(lua, lua, lua_tolstring(lua, 1, null), LUA_TRACEBACK_LEVEL);
    return 1;
}

extern (C) int luaFrames(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_Integer count = luaL_checkinteger(lua, SELF + 1);
    float dt = cast(float) luaL_optnumber(lua, SELF + 2, host.timestepSeconds);
    if (count < 0 || !(dt > 0)) {
        luaL_error(lua, "frames: need n >= 0 and dt > 0");
    } else if (host.stepping) {
        luaL_error(lua, "frames: every_frame hooks cannot advance time");
    } else {
        bool ok = true;
        lua_Integer frame = 0;
        while (ok && frame < count) {
            ok = stepOnce(host, dt);
            frame += 1;
        }
        if (!ok) {
            lua_error(lua);
        }
    }
    return 0;
}

extern (C) int luaTimestep(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    if (!isNoneOrNil(lua, SELF + 1)) {
        float seconds = cast(float) luaL_checknumber(lua, SELF + 1);
        if (!(seconds > 0)) {
            luaL_error(lua, "timestep must be positive");
        } else {
            host.timestepSeconds = seconds;
        }
    }
    lua_pushnumber(lua, host.timestepSeconds);
    return 1;
}

extern (C) int luaTime(lua_State* lua) {
    lua_pushnumber(lua, methodHost(lua).game.simTime);
    return 1;
}

extern (C) int luaWorldgen(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    const(char)* name = luaL_checklstring(lua, SELF + 1, null);
    const(char)[] kind = name[0 .. strlen(name)];
    if (host.frames > 0) {
        luaL_error(lua, "worldgen must be chosen before the first frame");
    } else if (kind != "flat" && kind != "terrain") {
        luaL_error(lua, "unknown worldgen '%s'", name);
    } else {
        host.game.world.worldgenDriver.flatWorldgen = kind == "flat";
    }
    return 0;
}

extern (C) int luaEveryFrame(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    if (host.frameHook != LUA_NO_REF) {
        luaL_unref(lua, LUA_REGISTRY, host.frameHook);
        host.frameHook = LUA_NO_REF;
    }
    if (!isNoneOrNil(lua, SELF + 1)) {
        luaL_checktype(lua, SELF + 1, LUA_TYPE_FUNCTION);
        lua_pushvalue(lua, SELF + 1);
        host.frameHook = luaL_ref(lua, LUA_REGISTRY);
    }
    return 0;
}

extern (C) int luaCheck(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    luaL_checkany(lua, SELF + 1);
    int passed = lua_toboolean(lua, SELF + 1);
    if (!passed) {
        const(char)* message = luaL_optlstring(lua, SELF + 2, "check failed", null);
        luaL_where(lua, LUA_TRACEBACK_LEVEL);
        if (host.report !is null) {
            fprintf(host.report, "FAIL %s%s (t=%.2fs)\n", lua_tolstring(lua, LUA_TOP, null), message, cast(double) host.game.simTime);
        }
        host.failures += 1;
    }
    lua_pushboolean(lua, passed);
    return 1;
}

extern (C) int luaHold(lua_State* lua) {
    setKeys(lua, true);
    return 0;
}

extern (C) int luaRelease(lua_State* lua) {
    setKeys(lua, false);
    return 0;
}

void setKeys(lua_State* lua, bool held) {
    ScriptHost* host = methodHost(lua);
    foreach (index; SELF + 1 .. lua_gettop(lua) + 1) {
        const(char)* name = luaL_checklstring(lua, index, null);
        KeyLookup lookup = keyFromName(name[0 .. strlen(name)]);
        if (lookup.found) {
            host.held[lookup.key] = held;
        } else {
            luaL_error(lua, "unknown key '%s'", name);
        }
    }
}

extern (C) int luaReleaseAll(lua_State* lua) {
    methodHost(lua).held[] = false;
    return 0;
}

extern (C) int luaLook(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    gameLook(host.game, degreesArgument(lua, SELF + 1), degreesArgument(lua, SELF + 2));
    return 0;
}

extern (C) int luaTurnRate(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    if (!isNoneOrNil(lua, SELF + 1)) {
        host.yawRadiansPerSecond = degreesArgument(lua, SELF + 1);
        host.pitchRadiansPerSecond = 0;
        if (!isNoneOrNil(lua, SELF + 2)) {
            host.pitchRadiansPerSecond = degreesArgument(lua, SELF + 2);
        }
    }
    lua_pushnumber(lua, host.yawRadiansPerSecond / RADIANS_PER_DEGREE);
    lua_pushnumber(lua, host.pitchRadiansPerSecond / RADIANS_PER_DEGREE);
    return 2;
}

extern (C) int luaMode(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    if (!isNoneOrNil(lua, SELF + 1)) {
        const(char)* name = luaL_checklstring(lua, SELF + 1, null);
        if (!setMode(host.game, name[0 .. strlen(name)])) {
            luaL_error(lua, "unknown mode '%s'", name);
        }
    }
    lua_pushstring(lua, modeName(host.game));
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
    lua_pushboolean(lua, gameBreakBlock(methodHost(lua).game));
    return 1;
}

extern (C) int luaPlaceBlock(lua_State* lua) {
    lua_pushboolean(lua, gamePlaceBlock(methodHost(lua).game));
    return 1;
}

extern (C) int luaTraveled(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, host.game.traveled * metersPerAbsolute(host));
    return 1;
}

extern (C) int luaOnGround(lua_State* lua) {
    lua_pushboolean(lua, methodHost(lua).game.characterState.onGround);
    return 1;
}

extern (C) int luaAltitude(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, characterAltitude(host.game) * metersPerAbsolute(host));
    return 1;
}

extern (C) int luaSpeed(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, magnitude3(host.game.characterState.velocity) * metersPerAbsolute(host));
    return 1;
}

extern (C) int luaHorizontalSpeed(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, magnitude3(rejectAlong(host.game.characterState.velocity, host.game.character.up)) * metersPerAbsolute(host));
    return 1;
}

extern (C) int luaVerticalSpeed(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, dot3(host.game.characterState.velocity, host.game.character.up) * metersPerAbsolute(host));
    return 1;
}

extern (C) int luaCameraVerticalAcceleration(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, host.game.vacc * metersPerAbsolute(host));
    return 1;
}

struct ScriptRecorder {
    FILE* file;
    uint pendingCount;
    char[FRAME_TEXT_CAPACITY] pendingFrame = 0;
    bool[KEY_COUNT] held;
}

ScriptRecorder openScriptRecorder(const(char)* path) {
    ScriptRecorder recorder;
    recorder.file = fopen(path, "w");
    if (recorder.file !is null) {
        fprintf(recorder.file, "local world = ...\nlocal player = world.player\n");
    }
    return recorder;
}

void recordFrame(ScriptRecorder* recorder, FrameInput input, float dt) {
    if (recorder.file !is null) {
        foreach (i; 0 .. KEY_COUNT) {
            if (input.held[i] != recorder.held[i]) {
                flushRecorder(recorder);
                const(char)* call = "release";
                if (input.held[i]) {
                    call = "hold";
                }
                fprintf(recorder.file, "player:%s(\"%.*s\")\n", call, cast(int) KEY_NAMES[i].length, KEY_NAMES[i].ptr);
            }
        }
        recorder.held = input.held;
        if (input.yaw != 0 || input.pitch != 0) {
            flushRecorder(recorder);
            fprintf(recorder.file, "player:look(%.9g, %.9g)\n", input.yaw / RADIANS_PER_DEGREE, input.pitch / RADIANS_PER_DEGREE);
        }
        char[FRAME_TEXT_CAPACITY] frameText;
        snprintf(frameText.ptr, frameText.length, "%.9g", cast(double) dt);
        if (strcmp(frameText.ptr, recorder.pendingFrame.ptr) != 0) {
            flushRecorder(recorder);
            recorder.pendingFrame = frameText;
        }
        recorder.pendingCount += 1;
    }
}

void recordEvent(ScriptRecorder* recorder, const(char)* call) {
    if (recorder.file !is null) {
        flushRecorder(recorder);
        fprintf(recorder.file, "%s\n", call);
    }
}

void flushRecorder(ScriptRecorder* recorder) {
    if (recorder.pendingCount > 0) {
        fprintf(recorder.file, "world:frames(%u, %s)\n", recorder.pendingCount, recorder.pendingFrame.ptr);
    }
    recorder.pendingCount = 0;
    recorder.pendingFrame[0] = 0;
}

void closeScriptRecorder(ScriptRecorder* recorder) {
    if (recorder.file !is null) {
        flushRecorder(recorder);
        fclose(recorder.file);
        recorder.file = null;
    }
}
