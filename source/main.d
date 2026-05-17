import std.stdio;
import std.conv : to;
import std.file : exists, readText;
import std.string : strip, split, splitLines, startsWith;
import std.format : format;
import core.stdc.string : strlen;
import core.stdc.stdlib : system;
import bindings.sdl3;
import client.graphics;
import client.sim;
import common.sim_config;
import common.proto;

enum : ulong {
    WINDOW_VULKAN    = 0x0000000010000000,
    WINDOW_RESIZABLE = 0x0000000000000020,
}

void main(string[] args) {
    writeln("mined - hyperbolic voxel engine");

    // Parse --script <file> (deterministic timed-input test driver).
    string scriptPath;
    foreach (i, a; args) {
        if (a == "--script" && i + 1 < args.length) {
            scriptPath = args[i + 1];
        }
    }
    Script script;
    if (scriptPath.length > 0) {
        if (!exists(scriptPath)) {
            writefln("script file not found: %s", scriptPath);
            return;
        }
        script = Script.parse(readText(scriptPath));
        writefln("Loaded test script %s with %d events", scriptPath, script.events.length);
    }

    if (!SDL_Init(SDL_INIT_VIDEO)) {
        auto err = SDL_GetError();
        if (err !is null) {
            writefln("SDL init failed: %s", err[0..strlen(err)]);
        } else {
            writefln("SDL init failed: (no error string)");
        }
        return;
    }
    scope(exit) SDL_Quit();

    writeln("SDL3 initialized");

    auto window = SDL_CreateWindow("mined", 1280, 720,
        WINDOW_VULKAN | WINDOW_RESIZABLE);
    if (window is null) {
        writefln("Window creation failed");
        return;
    }
    scope(exit) SDL_DestroyWindow(window);

    // X11 window id (used by scripted screenshot commands via `import`)
    auto props = SDL_GetWindowProperties(window);
    ulong xWindowId = SDL_GetNumberProperty(props, "SDL.window.x11.window", 0);
    writefln("X11 window id: 0x%x", xWindowId);

    // Capture the mouse for FPS-style look (skipped in script mode so headless
    // tests don't yank the cursor from elsewhere).
    if (scriptPath.length == 0) {
        SDL_SetWindowRelativeMouseMode(window, true);
    }

    writeln("Window created, initializing renderer...");

    Renderer renderer;
    if (!renderer.init(cast(void*)window)) {
        writeln("Renderer initialization failed");
        return;
    }
    scope(exit) renderer.cleanup();

    auto cfg = SimConfig.fromRaw();
    auto sim = ClientSim.create(cfg, cast(EntityId)1);
    writefln("Sim initialized (chunkSize=%d, stepInterval=%s)", cfg.chunkSize, cfg.stepInterval);

    writeln("Entering render loop...");
    if (script.events.length == 0) {
        writeln("Controls: arrows = look, WASD = move, space/lshift = up/down, Esc = quit");
    } else {
        writeln("Running scripted input mode (deterministic dt = 0.016)");
    }

    bool running = true;
    SDL_Event ev;
    CameraInput cam;
    int interactiveShotIndex = 0;
    float dt = 0.016f;
    float simTime = 0;
    // Mouse-look delta accumulated this frame.
    float mouseDx = 0;
    float mouseDy = 0;
    // FPS counter
    ulong startTicks = SDL_GetTicks();
    ulong lastFpsReport = startTicks;
    ulong framesSinceReport = 0;

    while (running) {
        mouseDx = 0;
        mouseDy = 0;
        // Real SDL events still pump (so window manager events get processed),
        // but in script mode we ignore keyboard and use the script instead.
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_EVENT_QUIT) {
                running = false;
            }
            if (script.events.length == 0) {
                if (ev.type == SDL_EVENT_KEY_DOWN) {
                    if (ev.key.key == SDLK_ESCAPE) {
                        running = false;
                    } else if (ev.key.key == SDLK_F12) {
                        auto path = format("/tmp/mined_shot_%03d.png", interactiveShotIndex++);
                        auto cmd = format("import -window 0x%x %s", xWindowId, path);
                        writefln("F12 screenshot -> %s", path);
                        import std.string : toStringz;
                        system(cmd.toStringz);
                    } else {
                        handleKeyDown(ev.key.key, cam);
                    }
                }
                if (ev.type == SDL_EVENT_KEY_UP) {
                    handleKeyUp(ev.key.key, cam);
                }
                if (ev.type == SDL_EVENT_MOUSE_MOTION) {
                    mouseDx += ev.motion.xrel;
                    mouseDy += ev.motion.yrel;
                }
            }
        }

        if (script.events.length > 0) {
            if (!script.tick(simTime, cam, xWindowId, running)) {
                running = false;
            }
        }

        if (!running) {
            break;
        }

        sim.step++;
        enum float MOUSE_SENS = 0.003f;
        renderer.rotateCamera(
            cam.yawRate * dt - mouseDx * MOUSE_SENS,
            cam.pitchRate * dt - mouseDy * MOUSE_SENS);
        renderer.moveCamera(cam.strafe * dt, cam.vert * dt, cam.fwd * dt);
        renderer.render(dt);

        simTime += dt;
        framesSinceReport++;
        auto nowTicks = SDL_GetTicks();
        if (nowTicks - lastFpsReport >= 1000) {
            float fps = framesSinceReport * 1000.0f / (nowTicks - lastFpsReport);
            writefln("[wall=%ss sim=%ss] FPS=%.1f", (nowTicks - startTicks) / 1000, cast(int)simTime, fps);
            stdout.flush();
            framesSinceReport = 0;
            lastFpsReport = nowTicks;
        }
    }

    writeln("Exiting.");
}

