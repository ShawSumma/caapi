module client.script;

import std.format : format;
import std.math : sqrt;
import std.path : dirName;
import std.stdio : File, stdout, writefln, writeln;
import std.string : fromStringz, toStringz;
import bindings.lua;
import client.game : Game, FrameInput, InputState, Key, KEY_NAMES, MATERIAL_PALETTE,
    keyFromName, modeName, setMode;

// Lua's API is mostly macros ImportC can't see; these are their values.
enum int LUA_REGISTRY = -(int.max / 2 + 1000);
enum int LUA_NO_REF = -2;
enum int LUA_STATUS_OK = 0;
enum int LUA_TYPE_FUNCTION = 6;

alias LuaFunction = extern (C) int function(lua_State*);

enum string PRELUDE = import("prelude.lua");
enum uint STATUS_INTERVAL_FRAMES = 60;

/// Runs a Lua script against a Game. The script owns time: nothing advances
/// except through `frames`, so a run is a pure function of the script.
/// Script-facing quantities are meters and seconds, like `*Raw` config.
struct ScriptHost {
    lua_State* L;
    Game* game;
    InputState keys;
    uint frames;
    uint failures;
    int frameHook = LUA_NO_REF;
    // The every_frame hook may observe but must not advance time.
    bool stepping;
    // Worst vertical acceleration since the last status line, absolute units.
    float statusVacc = 0;

    float metersPerAbsolute() const {
        return 1.0f / game.simCfg.metersToAbsolute;
    }

    /// Runs the prelude and then the script at `path`. False on a Lua error
    /// (already reported); failed checks are counted in `failures`.
    bool run(string path) {
        L = luaL_newstate();
        luaL_openselectedlibs(L, ~0, 0);
        registerApi();
        lua_pushstring(L, dirName(path).toStringz);
        lua_setglobal(L, "SCRIPT_DIR");
        if (!callChunk(luaL_loadbufferx(L, PRELUDE.ptr, PRELUDE.length, "=prelude", null))) {
            return false;
        }
        return callChunk(luaL_loadfilex(L, path.toStringz, null));
    }

    void close() {
        if (L !is null) {
            lua_close(L);
            L = null;
        }
    }

    bool callChunk(int loadStatus) {
        if (loadStatus != LUA_STATUS_OK) {
            writefln("script error: %s", fromStringz(lua_tolstring(L, -1, null)));
            lua_settop(L, -2);
            return false;
        }
        lua_pushcclosure(L, cast(lua_CFunction) &luaTraceback, 0);
        lua_rotate(L, -2, 1);
        int status = lua_pcallk(L, 0, 0, -2, 0, null);
        if (status != LUA_STATUS_OK) {
            writefln("script error: %s", fromStringz(lua_tolstring(L, -1, null)));
            lua_settop(L, -3);
            return false;
        }
        lua_settop(L, -2);
        return true;
    }

    void registerApi() {
        register("frames", &luaFrames);
        register("hold", &luaHold);
        register("release", &luaRelease);
        register("release_all", &luaReleaseAll);
        register("mode", &luaMode);
        register("material", &luaMaterial);
        register("break_block", &luaBreakBlock);
        register("place_block", &luaPlaceBlock);
        register("time", &luaTime);
        register("traveled", &luaTraveled);
        register("on_ground", &luaOnGround);
        register("speed", &luaSpeed);
        register("horizontal_speed", &luaHorizontalSpeed);
        register("worldgen", &luaWorldgen);
        register("vacc", &luaVacc);
        register("every_frame", &luaEveryFrame);
        register("check", &luaCheck);
        register("status", &luaStatus);
    }

    void register(const(char)* name, LuaFunction fn) {
        lua_pushlightuserdata(L, &this);
        lua_pushcclosure(L, cast(lua_CFunction) fn, 1);
        lua_setglobal(L, name);
    }

    /// Advances one frame and runs the every_frame hook. On a hook error the
    /// message is left on the Lua stack and false is returned.
    bool stepOnce(float dt, float yaw, float pitch) {
        FrameInput input;
        input.keys = keys;
        input.yaw = yaw;
        input.pitch = pitch;
        game.step(input, dt);
        frames++;
        if (game.vacc > statusVacc) {
            statusVacc = game.vacc;
        }
        if (frames % STATUS_INTERVAL_FRAMES == 0) {
            printStatus();
        }
        if (frameHook == LUA_NO_REF) {
            return true;
        }
        stepping = true;
        lua_rawgeti(L, LUA_REGISTRY, frameHook);
        int status = lua_pcallk(L, 0, 0, 0, 0, null);
        stepping = false;
        return status == LUA_STATUS_OK;
    }

