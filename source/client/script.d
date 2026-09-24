module client.script;

import core.math : sqrt;
import core.stdc.stdio : FILE, fclose, fopen, fprintf, snprintf;
import core.stdc.string : strcmp, strlen;
import bindings.lua : luaL_checkany, luaL_checkinteger, luaL_checklstring, luaL_checknumber, luaL_checktype, luaL_error, luaL_loadbufferx, luaL_loadfilex, luaL_newstate, luaL_openselectedlibs, luaL_optlstring, luaL_optnumber, luaL_ref, luaL_traceback, luaL_unref, luaL_where, lua_CFunction, lua_Integer, lua_State, lua_close, lua_error, lua_gettop, lua_pcallk, lua_pushboolean, lua_pushcclosure, lua_pushinteger, lua_pushlightuserdata, lua_pushnil, lua_pushnumber, lua_pushstring, lua_pushvalue, lua_rawgeti, lua_rotate, lua_setglobal, lua_settop, lua_toboolean, lua_tolstring, lua_touserdata, lua_type;
import client.game : FrameInput, Game, KEY_COUNT, KEY_NAMES, KeyLookup, MATERIAL_PALETTE, gameBreakBlock, gamePlaceBlock, keyFromName, modeName, setMode, stepGame;

enum int LUA_REGISTRY = -(int.max / 2 + 1000);
enum int LUA_FIRST_UPVALUE = LUA_REGISTRY - 1;
enum int LUA_NO_REF = -2;
enum int LUA_TOP = -1;
enum int LUA_BELOW_TOP = -2;
enum int LUA_POP_ONE = -2;
enum int LUA_POP_TWO = -3;
enum int LUA_ROTATE_ONE = 1;
enum int LUA_TRACEBACK_LEVEL = 1;
enum int LUA_STATUS_OK = 0;
enum int LUA_TYPE_FUNCTION = 6;
enum int LUA_LIBRARY_BASE = 1;
enum int LUA_LIBRARY_PACKAGE = 1 << 1;
enum int LUA_LIBRARY_COROUTINE = 1 << 2;
enum int LUA_LIBRARY_MATH = 1 << 5;
enum int LUA_LIBRARY_STRING = 1 << 7;
enum int LUA_LIBRARY_TABLE = 1 << 8;
enum int LUA_LIBRARY_UTF8 = 1 << 9;
enum int LUA_SAFE_LIBRARIES = LUA_LIBRARY_BASE | LUA_LIBRARY_PACKAGE | LUA_LIBRARY_COROUTINE | LUA_LIBRARY_MATH | LUA_LIBRARY_STRING | LUA_LIBRARY_TABLE | LUA_LIBRARY_UTF8;
enum size_t SCRIPT_DIR_CAPACITY = 1024;
enum size_t FRAME_TEXT_CAPACITY = 64;

enum string PRELUDE = import("prelude.lua");

alias LuaFunction = extern (C) int function(lua_State*);

struct ScriptHost {
    lua_State* lua;
    Game* game;
    FILE* report;
    uint frames;
    uint failures;
    int frameHook = LUA_NO_REF;
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
    registerApi(host);
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
    lua_pushstring(host.lua, directory.ptr);
    lua_setglobal(host.lua, "SCRIPT_DIR");
    bool ok = callChunk(host, luaL_loadbufferx(host.lua, PRELUDE.ptr, PRELUDE.length, "=prelude", null));
    if (ok) {
        ok = callChunk(host, luaL_loadfilex(host.lua, path, null));
    }
    return ok;
}

void closeScript(ScriptHost* host) {
    if (host.lua !is null) {
        lua_close(host.lua);
        host.lua = null;
    }
}

