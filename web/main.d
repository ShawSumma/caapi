module web.main;

import core.stdc.stdlib : calloc;
import base.clock : FrameClock, nowMilliseconds, nowSeconds;
import base.maybe : Maybe;
import base.units : Time;
import client.config : ClientConfig;
import client.game : Command, CommandBinding, Game, Key, KeyBinding, KeyStroke, MAX_STEP_SECONDS, commandOf, frameInputOf, holdBound, letGoBound;
import client.hud : FrameMeter, Hud, MouseCapture, STATUS_CAPACITY, statusLine;
import client.plugins : gatherWorlds;
import client.structures : StructureProblem, WorldStep, growthProblem, placeStructure, restartGame, steppedWorld, worldgenAt;
import common.character.controller : MovementMode;
import common.settings : CHUNK_DIMENSION;
import common.worldgen.generation : Worldgen;
import plugins.api.flags : Flags;
import web.renderer : WebRenderer;

enum double FRAME_WORK_MILLISECONDS = 13.0;
enum double LEAST_TASK_MILLISECONDS = 2.0;
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
    p,
    o,
    e,
    f,
}

enum SessionMark : ubyte {
    stopped,
    titleStale,
}

immutable KeyBinding!WebKey[Key.max + 1] KEY_BINDINGS = [
    KeyBinding!WebKey(WebKey.w, Key.fwd),
    KeyBinding!WebKey(WebKey.s, Key.back),
    KeyBinding!WebKey(WebKey.a, Key.left),
    KeyBinding!WebKey(WebKey.d, Key.right),
    KeyBinding!WebKey(WebKey.space, Key.up),
    KeyBinding!WebKey(WebKey.shift, Key.down),
    KeyBinding!WebKey(WebKey.left, Key.yawLeft),
    KeyBinding!WebKey(WebKey.right, Key.yawRight),
    KeyBinding!WebKey(WebKey.up, Key.pitchUp),
    KeyBinding!WebKey(WebKey.down, Key.pitchDown),
];

immutable CommandBinding!WebKey[Command.max + 1] COMMAND_BINDINGS = [
    CommandBinding!WebKey(WebKey.v, Command.walkMode),
    CommandBinding!WebKey(WebKey.n, Command.noclipMode),
    CommandBinding!WebKey(WebKey.bracketLeft, Command.previousWorld),
    CommandBinding!WebKey(WebKey.bracketRight, Command.nextWorld),
    CommandBinding!WebKey(WebKey.t, Command.throwBlock),
    CommandBinding!WebKey(WebKey.p, Command.nextPreset),
    CommandBinding!WebKey(WebKey.o, Command.dose),
    CommandBinding!WebKey(WebKey.e, Command.use),
    CommandBinding!WebKey(WebKey.f, Command.eat),
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
    FrameMeter meter;
    double mouseDx = 0;
    double mouseDy = 0;
    uint worldIndex;
    Flags!Key held;
    Flags!SessionMark marks;
    MouseCapture mouse;

    bool isCaptured() const {
        return mouse == MouseCapture.captured;
    }

    bool isRunning() const {
        return !marks.has(SessionMark.stopped);
    }

    void start(uint width, uint height, float renderRadius) {
        renderer.setup(CHUNK_DIMENSION, width, height);
        game = Game.make(Worldgen.makeTerrain(), config.reach);
        game.comfort = config.comfort;
        game.world.graph.bindView();
        game.world.renderRadius = renderRadius;
        report(game.placeStructure());
        double started = nowSeconds();
        clock = FrameClock.startingAt(started);
        meter = FrameMeter.startingAt(started);
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
        game.step(frameInputOf(config, held, mouseDx, mouseDy, dt), dt);
        mouseDx = 0;
        mouseDy = 0;
        hud.buildMarkers(game);
        hud.build(game, renderer.width, renderer.height);
        renderer.render(game.world, hud.vertices.slice(), hud.markers.slice(), hud.atlas);
        double deadline = frameStart + FRAME_WORK_MILLISECONDS;
        double least = nowMilliseconds() + LEAST_TASK_MILLISECONDS;
        if (least > deadline) {
            deadline = least;
        }
        game.world.streamer.runTasksUntil(deadline);
        report(growthProblem(game.world.graph));
        bool refreshed = meter.tick(now, clock);
        if (refreshed) {
            marks.set(SessionMark.titleStale);
        }
        if (marks.has(SessionMark.titleStale)) {
            updateStatus();
        }
    }

    void updateStatus() {
        char[STATUS_CAPACITY] text = statusLine(game, mouse, meter);
        web_status(text.ptr);
        marks.clear(SessionMark.titleStale);
    }

    void keyDown(WebKey symbol, KeyStroke press) {
        if (isCaptured) {
            Maybe!Command command = COMMAND_BINDINGS[].commandOf(symbol, press);
            if (command.exists) {
                run(command.value);
            } else if (symbol >= WebKey.digit1 && symbol <= WebKey.digit9) {
                selectMaterial(cast(uint)(symbol - WebKey.digit1));
            } else {
                held.holdBound(KEY_BINDINGS[], symbol);
            }
        }
    }

    void run(Command command) {
        final switch (command) {
            case Command.walkMode:
                game.toggleMode(MovementMode.walk);
                marks.set(SessionMark.titleStale);
                break;
            case Command.noclipMode:
                game.toggleMode(MovementMode.noclip);
                marks.set(SessionMark.titleStale);
                break;
            case Command.previousWorld:
                switchWorld(WorldStep.previous);
                break;
            case Command.nextWorld:
                switchWorld(WorldStep.next);
                break;
            case Command.throwBlock:
                game.throwBlock();
                break;
            case Command.nextPreset:
                game.nextPreset();
                marks.set(SessionMark.titleStale);
                break;
            case Command.dose:
                game.doseNext();
                break;
            case Command.use:
                game.use();
                break;
            case Command.eat:
                game.eat();
                break;
        }
    }

    void selectMaterial(uint index) {
        bool changed = game.inventory.select(index);
        if (changed) {
            marks.set(SessionMark.titleStale);
        }
    }

    void switchWorld(WorldStep direction) {
        worldIndex = steppedWorld(worldIndex, direction);
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

    void capture(MouseCapture state) {
        mouse = state;
        if (state == MouseCapture.released) {
            held = Flags!Key.init;
        }
        marks.set(SessionMark.titleStale);
    }
}

__gshared Session* session;

extern (C) void web_start(uint width, uint height, float renderRadius) {
    gatherWorlds();
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
    session.held.letGoBound(KEY_BINDINGS[], cast(WebKey) key);
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
    session.capture(cast(MouseCapture) state);
}
