module web.main;

import core.stdc.stdio : snprintf;
import core.stdc.stdlib : calloc;
import base.clock : FrameClock, MILLISECONDS_PER_SECOND, nowMilliseconds, nowSeconds;
import base.names : ENUM_NAMES;
import base.units : Angle, AngularSpeed, Time;
import client.config : ClientConfig, PitchAxis;
import client.game : FrameInput, Game, Key, MATERIAL_PALETTE, axisValue;
import client.hud : Hud, worldNameOf;
import client.plugins : registry;
import client.structures : StructureProblem, growthProblem, placeStructure, restartGame;
import common.character.controller : MovementMode;
import common.settings : CHUNK_DIMENSION;
import common.worldgen.generation : StructureWorld, Worldgen;
import plugins.api.flags : Flags;
import web.renderer : WebRenderer;

enum double MAX_STEP_SECONDS = 0.1;
enum double TITLE_INTERVAL_SECONDS = 1.0;
enum double FRAME_WORK_MILLISECONDS = 13.0;
enum double LEAST_TASK_MILLISECONDS = 2.0;
enum size_t TEXT_CAPACITY = 256;
enum uint LEFT_BUTTON = 0;
enum uint RIGHT_BUTTON = 2;

enum WebKey : uint {
    w,
    a,
    s,
    d,
    space,
    shift,
    left,
    right,
    up,
    down,
    v,
    n,
    t,
    bracketLeft,
    bracketRight,
    digit1,
    digit9 = digit1 + 8,
}

enum KeyStroke : uint {
    first,
    repeated,
}

enum Capture : uint {
    released,
    captured,
}

enum WorldStep : ubyte {
    previous,
    next,
}

enum SessionMark : ubyte {
    captured,
    stopped,
    titleStale,
}

struct KeyBinding {
    WebKey symbol;
    Key key;
}

immutable KeyBinding[10] KEY_BINDINGS = [
    KeyBinding(WebKey.w, Key.fwd),
    KeyBinding(WebKey.s, Key.back),
    KeyBinding(WebKey.a, Key.left),
    KeyBinding(WebKey.d, Key.right),
    KeyBinding(WebKey.space, Key.up),
    KeyBinding(WebKey.shift, Key.down),
    KeyBinding(WebKey.left, Key.yawLeft),
    KeyBinding(WebKey.right, Key.yawRight),
    KeyBinding(WebKey.up, Key.pitchUp),
    KeyBinding(WebKey.down, Key.pitchDown),
];

extern (C) nothrow @nogc {
    void web_status(const(char)* text);
    void web_fail(const(char)* text);
}

struct Session {
    Game game;
    WebRenderer renderer;
    Hud hud;
    ClientConfig config;
    FrameClock clock;
    double mouseDx = 0;
    double mouseDy = 0;
    double lastTitleTime = 0;
    float fps = 0;
    float worstFrameMs = 0;
    uint framesSinceTitle;
    uint worldIndex;
    Flags!Key held;
    Flags!SessionMark marks;

    bool isCaptured() const {
        return marks.has(SessionMark.captured);
    }

    bool isRunning() const {
        return !marks.has(SessionMark.stopped);
    }

    void start(uint width, uint height, float renderRadius) {
        renderer.setup(CHUNK_DIMENSION, width, height);
        game = Game.make(Worldgen.makeTerrain(), config.reach);
        game.world.renderRadius = renderRadius;
        report(game.placeStructure());
        lastTitleTime = nowSeconds();
        clock = FrameClock.startingAt(lastTitleTime);
        marks.set(SessionMark.titleStale);
    }

    void report(StructureProblem problem) {
        if (problem.isPresent) {
            web_fail(problem.text.ptr);
            marks.set(SessionMark.stopped);
        }
    }

    void frame() {
        double frameStart = nowMilliseconds();
        double now = nowSeconds();
        Time dt = Time(cast(float) clock.tick(now, MAX_STEP_SECONDS));
        game.step(buildFrameInput(dt), dt);
        mouseDx = 0;
        mouseDy = 0;
        hud.buildMarkers(game);
        hud.build(game, renderer.width, renderer.height);
        renderer.render(game.world, hud.vertices.slice(), hud.markers.slice());
        double deadline = frameStart + FRAME_WORK_MILLISECONDS;
        double least = nowMilliseconds() + LEAST_TASK_MILLISECONDS;
        if (least > deadline) {
            deadline = least;
        }
        game.world.streamer.runTasksUntil(deadline);
        report(growthProblem(game.world.graph));
        framesSinceTitle += 1;
        if (now - lastTitleTime >= TITLE_INTERVAL_SECONDS) {
            fps = cast(float)(framesSinceTitle / (now - lastTitleTime));
            worstFrameMs = cast(float)(clock.worst * MILLISECONDS_PER_SECOND);
            clock.worst = 0;
            framesSinceTitle = 0;
            lastTitleTime = now;
            marks.set(SessionMark.titleStale);
        }
        if (marks.has(SessionMark.titleStale)) {
            updateStatus();
        }
    }

    FrameInput buildFrameInput(Time dt) {
        AngularSpeed yawRate = config.keyTurnRate * (axisValue(held, Key.yawRight) - axisValue(held, Key.yawLeft));
        AngularSpeed pitchRate = config.keyTurnRate * (axisValue(held, Key.pitchDown) - axisValue(held, Key.pitchUp));
        Angle yaw = yawRate * dt + config.mouseTurnPerCount * cast(float) mouseDx;
        Angle pitch = pitchRate * dt + config.mouseTurnPerCount * cast(float) mouseDy * pitchSign(config.pitchAxis);
        return FrameInput(yaw, pitch, held);
    }

