module client.script;

import core.stdc.stdio : FILE, fclose, fopen, fprintf, snprintf;
import core.stdc.string : strcmp, strlen;
import bindings.lua : luaL_checkany, luaL_checkinteger, luaL_checklstring, luaL_checknumber, luaL_checktype, luaL_error, luaL_loadbufferx, luaL_newstate, luaL_openselectedlibs, luaL_optlstring, luaL_optnumber, luaL_ref, luaL_traceback, luaL_unref, luaL_where, lua_CFunction, lua_Integer, lua_State, lua_callk, lua_close, lua_createtable, lua_gettop, lua_pcallk, lua_pushboolean, lua_pushcclosure, lua_pushinteger, lua_pushlightuserdata, lua_pushnil, lua_pushnumber, lua_pushstring, lua_pushvalue, lua_rawgeti, lua_setfield, lua_setglobal, lua_toboolean, lua_tolstring, lua_touserdata, lua_type;
import client.game : FrameInput, Game, KEY_COUNT, KEY_NAMES, KeyLookup, MATERIAL_PALETTE, keyFromName;
import common.vector3 : dot3, magnitude3, rejectAlong;

enum int LUA_REGISTRY = -(int.max / 2 + 1000);
enum int LUA_FIRST_UPVALUE = LUA_REGISTRY - 1;
enum int LUA_NO_REF = -2;
enum int LUA_TOP = -1;
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
enum int PRELUDE_ARGUMENTS = 2;
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
    bool[KEY_COUNT] isHeld;
    bool isStepping;

    bool run(const(char)* path) {
        lua = luaL_newstate();
        luaL_openselectedlibs(lua, LUA_SAFE_LIBRARIES, 0);
        lua_pushnil(lua);
        lua_setglobal(lua, "print");
        lua_pushnil(lua);
        lua_setglobal(lua, "warn");
        createWorld();
        lua_pushcclosure(lua, cast(lua_CFunction) &luaTraceback, 0);
        immutable int loadStatus = luaL_loadbufferx(lua, PRELUDE.ptr, PRELUDE.length, "=prelude", null);
        if (loadStatus != LUA_STATUS_OK) {
            reportError();
            return false;
        } else {
            lua_rawgeti(lua, LUA_REGISTRY, worldRef);
            lua_pushstring(lua, path);
            immutable int runStatus = lua_pcallk(lua, PRELUDE_ARGUMENTS, 0, TRACEBACK_INDEX, 0, null);
            if (runStatus != LUA_STATUS_OK) {
                reportError();
                return false;
            } else {
                return true;
            }
        }
    }

    void close() {
        lua_close(lua);
        lua = null;
    }

    void reportError() {
        fprintf(report, "script error: %s\n", lua_tolstring(lua, LUA_TOP, null));
    }

    void createWorld() {
        lua_createtable(lua, 0, 0);
        registerMethod("frames", &luaFrames);
        registerMethod("timestep", &luaTimestep);
        registerMethod("time", &luaTime);
        registerMethod("worldgen", &luaWorldgen);
        registerMethod("every_frame", &luaEveryFrame);
        registerMethod("check", &luaCheck);
        lua_createtable(lua, 0, 0);
        registerMethod("hold", &luaHold);
        registerMethod("release", &luaRelease);
        registerMethod("release_all", &luaReleaseAll);
        registerMethod("look", &luaLook);
        registerMethod("turn_rate", &luaTurnRate);
        registerMethod("mode", &luaMode);
        registerMethod("material", &luaMaterial);
        registerMethod("break_block", &luaBreakBlock);
        registerMethod("place_block", &luaPlaceBlock);
        registerMethod("traveled", &luaTraveled);
        registerMethod("on_ground", &luaOnGround);
        registerMethod("altitude", &luaAltitude);
        registerMethod("speed", &luaSpeed);
        registerMethod("horizontal_speed", &luaHorizontalSpeed);
        registerMethod("vertical_speed", &luaVerticalSpeed);
        registerMethod("camera_vertical_acceleration", &luaCameraVerticalAcceleration);
        lua_setfield(lua, -2, "player");
        worldRef = luaL_ref(lua, LUA_REGISTRY);
    }

    void registerMethod(const(char)* name, LuaFunction fn) {
        lua_pushlightuserdata(lua, &this);
        lua_pushcclosure(lua, cast(lua_CFunction) fn, 1);
        lua_setfield(lua, -2, name);
    }

    void step(float dt) {
        FrameInput input;
        input.isHeld = isHeld;
        input.yaw = yawRadiansPerSecond * dt;
        input.pitch = pitchRadiansPerSecond * dt;
        game.step(input, dt);
        frames += 1;
        if (frameHook != LUA_NO_REF) {
            isStepping = true;
            lua_rawgeti(lua, LUA_REGISTRY, frameHook);
            lua_callk(lua, 0, 0, 0, null);
            isStepping = false;
        }
    }

    void setKeys(bool isPressed) {
        foreach (index; SELF + 1 .. lua_gettop(lua) + 1) {
            const(char)* name = luaL_checklstring(lua, index, null);
            KeyLookup lookup = keyFromName(name[0 .. strlen(name)]);
            if (lookup.isFound) {
                isHeld[lookup.key] = isPressed;
            } else {
                luaL_error(lua, "unknown key '%s'", name);
            }
        }
    }

    float metersPerAbsolute() const {
        return 1.0f / game.simConfig.metersToAbsolute;
    }
}

