module client.script;

import core.stdc.math : acosf, floor, fabsf;
import core.stdc.stdio : FILE, fclose, fopen, fprintf, snprintf;
import base.maybe : Maybe;
import base.names : ENUM_NAMES;
import base.numbers : RADIANS_PER_DEGREE, clamped;
import base.units : Angle, AngularSpeed, Length, Speed, Time;
import base.vector3 : dot, magnitude, rejectAlong;
import client.arguments : ExitStatus, StructureName, exitStatus;
import client.game : ChunkSupply, FrameInput, Game, KEY_COUNT, Key, Preset, RouteWaypoint, ThrownMotion, UnloadedCount;
import common.inventory : HOTBAR_SLOTS;
import client.structures : StructureProblem, growthProblem, restartGame;
import common.character.controller : Footing, MovementMode;
import common.worldgen.generation : PlaneWorld, Worldgen, WorldgenKind;
import plugins.api.api : Material;
import plugins.api.flags : Flags;

enum Time DEFAULT_TIMESTEP = Time(0.016f);
enum Time ONE_SECOND = Time(1.0f);
enum size_t FAILURE_CAPACITY = 1024;

alias ScriptBody = void function(ref Script script);

enum HookState : ubyte {
    idle,
    running,
}

struct NamedScript {
    string name;
    ScriptBody run;
}

struct StepHook {
    void function(ref Script script, void* context) call;
    void* context;
}

Angle degrees(double value) {
    return Angle(cast(float)(value * RADIANS_PER_DEGREE));
}

double degreesOf(Angle angle) {
    return angle.value / RADIANS_PER_DEGREE;
}

float smoothStep(float share) {
    return share * share * (3 - 2 * share);
}

struct Script {
    Game* game;
    FILE* report;
    Time timestep = DEFAULT_TIMESTEP;
    AngularSpeed yawRate;
    AngularSpeed pitchRate;
    StepHook hook;
    StepHook camera;
    uint steps;
    char[FAILURE_CAPACITY] failure = 0;
    Flags!Key held;
    HookState hookState;

    static Script make(Game* game, FILE* report) {
        return Script(game, report);
    }

    bool isFailed() const {
        return failure[0] != 0;
    }

    ExitStatus run(ScriptBody body) {
        body(this);
        if (isFailed) {
            fprintf(report, "script error: %s\n", failure.ptr);
        }
        return exitStatus(!isFailed);
    }

    void fail(Args...)(const(char)* format, Args args) {
        if (!isFailed) {
            snprintf(failure.ptr, failure.length, format, args);
        }
    }

    bool takeFailure() {
        if (isFailed) {
            failure[0] = 0;
            return true;
        } else {
            return false;
        }
    }

    void check(Args...)(bool condition, const(char)* format, Args args) {
        if (!condition) {
            fail(format, args);
        }
    }

    void step() {
        step(timestep);
    }

    void step(Time dt) {
        if (!(dt.value > 0)) {
            fail("the timestep must be positive");
        } else if (hookState == HookState.running) {
            fail("a step hook cannot advance time");
        } else if (!isFailed) {
            game.step(FrameInput(yawRate * dt, pitchRate * dt, held), dt);
            steps += 1;
            StructureProblem grown = growthProblem(game.world.graph);
            if (grown.isPresent) {
                fail("%s", grown.text.ptr);
            } else if (hook.call !is null) {
                hookState = HookState.running;
                hook.call(this, hook.context);
                hookState = HookState.idle;
            }
        }
    }

    void wait(double seconds) {
        wait(seconds, timestep);
    }

    void wait(double seconds, Time dt) {
        if (!(seconds >= 0)) {
            fail("cannot wait a negative time");
        } else if (!(dt.value > 0)) {
            fail("the timestep must be positive");
        } else {
            ulong count = cast(ulong) floor(seconds / dt.value + 0.5);
            ulong done = 0;
            while (done < count && !isFailed) {
                step(dt);
                done += 1;
            }
        }
    }

    void setTimestep(Time chosen) {
        if (!(chosen.value > 0)) {
            fail("the timestep must be positive");
        } else {
            timestep = chosen;
        }
    }

    Time time() const {
        return game.time;
    }

    void worldgen(Worldgen chosen) {
        if (steps > 0) {
            fail("worldgen must be chosen before the first step");
        } else {
            StructureProblem problem = restartGame(*game, chosen);
            if (problem.isPresent) {
                fail("%s", problem.text.ptr);
            }
        }
    }