    void printStatus() {
        float m = metersPerAbsolute();
        writefln("t=%.2f mode=%s ground=%s speed=%.2f traveled=%.2f vacc=%.1f",
            game.simTime, modeName(game.flyMode, game.noClip), game.onGround,
            speedOf(game.velocity) * m, game.traveled * m, statusVacc * m);
        statusVacc = 0;
        stdout.flush();
    }
}

float speedOf(const float[3] v) {
    return sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
}

ScriptHost* hostOf(lua_State* L) {
    return cast(ScriptHost*) lua_touserdata(L, LUA_REGISTRY - 1);
}

bool isNoneOrNil(lua_State* L, int idx) {
    return lua_type(L, idx) <= 0;
}

extern (C) int luaTraceback(lua_State* L) {
    luaL_traceback(L, L, lua_tolstring(L, 1, null), 1);
    return 1;
}

/// frames(n, dt, yaw, pitch): n frames of dt seconds, turning by yaw and
/// pitch radians per frame, with the currently held keys.
extern (C) int luaFrames(lua_State* L) {
    ScriptHost* host = hostOf(L);
    lua_Integer n = luaL_checkinteger(L, 1);
    float dt = cast(float) luaL_checknumber(L, 2);
    float yaw = cast(float) luaL_optnumber(L, 3, 0);
    float pitch = cast(float) luaL_optnumber(L, 4, 0);
    if (n < 0 || !(dt > 0)) {
        return luaL_error(L, "frames: need n >= 0 and dt > 0");
    }
    if (host.stepping) {
        return luaL_error(L, "frames: every_frame hooks cannot advance time");
    }
    foreach (i; 0 .. n) {
        if (!host.stepOnce(dt, yaw, pitch)) {
            return lua_error(L);
        }
    }
    return 0;
}

extern (C) int luaHold(lua_State* L) {
    return setKeys(L, true);
}

extern (C) int luaRelease(lua_State* L) {
    return setKeys(L, false);
}

int setKeys(lua_State* L, bool held) {
    ScriptHost* host = hostOf(L);
    int top = lua_gettop(L);
    foreach (i; 1 .. top + 1) {
        const(char)* name = luaL_checklstring(L, i, null);
        Key key;
        if (!keyFromName(fromStringz(name), key)) {
            return luaL_error(L, "unknown key '%s'", name);
        }
        host.keys.held[key] = held;
    }
    return 0;
}

extern (C) int luaReleaseAll(lua_State* L) {
    hostOf(L).keys.clear();
    return 0;
}

/// mode() -> name; mode(name) sets "walk", "fly" or "noclip".
extern (C) int luaMode(lua_State* L) {
    ScriptHost* host = hostOf(L);
    if (!isNoneOrNil(L, 1)) {
        const(char)* name = luaL_checklstring(L, 1, null);
        if (!setMode(*host.game, fromStringz(name))) {
            return luaL_error(L, "unknown mode '%s'", name);
        }
    }
    lua_pushstring(L, modeName(host.game.flyMode, host.game.noClip).toStringz);
    return 1;
}

/// material() -> slot; material(slot) selects palette slot 1..9.
extern (C) int luaMaterial(lua_State* L) {
    ScriptHost* host = hostOf(L);
    if (!isNoneOrNil(L, 1)) {
        lua_Integer slot = luaL_checkinteger(L, 1);
        if (slot < 1 || slot > MATERIAL_PALETTE.length) {
            return luaL_error(L, "material slot must be 1..%d", cast(int) MATERIAL_PALETTE.length);
        }
        host.game.materialIndex = cast(int) slot - 1;
    }
    lua_pushinteger(L, host.game.materialIndex + 1);
    return 1;
}

extern (C) int luaBreakBlock(lua_State* L) {
    lua_pushboolean(L, hostOf(L).game.breakBlock() ? 1 : 0);
    return 1;
}

extern (C) int luaPlaceBlock(lua_State* L) {
    lua_pushboolean(L, hostOf(L).game.placeBlock() ? 1 : 0);
    return 1;
}

extern (C) int luaTime(lua_State* L) {
    lua_pushnumber(L, hostOf(L).game.simTime);
    return 1;
}

/// Odometer in meters.
extern (C) int luaTraveled(lua_State* L) {
    ScriptHost* host = hostOf(L);
    lua_pushnumber(L, host.game.traveled * host.metersPerAbsolute());
    return 1;
}