ScriptHost* methodHost(lua_State* lua) {
    luaL_checktype(lua, SELF, LUA_TYPE_TABLE);
    return cast(ScriptHost*) lua_touserdata(lua, LUA_FIRST_UPVALUE);
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
    } else if (host.isStepping) {
        luaL_error(lua, "frames: every_frame hooks cannot advance time");
    } else {
        foreach (frame; 0 .. count) {
            host.step(dt);
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
        host.game.setWorldgen(kind == "flat");
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
    immutable int passed = lua_toboolean(lua, SELF + 1);
    if (!passed) {
        const(char)* message = luaL_optlstring(lua, SELF + 2, "check failed", null);
        luaL_where(lua, LUA_TRACEBACK_LEVEL);
        fprintf(host.report, "FAIL %s%s (t=%.2fs)\n", lua_tolstring(lua, LUA_TOP, null), message, cast(double) host.game.simTime);
        host.failures += 1;
    }
    lua_pushboolean(lua, passed);
    return 1;
}

extern (C) int luaHold(lua_State* lua) {
    methodHost(lua).setKeys(true);
    return 0;
}

extern (C) int luaRelease(lua_State* lua) {
    methodHost(lua).setKeys(false);
    return 0;
}

extern (C) int luaReleaseAll(lua_State* lua) {
    methodHost(lua).isHeld[] = false;
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
        immutable bool isKnown = host.game.setMode(name[0 .. strlen(name)]);
        if (!isKnown) {
            luaL_error(lua, "unknown mode '%s'", name);
        }
    }
    lua_pushstring(lua, host.game.modeName());
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
    immutable bool isBroken = methodHost(lua).game.breakBlock();
    lua_pushboolean(lua, isBroken);
    return 1;
}

extern (C) int luaPlaceBlock(lua_State* lua) {
    immutable bool isPlaced = methodHost(lua).game.placeBlock();
    lua_pushboolean(lua, isPlaced);
    return 1;
}

extern (C) int luaTraveled(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, host.game.traveled * host.metersPerAbsolute());
    return 1;
}

extern (C) int luaOnGround(lua_State* lua) {
    lua_pushboolean(lua, methodHost(lua).game.characterState.isOnGround);
    return 1;
}

extern (C) int luaAltitude(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, host.game.characterAltitude() * host.metersPerAbsolute());
    return 1;
}

extern (C) int luaSpeed(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, magnitude3(host.game.characterState.velocity) * host.metersPerAbsolute());
    return 1;
}

extern (C) int luaHorizontalSpeed(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, magnitude3(rejectAlong(host.game.characterState.velocity, host.game.character.up)) * host.metersPerAbsolute());
    return 1;
}

extern (C) int luaVerticalSpeed(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, dot3(host.game.characterState.velocity, host.game.character.up) * host.metersPerAbsolute());
    return 1;
}

extern (C) int luaCameraVerticalAcceleration(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, host.game.vacc * host.metersPerAbsolute());
    return 1;
}

struct ScriptRecorder {
    FILE* file;
    uint pendingCount;
    char[FRAME_TEXT_CAPACITY] pendingFrame = 0;
    bool[KEY_COUNT] isHeld;

    bool open(const(char)* path) {
        file = fopen(path, "w");
        if (file is null) {
            return false;
        } else {
            fprintf(file, "local world = ...\nlocal player = world.player\n");
            return true;
        }
    }

    void recordFrame(FrameInput input, float dt) {
        foreach (i; 0 .. KEY_COUNT) {
            if (input.isHeld[i] != isHeld[i]) {
                flush();
                fprintf(file, "player:%s(\"%.*s\")\n", keyCall(input.isHeld[i]), cast(int) KEY_NAMES[i].length, KEY_NAMES[i].ptr);
            }
        }
        isHeld = input.isHeld;
        if (input.yaw != 0 || input.pitch != 0) {
            flush();
            fprintf(file, "player:look(%.9g, %.9g)\n", input.yaw / RADIANS_PER_DEGREE, input.pitch / RADIANS_PER_DEGREE);
        }
        char[FRAME_TEXT_CAPACITY] frameText;
        snprintf(frameText.ptr, frameText.length, "%.9g", cast(double) dt);
        if (strcmp(frameText.ptr, pendingFrame.ptr) != 0) {
            flush();
            pendingFrame = frameText;
        }
        pendingCount += 1;
    }

    void recordEvent(const(char)* call) {
        flush();
        fprintf(file, "%s\n", call);
    }

    void flush() {
        if (pendingCount > 0) {
            fprintf(file, "world:frames(%u, %s)\n", pendingCount, pendingFrame.ptr);
        }
        pendingCount = 0;
        pendingFrame[0] = 0;
    }

    void close() {
        flush();
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
