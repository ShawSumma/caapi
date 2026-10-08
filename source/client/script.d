module client.script;

import core.stdc.math : floor;
import core.stdc.stdio : FILE, fclose, fopen, fprintf;
import core.stdc.string : strlen;
import bindings.lua : luaL_checkinteger, luaL_checklstring, luaL_checknumber, luaL_checktype, luaL_error, luaL_loadfilex, luaL_optnumber, luaL_ref, luaL_unref, lua_CFunction, lua_Integer, lua_State, lua_callk, lua_close, lua_createtable, lua_gettop, lua_pcallk, lua_pushboolean, lua_pushcclosure, lua_pushinteger, lua_pushnil, lua_pushnumber, lua_pushvalue, lua_rawgeti, lua_tolstring, lua_touserdata, lua_type;
import client.arguments : StructureName;
import client.game : FrameInput, Game, KEY_COUNT, Key, MATERIAL_PALETTE, RouteWaypoint;
import client.lua : LUA_FIRST_UPVALUE, LUA_NO_REF, LUA_REGISTRY, LUA_STATUS_OK, LUA_TOP, LUA_TYPE_FUNCTION, LUA_TYPE_TABLE, LuaLookup, LuaName, SELF, TRACEBACK_INDEX, isNoneOrNil, luaTraceback, newSafeState, pushLuaName, registerMethod, setPackagePath;
import client.structures : StructureProblem, restartGame;
import client.world : TargetMaterial;
import common.character.controller : MovementMode;
import common.names : ENUM_NAMES;
import common.units : Angle, AngularSpeed, Length, Time;
import common.vector3 : dot, magnitude, rejectAlong;
import common.worldgen.generation : PlaneWorld, StructureWorld, Worldgen, WorldgenKind;

enum int CHUNK_RESULTS = 1;
enum int SCRIPT_ARGUMENTS = 1;
enum Time DEFAULT_TIMESTEP = Time(0.016f);
enum Time ONE_SECOND = Time(1.0f);
enum double RADIANS_PER_DEGREE = 0.017453292519943295;

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
        lua = newSafeState();
        lua.setPackagePath(path[0 .. strlen(path)]);
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

    void createWorld() {
        lua_createtable(lua, 0, 0);
        lua.registerMethod(&this, "wait", &luaWait);
        lua.registerMethod(&this, "step", &luaStep);
        lua.registerMethod(&this, "timestep", &luaTimestep);
        lua.registerMethod(&this, "time", &luaTime);
        lua.registerMethod(&this, "worldgen", &luaWorldgen);
        lua.registerMethod(&this, "on_step", &luaOnStep);
        lua.registerMethod(&this, "hold", &luaHold);
        lua.registerMethod(&this, "release", &luaRelease);
        lua.registerMethod(&this, "release_all", &luaReleaseAll);
        lua.registerMethod(&this, "press", &luaPress);
        lua.registerMethod(&this, "look", &luaLook);
        lua.registerMethod(&this, "turn_rate", &luaTurnRate);
        lua.registerMethod(&this, "turn", &luaTurn);
        lua.registerMethod(&this, "mode", &luaMode);
        lua.registerMethod(&this, "material", &luaMaterial);
        lua.registerMethod(&this, "break_block", &luaBreakBlock);
        lua.registerMethod(&this, "place_block", &luaPlaceBlock);
        lua.registerMethod(&this, "target_material", &luaTargetMaterial);
        lua.registerMethod(&this, "enter_structure", &luaEnterStructure);
        lua.registerMethod(&this, "enter_route", &luaEnterRoute);
        lua.registerMethod(&this, "route_waypoint", &luaRouteWaypoint);
        lua.registerMethod(&this, "traveled", &luaTraveled);
        lua.registerMethod(&this, "is_on_ground", &luaIsOnGround);
        lua.registerMethod(&this, "altitude", &luaAltitude);
        lua.registerMethod(&this, "speed", &luaSpeed);
        lua.registerMethod(&this, "horizontal_speed", &luaHorizontalSpeed);
        lua.registerMethod(&this, "vertical_speed", &luaVerticalSpeed);
        lua.registerMethod(&this, "camera_vertical_acceleration", &luaCameraVerticalAcceleration);
        worldRef = luaL_ref(lua, LUA_REGISTRY);
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

Angle degreesArgument(lua_State* lua, int index) {
    return Angle(cast(float)(luaL_checknumber(lua, index) * RADIANS_PER_DEGREE));
}

Time timestepArgument(lua_State* lua, int index, Time fallback) {
    return Time(cast(float) luaL_optnumber(lua, index, fallback.value));
}

double degreesOf(Angle angle) {
    return angle.value / RADIANS_PER_DEGREE;
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
        StructureProblem problem = restartGame(*host.game, worldgenOfKind(lua, lookup.value));
        if (problem.isPresent) {
            luaL_error(lua, "%s", problem.text.ptr);
        }
    }
    return 0;
}

Worldgen worldgenOfKind(lua_State* lua, WorldgenKind kind) {
    Worldgen worldgen = void;
    final switch (kind) {
        case WorldgenKind.terrain:
            worldgen = Worldgen.makeTerrain();
            break;
        case WorldgenKind.plane:
            worldgen = Worldgen.fromPlane(PlaneWorld(cast(float)(luaL_optnumber(lua, SELF + 2, 0) * RADIANS_PER_DEGREE)));
            break;
        case WorldgenKind.structure:
            worldgen = Worldgen.fromStructure(structureArgument(lua));
            break;
    }
    return worldgen;
}

StructureWorld structureArgument(lua_State* lua) {
    const(char)* text = luaL_checklstring(lua, SELF + 2, null);
    StructureName name = StructureName.fromText(text[0 .. strlen(text)]);
    if (name.problem !is null) {
        luaL_error(lua, "%s '%s'", name.problem, text);
    }
    return name.world;
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

extern (C) int luaEnterRoute(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    if (host.game.world.graph.blueprint.route.length == 0) {
        luaL_error(lua, "enter_route needs a structure with a route");
    } else {
        host.game.enterRoute();
    }
    return 0;
}

extern (C) int luaRouteWaypoint(lua_State* lua) {
    ScriptHost* host = methodHost(lua);
    lua_Integer number = luaL_checkinteger(lua, SELF + 1);
    RouteWaypoint waypoint;
    if (number >= 1) {
        waypoint = host.game.routeWaypoint(cast(size_t)(number - 1));
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