    void terrain() {
        worldgen(Worldgen.makeTerrain());
    }

    void plane(Angle tilt) {
        worldgen(Worldgen.fromPlane(PlaneWorld(tilt.value)));
    }

    void structure(const(char)[] name) {
        StructureName found = StructureName.fromText(name);
        if (found.problem !is null) {
            fail("%s '%.*s'", found.problem, cast(int) name.length, name.ptr);
        } else {
            worldgen(Worldgen.fromStructure(found.world));
        }
    }

    void onStep(StepHook chosen) {
        hook = chosen;
    }

    void hold(Key[] keys...) {
        foreach (key; keys) {
            held.set(key);
        }
    }

    void release(Key[] keys...) {
        foreach (key; keys) {
            held.clear(key);
        }
    }

    void releaseAll() {
        held = Flags!Key.init;
    }

    void press(double seconds, Key[] keys...) {
        hold(keys);
        wait(seconds);
        release(keys);
    }

    void look(Angle yaw, Angle pitch) {
        game.look(yaw, pitch);
    }

    void turnRate(AngularSpeed yaw, AngularSpeed pitch) {
        yawRate = yaw;
        pitchRate = pitch;
    }

    void turn(Angle yaw, Angle pitch, double seconds) {
        Time duration = Time(cast(float) seconds);
        AngularSpeed restingYaw = yawRate;
        AngularSpeed restingPitch = pitchRate;
        yawRate = yaw / duration;
        pitchRate = pitch / duration;
        wait(seconds);
        yawRate = restingYaw;
        pitchRate = restingPitch;
    }

    void roll() {
        hook = camera;
    }

    void glide(Key key, float distance, Angle yaw, Angle pitch, double seconds) {
        ulong count = cast(ulong) floor(seconds / timestep.value + 0.5);
        Speed resting = game.character.noclipSpeed;
        float before = 0;
        hold(key);
        foreach (index; 0 .. count) {
            if (!isFailed) {
                float after = smoothStep((index + 1.0f) / count);
                float share = after - before;
                before = after;
                game.character.noclipSpeed = Speed(fabsf(distance) * share / timestep.value);
                look(yaw * share, pitch * share);
                step();
            }
        }
        release(key);
        game.character.noclipSpeed = resting;
    }

    void ease(Angle yaw, Angle pitch, double seconds) {
        ulong count = cast(ulong) floor(seconds / timestep.value + 0.5);
        float before = 0;
        foreach (index; 0 .. count) {
            if (!isFailed) {
                float after = smoothStep((index + 1.0f) / count);
                look(yaw * (after - before), pitch * (after - before));
                before = after;
                step();
            }
        }
    }

    void throwBlock() {
        game.throwBlock();
    }

    size_t thrownCount() const {
        return game.thrown.length;
    }

    bool isThrownResting(size_t index) const {
        return game.thrown.ptr[index].motion == ThrownMotion.resting;
    }

    void resetCompass() {
        game.resetCompass();
    }

    Angle compassOff() const {
        return game.compassOff();
    }

    MovementMode mode() const {
        return game.mode;
    }

    void mode(MovementMode chosen) {
        game.mode = chosen;
    }

    Preset preset() const {
        return game.preset;
    }

    void perceive(Preset chosen) {
        game.perceive(chosen);
    }

    void dose() {
        game.doseNext();
    }

    void use() {
        game.use();
    }

    bool eat() {
        return game.eat();
    }

    uint material() const {
        return game.inventory.selected + 1;
    }

    void material(uint slot) {
        if (slot < 1 || slot > HOTBAR_SLOTS) {
            fail("material slot must be 1..%d", cast(int) HOTBAR_SLOTS);
        } else {
            game.inventory.selected = slot - 1;
        }
    }

    bool breakBlock() {
        return game.breakBlock();
    }

    bool placeBlock() {
        return game.placeBlock();
    }

    Maybe!Material targetMaterial() const {
        return game.world.targetMaterial();
    }

    void enterStructure(Length height) {
        if (game.world.graph.worldgen.kind != WorldgenKind.structure) {
            fail("enterStructure needs the structure worldgen");
        } else {
            game.enterStructure(height);
        }
    }

    void enterRoute(size_t number = 1) {
        if (number == 0 || game.world.graph.structures.blueprint.route.length < number) {
            fail("enterRoute needs a structure with a route that has stop %zu", number);
        } else {
            game.enterRoute(number - 1);
        }
    }