bool callChunk(ScriptHost* host, int loadStatus) {
    bool ok = loadStatus == LUA_STATUS_OK;
    if (ok) {
        lua_pushcclosure(host.lua, cast(lua_CFunction) &luaTraceback, 0);
        lua_rotate(host.lua, LUA_BELOW_TOP, LUA_ROTATE_ONE);
        ok = lua_pcallk(host.lua, 0, 0, LUA_BELOW_TOP, 0, null) == LUA_STATUS_OK;
        if (ok) {
            lua_settop(host.lua, LUA_POP_ONE);
        } else {
            reportError(host);
            lua_settop(host.lua, LUA_POP_TWO);
        }
    } else {
        reportError(host);
        lua_settop(host.lua, LUA_POP_ONE);
    }
    return ok;
}

void reportError(ScriptHost* host) {
    if (host.report !is null) {
        fprintf(host.report, "script error: %s\n", lua_tolstring(host.lua, LUA_TOP, null));
    }
}

void registerApi(ScriptHost* host) {
    registerFunction(host, "frames", &luaFrames);
    registerFunction(host, "hold", &luaHold);
    registerFunction(host, "release", &luaRelease);
    registerFunction(host, "release_all", &luaReleaseAll);
    registerFunction(host, "mode", &luaMode);
    registerFunction(host, "material", &luaMaterial);
    registerFunction(host, "break_block", &luaBreakBlock);
    registerFunction(host, "place_block", &luaPlaceBlock);
    registerFunction(host, "time", &luaTime);
    registerFunction(host, "traveled", &luaTraveled);
    registerFunction(host, "on_ground", &luaOnGround);
    registerFunction(host, "speed", &luaSpeed);
    registerFunction(host, "horizontal_speed", &luaHorizontalSpeed);
    registerFunction(host, "worldgen", &luaWorldgen);
    registerFunction(host, "vacc", &luaVacc);
    registerFunction(host, "every_frame", &luaEveryFrame);
    registerFunction(host, "check", &luaCheck);
}

void registerFunction(ScriptHost* host, const(char)* name, LuaFunction fn) {
    lua_pushlightuserdata(host.lua, host);
    lua_pushcclosure(host.lua, cast(lua_CFunction) fn, 1);
    lua_setglobal(host.lua, name);
}