struct CameraInput {
    float yawRate = 0;
    float pitchRate = 0;
    float fwd = 0;
    float strafe = 0;
    float vert = 0;
}

private void handleKeyDown(uint key, ref CameraInput cam) {
    enum float TURN = 1.5f;
    enum float MOVE = 1.0f;
    if (key == SDLK_ESCAPE) {
        return;
    }
    if (key == SDLK_LEFT) {
        cam.yawRate = -TURN;
    }
    if (key == SDLK_RIGHT) {
        cam.yawRate = TURN;
    }
    if (key == SDLK_UP) {
        cam.pitchRate = -TURN;
    }
    if (key == SDLK_DOWN) {
        cam.pitchRate = TURN;
    }
    if (key == SDLK_W) {
        cam.fwd = -MOVE;
    }
    if (key == SDLK_S) {
        cam.fwd = MOVE;
    }
    if (key == SDLK_A) {
        cam.strafe = -MOVE;
    }
    if (key == SDLK_D) {
        cam.strafe = MOVE;
    }
    if (key == SDLK_SPACE) {
        cam.vert = MOVE;
    }
    if (key == SDLK_LSHIFT) {
        cam.vert = -MOVE;
    }
}

private void handleKeyUp(uint key, ref CameraInput cam) {
    if (key == SDLK_LEFT || key == SDLK_RIGHT) {
        cam.yawRate = 0;
    }
    if (key == SDLK_UP || key == SDLK_DOWN) {
        cam.pitchRate = 0;
    }
    if (key == SDLK_W || key == SDLK_S) {
        cam.fwd = 0;
    }
    if (key == SDLK_A || key == SDLK_D) {
        cam.strafe = 0;
    }
    if (key == SDLK_SPACE || key == SDLK_LSHIFT) {
        cam.vert = 0;
    }
}

// ---- Test scripting ("MIDI for testing") -------------------------------------
//
// Script file format: one event per line, "<seconds> <command> [args...]".
// Comments begin with '#' or ';'. Blank lines ignored.
//
// Commands:
//   down <key>           - press a key (down event)
//   up <key>             - release a key
//   screenshot <path>    - capture current window via `import` to path
//   quit                 - terminate the program
//
// Keys: w, a, s, d, space, lshift, left, right, up, down, esc

struct ScriptEvent {
    float time;
    string command;
    string arg;
}

struct Script {
    ScriptEvent[] events;
    size_t cursor;

    static Script parse(string text) {
        Script s;
        foreach (line; text.splitLines()) {
            auto trimmed = line.strip();
            if (trimmed.length == 0 || trimmed.startsWith("#") || trimmed.startsWith(";")) {
                continue;
            }
            auto parts = trimmed.split();
            if (parts.length < 2) {
                continue;
            }
            ScriptEvent e;
            try {
                e.time = parts[0].to!float;
            } catch (Exception) {
                continue;
            }
            e.command = parts[1];
            if (parts.length >= 3) {
                e.arg = parts[2 .. $].join_();
            }
            s.events ~= e;
        }
        return s;
    }

    /// Returns false if "quit" event fired.
    bool tick(float now, ref CameraInput cam, ulong xwid, ref bool running) {
        while (cursor < events.length && events[cursor].time <= now) {
            auto e = events[cursor++];
            applyEvent(e, cam, xwid, running);
        }
        return running;
    }

    private static void applyEvent(ScriptEvent e, ref CameraInput cam, ulong xwid, ref bool running) {
        if (e.command == "down") {
            handleKeyDown(keyFromName(e.arg), cam);
        } else if (e.command == "up") {
            handleKeyUp(keyFromName(e.arg), cam);
        } else if (e.command == "screenshot") {
            auto cmd = format("import -window 0x%x %s", xwid, e.arg);
            writefln("[script t=%s] %s", e.time, cmd);
            import std.string : toStringz;
            system(cmd.toStringz);
        } else if (e.command == "quit") {
            writefln("[script t=%s] quit", e.time);
            running = false;
        } else {
            writefln("[script] unknown command: %s", e.command);
        }
    }
}

private string join_(string[] parts) {
    string r;
    foreach (i, p; parts) {
        if (i > 0) {
            r ~= " ";
        }
        r ~= p;
    }
    return r;
}

private uint keyFromName(string name) {
    switch (name) {
        case "w":      return SDLK_W;
        case "a":      return SDLK_A;
        case "s":      return SDLK_S;
        case "d":      return SDLK_D;
        case "space":  return SDLK_SPACE;
        case "lshift": return SDLK_LSHIFT;
        case "left":   return SDLK_LEFT;
        case "right":  return SDLK_RIGHT;
        case "up":     return SDLK_UP;
        case "down":   return SDLK_DOWN;
        case "esc":    return SDLK_ESCAPE;
        default:       return 0;
    }
}