    Maybe!RouteWaypoint routeWaypoint(size_t number) const {
        Maybe!RouteWaypoint waypoint;
        if (number >= 1) {
            waypoint = game.routeWaypoint(number - 1);
            if (waypoint.exists) {
                waypoint.value.yaw = -waypoint.value.yaw;
            }
        }
        return waypoint;
    }

    RouteWaypoint needWaypoint(size_t number) {
        Maybe!RouteWaypoint waypoint = routeWaypoint(number);
        if (waypoint.exists) {
            return waypoint.value;
        } else {
            fail("the route has no stop %zu", number);
            return RouteWaypoint.init;
        }
    }

    Length traveled() const {
        return game.traveled;
    }

    bool isOnGround() const {
        return game.characterState.isOnGround;
    }

    Footing footing() const {
        return game.characterState.footing;
    }

    void live() {
        game.supply = ChunkSupply.streamed;
    }

    bool isLoaded() const {
        return game.isLoadedAround();
    }

    UnloadedCount unloadedWithin(Length radius) const {
        return game.unloadedWithin(radius);
    }

    Length probeFrameDrift(Length radius) {
        return game.probeFrameDrift(radius);
    }

    Length altitude() const {
        return game.altitude;
    }

    Speed speed() const {
        return Speed(game.characterState.velocity.magnitude);
    }

    Speed horizontalSpeed() const {
        return Speed(game.characterState.velocity.rejectAlong(game.characterState.up).magnitude);
    }

    Angle floorTilt() const {
        return Angle(acosf(clamped(game.characterState.groundNormal.dot(game.characterState.up), -1.0f, 1.0f)));
    }

    Speed verticalSpeed() const {
        return Speed(game.characterState.velocity.dot(game.characterState.up));
    }

    float cameraVerticalAcceleration() const {
        return game.cameraVerticalAcceleration.value;
    }
}

const(T)* named(T)(const(T)[] items, const(char)[] name) {
    size_t index = 0;
    while (index < items.length && items[index].name != name) {
        index += 1;
    }
    if (index < items.length) {
        return &items[index];
    } else {
        return null;
    }
}

struct ScriptRecorder {
    FILE* file;
    Time pendingDt;
    uint pendingSteps;
    Flags!Key held;

    bool open(const(char)* path) {
        file = fopen(path, "w");
        if (file is null) {
            return false;
        } else {
            fprintf(file, "void recorded(ref Script world) {\n");
            return true;
        }
    }

    void recordFrame(FrameInput input, Time dt) {
        foreach (i; 0 .. KEY_COUNT) {
            Key key = cast(Key) i;
            if (input.held.has(key) != held.has(key)) {
                flush();
                string name = ENUM_NAMES!Key[i];
                fprintf(file, "    world.%s(Key.%.*s);\n", keyCall(input.held, key), cast(int) name.length, name.ptr);
            }
        }
        held = input.held;
        if (input.yaw.value != 0 || input.pitch.value != 0) {
            flush();
            fprintf(file, "    world.look(degrees(%.9g), degrees(%.9g));\n", degreesOf(input.yaw), degreesOf(input.pitch));
        }
        if (dt.value != pendingDt.value) {
            flush();
            pendingDt = dt;
        }
        pendingSteps += 1;
    }

    void recordCall(const(char)* call) {
        flush();
        fprintf(file, "    world.%s();\n", call);
    }

    void recordMode(MovementMode mode) {
        flush();
        string name = ENUM_NAMES!MovementMode[mode];
        fprintf(file, "    world.mode(MovementMode.%.*s);\n", cast(int) name.length, name.ptr);
    }

    void recordPreset(Preset preset) {
        flush();
        string name = ENUM_NAMES!Preset[preset];
        fprintf(file, "    world.perceive(Preset.%.*s);\n", cast(int) name.length, name.ptr);
    }

    void recordMaterial(uint slot) {
        flush();
        fprintf(file, "    world.material(%u);\n", slot);
    }

    void flush() {
        if (pendingSteps > 0) {
            fprintf(file, "    world.wait(%.9g, Time(%.9gf));\n", pendingSteps * cast(double) pendingDt.value, cast(double) pendingDt.value);
        }
        pendingSteps = 0;
    }

    void close() {
        flush();
        fprintf(file, "}\n");
        fclose(file);
        file = null;
    }
}

immutable(char)* keyCall(Flags!Key held, Key key) {
    if (held.has(key)) {
        return "hold";
    } else {
        return "release";
    }
}
