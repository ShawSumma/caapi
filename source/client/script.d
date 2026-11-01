module client.script;

import core.stdc.math : floor;
import core.stdc.stdio : FILE, fclose, fopen, fprintf, snprintf;
import base.names : ENUM_NAMES;
import base.numbers : RADIANS_PER_DEGREE;
import base.units : Angle, AngularSpeed, Length, Speed, Time;
import base.vector3 : dot, magnitude, rejectAlong;
import client.arguments : StructureName;
import client.game : FrameInput, Game, KEY_COUNT, Key, MATERIAL_PALETTE, RouteWaypoint, UnloadedCount;
import client.structures : StructureProblem, growthProblem, restartGame;
import client.world : TargetMaterial;
import common.character.controller : MovementMode;
import common.worldgen.generation : PlaneWorld, Worldgen, WorldgenKind;

enum Time DEFAULT_TIMESTEP = Time(0.016f);
enum Time ONE_SECOND = Time(1.0f);
enum size_t FAILURE_CAPACITY = 1024;

alias ScriptBody = void function(ref Script script);

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

struct Script {
    Game* game;
    FILE* report;
    Time timestep = DEFAULT_TIMESTEP;
    AngularSpeed yawRate;
    AngularSpeed pitchRate;
    StepHook hook;
    uint steps;
    char[FAILURE_CAPACITY] failure = 0;
    bool[KEY_COUNT] isHeld;
    bool isStepping;
    bool isFailed;

    static Script make(Game* game, FILE* report) {
        return Script(game, report);
    }

    bool run(ScriptBody body) {
        body(this);
        if (isFailed) {
            fprintf(report, "script error: %s\n", failure.ptr);
        }
        return !isFailed;
    }

    void fail(Args...)(const(char)* format, Args args) {
        if (!isFailed) {
            snprintf(failure.ptr, failure.length, format, args);
            isFailed = true;
        }
    }

    bool takeFailure() {
        bool wasFailed = isFailed;
        isFailed = false;
        failure[0] = 0;
        return wasFailed;
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
        } else if (isStepping) {
            fail("a step hook cannot advance time");
        } else if (!isFailed) {
            game.step(FrameInput(yawRate * dt, pitchRate * dt, isHeld), dt);
            steps += 1;
            StructureProblem grown = growthProblem(game.world.graph);
            if (grown.isPresent) {
                fail("%s", grown.text.ptr);
            } else if (hook.call !is null) {
                isStepping = true;
                hook.call(this, hook.context);
                isStepping = false;
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
            isHeld[key] = true;
        }
    }

    void release(Key[] keys...) {
        foreach (key; keys) {
            isHeld[key] = false;
        }
    }

    void releaseAll() {
        isHeld[] = false;
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

    MovementMode mode() const {
        return game.mode;
    }

    void mode(MovementMode chosen) {
        game.mode = chosen;
    }

    uint material() const {
        return game.materialIndex + 1;
    }

    void material(uint slot) {
        if (slot < 1 || slot > MATERIAL_PALETTE.length) {
            fail("material slot must be 1..%d", cast(int) MATERIAL_PALETTE.length);
        } else {
            game.materialIndex = slot - 1;
        }
    }

    bool breakBlock() {
        return game.breakBlock();
    }

    bool placeBlock() {
        return game.placeBlock();
    }

    TargetMaterial targetMaterial() {
        return game.world.targetMaterial();
    }

    void enterStructure(Length height) {
        if (game.world.graph.worldgen.kind != WorldgenKind.structure) {
            fail("enterStructure needs the structure worldgen");
        } else {
            game.enterStructure(height);
        }
    }

    void enterRoute() {
        if (game.world.graph.structures.blueprint.route.length == 0) {
            fail("enterRoute needs a structure with a route");
        } else {
            game.enterRoute();
        }
    }

    RouteWaypoint routeWaypoint(size_t number) {
        RouteWaypoint waypoint;
        if (number >= 1) {
            waypoint = game.routeWaypoint(number - 1);
            waypoint.yaw = -waypoint.yaw;
        }
        return waypoint;
    }

    Length traveled() const {
        return game.traveled;
    }

    bool isOnGround() const {
        return game.characterState.isOnGround;
    }

    void live() {
        game.isGeneratingOnDemand = false;
    }

    bool isLoaded() const {
        return game.isLoadedAround();
    }

    UnloadedCount unloadedWithin(Length radius) const {
        return game.unloadedWithin(radius);
    }

    Length frameDrift(Length radius) {
        return game.frameDrift(radius);
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
    bool[KEY_COUNT] isHeld;

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
            if (input.isHeld[i] != isHeld[i]) {
                flush();
                string name = ENUM_NAMES!Key[i];
                fprintf(file, "    world.%s(Key.%.*s);\n", keyCall(input.isHeld[i]), cast(int) name.length, name.ptr);
            }
        }
        isHeld = input.isHeld;
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

immutable(char)* keyCall(bool isPressed) {
    if (isPressed) {
        return "hold";
    } else {
        return "release";
    }
}
