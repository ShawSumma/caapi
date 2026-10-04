module client.script;

import core.stdc.math : floor;
import core.stdc.stdio : FILE, fclose, fopen, fprintf;
import core.stdc.string : strlen;
import bindings.lua : luaL_checkinteger, luaL_checklstring, luaL_checknumber, luaL_checktype, luaL_error, luaL_loadfilex, luaL_newstate, luaL_openselectedlibs, luaL_optinteger, luaL_optnumber, luaL_ref, luaL_traceback, luaL_unref, lua_CFunction, lua_Integer, lua_State, lua_callk, lua_close, lua_createtable, lua_getglobal, lua_gettop, lua_pcallk, lua_pushboolean, lua_pushcclosure, lua_pushinteger, lua_pushlightuserdata, lua_pushlstring, lua_pushnil, lua_pushnumber, lua_pushstring, lua_pushvalue, lua_rawgeti, lua_setfield, lua_setglobal, lua_settop, lua_tolstring, lua_touserdata, lua_type;
import client.game : FrameInput, Game, KEY_COUNT, KEY_NAMES, KeyLookup, MATERIAL_PALETTE;
import client.world : TargetMaterial;
import common.array : Array;
import common.graph : NodeId;
import common.material : MATERIAL_NAMES;
import common.vector3 : dot, magnitude, rejectAlong;
import common.worldgen.generation : WorldgenKind, WorldgenLookup, WorldgenSettings;

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
enum float DEFAULT_TIMESTEP_SECONDS = 0.016f;
enum double RADIANS_PER_DEGREE = 0.017453292519943295;
enum string MODULE_PATTERN = "?.lua";

alias LuaFunction = extern (C) int function(lua_State*);

struct ScriptHost {
    lua_State* lua;
    Game* game;
    FILE* report;
    float timestepSeconds = DEFAULT_TIMESTEP_SECONDS;
    float yawRadiansPerSecond = 0;
    float pitchRadiansPerSecond = 0;
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