bool stepOnce(ScriptHost* host, float dt, float yaw, float pitch) {
    FrameInput input;
    input.held = host.held;
    input.yaw = yaw;
    input.pitch = pitch;
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

float magnitude(float[3] v) {
    return sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
}

ScriptHost* hostOf(lua_State* lua) {
    return cast(ScriptHost*) lua_touserdata(lua, LUA_FIRST_UPVALUE);
}

bool isNoneOrNil(lua_State* lua, int index) {
    return lua_type(lua, index) <= 0;
}

extern (C) int luaTraceback(lua_State* lua) {
    luaL_traceback(lua, lua, lua_tolstring(lua, 1, null), LUA_TRACEBACK_LEVEL);
    return 1;
}

extern (C) int luaFrames(lua_State* lua) {
    ScriptHost* host = hostOf(lua);
    lua_Integer count = luaL_checkinteger(lua, 1);
    float dt = cast(float) luaL_checknumber(lua, 2);
    float yaw = cast(float) luaL_optnumber(lua, 3, 0);
    float pitch = cast(float) luaL_optnumber(lua, 4, 0);
    if (count < 0 || !(dt > 0)) {
        luaL_error(lua, "frames: need n >= 0 and dt > 0");
    } else if (host.stepping) {
        luaL_error(lua, "frames: every_frame hooks cannot advance time");
    } else {
        bool ok = true;
        lua_Integer frame = 0;
        while (ok && frame < count) {
            ok = stepOnce(host, dt, yaw, pitch);
            frame += 1;
        }
        if (!ok) {
            lua_error(lua);
        }
    }
    return 0;
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
    ScriptHost* host = hostOf(lua);
    foreach (index; 1 .. lua_gettop(lua) + 1) {
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
    hostOf(lua).held[] = false;
    return 0;
}

extern (C) int luaMode(lua_State* lua) {
    ScriptHost* host = hostOf(lua);
    if (!isNoneOrNil(lua, 1)) {
        const(char)* name = luaL_checklstring(lua, 1, null);
        if (!setMode(host.game, name[0 .. strlen(name)])) {
            luaL_error(lua, "unknown mode '%s'", name);
        }
    }
    lua_pushstring(lua, modeName(host.game));
    return 1;
}

extern (C) int luaMaterial(lua_State* lua) {
    ScriptHost* host = hostOf(lua);
    if (!isNoneOrNil(lua, 1)) {
        lua_Integer slot = luaL_checkinteger(lua, 1);
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
    lua_pushboolean(lua, gameBreakBlock(hostOf(lua).game));
    return 1;
}

extern (C) int luaPlaceBlock(lua_State* lua) {
    lua_pushboolean(lua, gamePlaceBlock(hostOf(lua).game));
    return 1;
}

extern (C) int luaTime(lua_State* lua) {
    lua_pushnumber(lua, hostOf(lua).game.simTime);
    return 1;
}

extern (C) int luaTraveled(lua_State* lua) {
    ScriptHost* host = hostOf(lua);
    lua_pushnumber(lua, host.game.traveled * metersPerAbsolute(host));
    return 1;
}

extern (C) int luaOnGround(lua_State* lua) {
    lua_pushboolean(lua, hostOf(lua).game.characterState.onGround);
    return 1;
}

extern (C) int luaSpeed(lua_State* lua) {
    ScriptHost* host = hostOf(lua);
    lua_pushnumber(lua, magnitude(host.game.characterState.velocity) * metersPerAbsolute(host));
    return 1;
}

extern (C) int luaHorizontalSpeed(lua_State* lua) {
    ScriptHost* host = hostOf(lua);
    float[3] v = host.game.characterState.velocity;
    float[3] up = host.game.character.up;
    float along = v[0] * up[0] + v[1] * up[1] + v[2] * up[2];
    lua_pushnumber(lua, magnitude([v[0] - up[0] * along, v[1] - up[1] * along, v[2] - up[2] * along]) * metersPerAbsolute(host));
    return 1;
}

extern (C) int luaWorldgen(lua_State* lua) {
    ScriptHost* host = hostOf(lua);
    const(char)* name = luaL_checklstring(lua, 1, null);
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

extern (C) int luaVacc(lua_State* lua) {
    ScriptHost* host = hostOf(lua);
    lua_pushnumber(lua, host.game.vacc * metersPerAbsolute(host));
    return 1;
}

extern (C) int luaEveryFrame(lua_State* lua) {
    ScriptHost* host = hostOf(lua);
    if (host.frameHook != LUA_NO_REF) {
        luaL_unref(lua, LUA_REGISTRY, host.frameHook);
        host.frameHook = LUA_NO_REF;
    }
    if (!isNoneOrNil(lua, 1)) {
        luaL_checktype(lua, 1, LUA_TYPE_FUNCTION);
        lua_pushvalue(lua, 1);
        host.frameHook = luaL_ref(lua, LUA_REGISTRY);
    }
    return 0;
}

extern (C) int luaCheck(lua_State* lua) {
    ScriptHost* host = hostOf(lua);
    luaL_checkany(lua, 1);
    int passed = lua_toboolean(lua, 1);
    if (!passed) {
        const(char)* message = luaL_optlstring(lua, 2, "check failed", null);
        luaL_where(lua, LUA_TRACEBACK_LEVEL);
        if (host.report !is null) {
            fprintf(host.report, "FAIL %s%s (t=%.2fs)\n", lua_tolstring(lua, LUA_TOP, null), message, cast(double) host.game.simTime);
        }
        host.failures += 1;
    }
    lua_pushboolean(lua, passed);
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
                fprintf(recorder.file, "%s(\"%.*s\")\n", call, cast(int) KEY_NAMES[i].length, KEY_NAMES[i].ptr);
            }
        }
        recorder.held = input.held;
        char[FRAME_TEXT_CAPACITY] frameText;
        snprintf(frameText.ptr, frameText.length, "%.6f, %.6f, %.6f", cast(double) dt, cast(double) input.yaw, cast(double) input.pitch);
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
        fprintf(recorder.file, "frames(%u, %s)\n", recorder.pendingCount, recorder.pendingFrame.ptr);
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