    void updateStatus() {
        char[TEXT_CAPACITY] text;
        string mode = ENUM_NAMES!MovementMode[game.mode];
        const(char)[] world = worldNameOf(game.world.graph.worldgen);
        if (isCaptured) {
            snprintf(text.ptr, text.length, "mined - %.*s ([ ]) - %.*s (V) - [%u] - Esc to release mouse - FPS %.0f, worst frame %.0fms", cast(int) world.length, world.ptr, cast(int) mode.length, mode.ptr, game.materialIndex + 1, cast(double) fps, cast(double) worstFrameMs);
        } else {
            snprintf(text.ptr, text.length, "mined - %.*s ([ ]) - %.*s (V) - click to capture mouse - FPS %.0f, worst frame %.0fms", cast(int) world.length, world.ptr, cast(int) mode.length, mode.ptr, cast(double) fps, cast(double) worstFrameMs);
        }
        web_status(text.ptr);
        marks.clear(SessionMark.titleStale);
    }

    void keyDown(WebKey symbol, KeyStroke press) {
        if (isCaptured) {
            if (symbol == WebKey.v && press == KeyStroke.first) {
                game.toggleMode(MovementMode.walk);
                marks.set(SessionMark.titleStale);
            } else if (symbol == WebKey.n && press == KeyStroke.first) {
                game.toggleMode(MovementMode.noclip);
                marks.set(SessionMark.titleStale);
            } else if (symbol >= WebKey.digit1 && symbol <= WebKey.digit9) {
                selectMaterial(cast(uint)(symbol - WebKey.digit1));
            } else if (symbol == WebKey.bracketLeft && press == KeyStroke.first) {
                switchWorld(WorldStep.previous);
            } else if (symbol == WebKey.bracketRight && press == KeyStroke.first) {
                switchWorld(WorldStep.next);
            } else if (symbol == WebKey.t && press == KeyStroke.first) {
                game.throwBlock();
            } else {
                foreach (binding; KEY_BINDINGS) {
                    if (binding.symbol == symbol) {
                        held.set(binding.key);
                    }
                }
            }
        }
    }

    void keyUp(WebKey symbol) {
        foreach (binding; KEY_BINDINGS) {
            if (binding.symbol == symbol) {
                held.clear(binding.key);
            }
        }
    }

    void selectMaterial(uint index) {
        if (index < MATERIAL_PALETTE.length && index != game.materialIndex) {
            game.materialIndex = index;
            marks.set(SessionMark.titleStale);
        }
    }

    void switchWorld(WorldStep direction) {
        uint count = cast(uint) registry().allNames().length + 1;
        uint step = count - 1;
        if (direction == WorldStep.next) {
            step = 1;
        }
        worldIndex = (worldIndex + step) % count;
        report(restartGame(game, worldgenAt(worldIndex)));
        marks.set(SessionMark.titleStale);
    }

    void button(uint pressed) {
        if (isCaptured && pressed == LEFT_BUTTON) {
            game.breakBlock();
        } else if (isCaptured && pressed == RIGHT_BUTTON) {
            game.placeBlock();
        }
    }

    void capture(Capture state) {
        if (state == Capture.captured) {
            marks.set(SessionMark.captured);
        } else {
            marks.clear(SessionMark.captured);
            held = Flags!Key.init;
        }
        marks.set(SessionMark.titleStale);
    }
}

Worldgen worldgenAt(uint index) {
    if (index == 0) {
        return Worldgen.makeTerrain();
    } else {
        return Worldgen.fromStructure(StructureWorld.fromName(registry().allNames()[index - 1]));
    }
}

float pitchSign(PitchAxis axis) {
    if (axis == PitchAxis.inverted) {
        return -1.0f;
    } else {
        return 1.0f;
    }
}

__gshared Session* session;

extern (C) void web_start(uint width, uint height, float renderRadius) {
    session = cast(Session*) calloc(1, Session.sizeof);
    *session = Session.init;
    session.start(width, height, renderRadius);
}

extern (C) void web_frame() {
    if (session.isRunning) {
        session.frame();
    }
}

extern (C) void web_resize(uint width, uint height) {
    session.renderer.resize(width, height);
}

extern (C) void web_key_down(uint key, uint press) {
    session.keyDown(cast(WebKey) key, cast(KeyStroke) press);
}

extern (C) void web_key_up(uint key) {
    session.keyUp(cast(WebKey) key);
}

extern (C) void web_button(uint pressed) {
    session.button(pressed);
}

extern (C) void web_motion(double dx, double dy) {
    if (session.isCaptured) {
        session.mouseDx += dx;
        session.mouseDy += dy;
    }
}

extern (C) void web_capture(uint state) {
    session.capture(cast(Capture) state);
}

extern (C) uint web_backlog() {
    return session.renderer.backlog;
}

extern (C) uint web_visible_chunks() {
    return cast(uint) session.renderer.visible.length;
}

extern (C) uint web_drawable_chunks() {
    return session.renderer.meshes.drawableCount;
}

extern (C) uint web_settled() {
    return cast(uint)(session.game.world.isWorldgenSettled() && session.renderer.backlog == 0);
}