    void step(float dt) {
        if (!(dt > 0)) {
            luaL_error(lua, "the timestep must be positive");
        } else if (isStepping) {
            luaL_error(lua, "a step hook cannot advance time");
        } else {
            game.step(FrameInput(yawRadiansPerSecond * dt, pitchRadiansPerSecond * dt, isHeld), dt);
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

    void wait(double seconds, float dt) {
        if (!(seconds >= 0)) {
            luaL_error(lua, "cannot wait a negative time");
        } else if (!(dt > 0)) {
            luaL_error(lua, "the timestep must be positive");
        } else {
            foreach (_; 0 .. cast(ulong) floor(seconds / dt + 0.5)) {
                step(dt);
            }
        }
    }

    void setKeys(int firstArgument, bool isPressed) {
        foreach (index; firstArgument .. lua_gettop(lua) + 1) {
            const(char)* name = luaL_checklstring(lua, index, null);
            KeyLookup lookup = KeyLookup.fromName(name[0 .. strlen(name)]);
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

float timestepArgument(lua_State* lua, int index, float fallback) {
    return cast(float) luaL_optnumber(lua, index, fallback);
}

extern (C) int luaTraceback(lua_State* lua) {
    luaL_traceback(lua, lua, lua_tolstring(lua, 1, null), LUA_TRACEBACK_LEVEL);
    return 1;
}

extern (C) int luaWait(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    host.wait(luaL_checknumber(lua, SELF + 1), timestepArgument(lua, SELF + 2, host.timestepSeconds));
    return 0;
}

extern (C) int luaStep(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    host.step(timestepArgument(lua, SELF + 1, host.timestepSeconds));
    return 0;
}

extern (C) int luaTimestep(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    if (!isNoneOrNil(lua, SELF + 1)) {
        float seconds = cast(float) luaL_checknumber(lua, SELF + 1);
        if (!(seconds > 0)) {
            luaL_error(lua, "the timestep must be positive");
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
    WorldgenLookup lookup = WorldgenLookup.fromName(name[0 .. strlen(name)]);
    uint seed = cast(uint) luaL_optinteger(lua, SELF + 2, 0);
    if (host.steps > 0) {
        luaL_error(lua, "worldgen must be chosen before the first step");
    } else if (!lookup.isFound) {
        luaL_error(lua, "unknown worldgen '%s'", name);
    } else {
        host.game.setWorldgen(WorldgenSettings(NodeId.init, seed, lookup.kind));
    }
    return 0;
}

extern (C) int luaEnterStructure(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    float meters = cast(float) luaL_checknumber(lua, SELF + 1);
    if (host.game.world.graph.worldgen.kind != WorldgenKind.structure) {
        luaL_error(lua, "enter_structure needs the structure worldgen");
    } else {
        host.game.enterStructure(meters);
    }
    return 0;
}

extern (C) int luaTargetMaterial(lua_State* lua) {
    TargetMaterial target = methodHost(lua).game.world.targetMaterial();
    if (target.isFound) {
        lua_pushstring(lua, MATERIAL_NAMES[target.material].ptr);
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
    host.wait(seconds, host.timestepSeconds);
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

extern (C) int luaTurn(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    double seconds = luaL_checknumber(lua, SELF + 3);
    float restingYaw = host.yawRadiansPerSecond;
    float restingPitch = host.pitchRadiansPerSecond;
    host.yawRadiansPerSecond = cast(float)(luaL_checknumber(lua, SELF + 1) / seconds * RADIANS_PER_DEGREE);
    host.pitchRadiansPerSecond = cast(float)(luaL_checknumber(lua, SELF + 2) / seconds * RADIANS_PER_DEGREE);
    host.wait(seconds, host.timestepSeconds);
    host.yawRadiansPerSecond = restingYaw;
    host.pitchRadiansPerSecond = restingPitch;
    return 0;
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
    lua_pushboolean(lua, methodHost(lua).game.breakBlock());
    return 1;
}

extern (C) int luaPlaceBlock(lua_State* lua) {
    lua_pushboolean(lua, methodHost(lua).game.placeBlock());
    return 1;
}

extern (C) int luaTraveled(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, host.game.traveled * host.metersPerAbsolute());
    return 1;
}

extern (C) int luaIsOnGround(lua_State* lua) {
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
    lua_pushnumber(lua, host.game.characterState.velocity.magnitude * host.metersPerAbsolute());
    return 1;
}

extern (C) int luaHorizontalSpeed(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, host.game.characterState.velocity.rejectAlong(host.game.camera.up).magnitude * host.metersPerAbsolute());
    return 1;
}

extern (C) int luaVerticalSpeed(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, host.game.characterState.velocity.dot(host.game.camera.up) * host.metersPerAbsolute());
    return 1;
}

extern (C) int luaCameraVerticalAcceleration(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_pushnumber(lua, host.game.cameraVerticalAcceleration * host.metersPerAbsolute());
    return 1;
}

struct ScriptRecorder {
    FILE* file;
    float pendingDt = 0;
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

    void recordFrame(FrameInput input, float dt) {
        foreach (i; 0 .. KEY_COUNT) {
            if (input.isHeld[i] != isHeld[i]) {
                flush();
                fprintf(file, "  world:%s(\"%.*s\")\n", keyCall(input.isHeld[i]), cast(int) KEY_NAMES[i].length, KEY_NAMES[i].ptr);
            }
        }
        isHeld = input.isHeld;
        if (input.yaw != 0 || input.pitch != 0) {
            flush();
            fprintf(file, "  world:look(%.9g, %.9g)\n", input.yaw / RADIANS_PER_DEGREE, input.pitch / RADIANS_PER_DEGREE);
        }
        if (dt != pendingDt) {
            flush();
            pendingDt = dt;
        }
        pendingSteps += 1;
    }

    void recordEvent(const(char)* call) {
        flush();
        fprintf(file, "  %s\n", call);
    }

    void flush() {
        if (pendingSteps > 0) {
            fprintf(file, "  world:wait(%.9g, %.9g)\n", pendingSteps * cast(double) pendingDt, cast(double) pendingDt);
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