extern (C) int luaOnGround(lua_State* L) {
    lua_pushboolean(L, hostOf(L).game.onGround ? 1 : 0);
    return 1;
}

/// Character speed in meters per second.
extern (C) int luaSpeed(lua_State* L) {
    ScriptHost* host = hostOf(L);
    lua_pushnumber(L, speedOf(host.game.velocity) * host.metersPerAbsolute());
    return 1;
}

/// Speed perpendicular to the local up direction, meters per second.
extern (C) int luaHorizontalSpeed(lua_State* L) {
    ScriptHost* host = hostOf(L);
    const(float[3]) v = host.game.velocity;
    const(float[3]) up = host.game.character.up;
    float along = v[0] * up[0] + v[1] * up[1] + v[2] * up[2];
    float[3] h = [v[0] - up[0] * along, v[1] - up[1] * along, v[2] - up[2] * along];
    lua_pushnumber(L, speedOf(h) * host.metersPerAbsolute());
    return 1;
}

/// worldgen("flat" | "terrain"): chooses world generation. Only before the
/// first frame, since chunks generated earlier would keep the old kind.
extern (C) int luaWorldgen(lua_State* L) {
    ScriptHost* host = hostOf(L);
    const(char)* name = luaL_checklstring(L, 1, null);
    if (host.frames > 0) {
        return luaL_error(L, "worldgen must be chosen before the first frame");
    }
    const(char)[] kind = fromStringz(name);
    if (kind != "flat" && kind != "terrain") {
        return luaL_error(L, "unknown worldgen '%s'", name);
    }
    host.game.world.worldgenDriver.flatWorldgen = kind == "flat";
    return 0;
}

/// Vertical camera acceleration over the last frame, meters per second^2.
extern (C) int luaVacc(lua_State* L) {
    ScriptHost* host = hostOf(L);
    lua_pushnumber(L, host.game.vacc * host.metersPerAbsolute());
    return 1;
}

/// every_frame(fn) runs fn after each frame; every_frame(nil) clears it.
extern (C) int luaEveryFrame(lua_State* L) {
    ScriptHost* host = hostOf(L);
    if (host.frameHook != LUA_NO_REF) {
        luaL_unref(L, LUA_REGISTRY, host.frameHook);
        host.frameHook = LUA_NO_REF;
    }
    if (isNoneOrNil(L, 1)) {
        return 0;
    }
    luaL_checktype(L, 1, LUA_TYPE_FUNCTION);
    lua_pushvalue(L, 1);
    host.frameHook = luaL_ref(L, LUA_REGISTRY);
    return 0;
}

/// check(cond, message): reports and counts a failure without stopping.
extern (C) int luaCheck(lua_State* L) {
    ScriptHost* host = hostOf(L);
    luaL_checkany(L, 1);
    if (lua_toboolean(L, 1)) {
        lua_pushboolean(L, 1);
        return 1;
    }
    const(char)* message = luaL_optlstring(L, 2, "check failed", null);
    luaL_where(L, 1);
    writefln("FAIL %s%s (t=%.2fs)", fromStringz(lua_tolstring(L, -1, null)),
        fromStringz(message), host.game.simTime);
    stdout.flush();
    host.failures++;
    lua_pushboolean(L, 0);
    return 1;
}

extern (C) int luaStatus(lua_State* L) {
    hostOf(L).printStatus();
    return 0;
}

/// Writes live play as a Lua script the headless runner can replay exactly:
/// key changes and events as calls, runs of identical frames merged into
/// one `frames` call.
struct ScriptRecorder {
    File file;
    InputState keys;
    string pendingFrame;
    uint pendingCount;

    void open(string path) {
        file = File(path, "w");
        file.writeln("-- recorded by mined --record");
    }

    bool isOpen() const {
        return file.isOpen;
    }

    void frame(const ref FrameInput input, float dt) {
        foreach (i, name; KEY_NAMES) {
            if (input.keys.held[i] != keys.held[i]) {
                flush();
                file.writefln("%s(\"%s\")", input.keys.held[i] ? "hold" : "release", name);
            }
        }
        keys = input.keys;
        string f = format("%.6f, %.6f, %.6f", dt, input.yaw, input.pitch);
        if (f != pendingFrame) {
            flush();
            pendingFrame = f;
        }
        pendingCount++;
    }

    void event(string call) {
        flush();
        file.writeln(call);
    }

    void flush() {
        if (pendingCount > 0) {
            file.writefln("frames(%d, %s)", pendingCount, pendingFrame);
        }
        pendingCount = 0;
        pendingFrame = null;
    }

    void close() {
        flush();
        file.close();
    }
}
