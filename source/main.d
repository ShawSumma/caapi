import std.stdio;
import std.format : format;
import std.string : toStringz;
import core.stdc.string : strlen;
import core.stdc.stdlib : system;
import std.conv : to;
import bindings.sdl3;
import client.config : ClientConfig;
import client.game : Game, FrameInput, InputState, Key, MATERIAL_PALETTE, axis, modeName;
import client.graphics;
import client.script : ScriptRecorder;

enum : ulong {
    WINDOW_VULKAN    = 0x0000000010000000,
    WINDOW_RESIZABLE = 0x0000000000000020,
}

enum ubyte CHUNK_DIMENSION = 12;
// Longest frame the simulation will take in one step, in seconds.
enum float MAX_FRAME_SECONDS = 0.1f;

void main(string[] args) {
    writeln("mined - hyperbolic voxel engine");

    string configPath = "mined.cfg";
    string recordPath;
    bool flatWorldgen = false;
    foreach (i, a; args) {
        if (a == "--config" && i + 1 < args.length) {
            configPath = args[i + 1];
        }
        if (a == "--record" && i + 1 < args.length) {
            recordPath = args[i + 1];
        }
        if (a == "--flat") {
            flatWorldgen = true;
            writeln("flat worldgen enabled");
        }
    }

    ClientConfig cfg = ClientConfig.load(configPath);
    foreach (i, a; args) {
        if (a == "--sensitivity" && i + 1 < args.length) {
            cfg.mouseSensitivity = args[i + 1].to!float;
        }
        if (a == "--invert-y") {
            cfg.invertY = true;
        }
    }

    Session session;
    if (recordPath.length > 0) {
        session.recorder.open(recordPath);
        writefln("recording to %s", recordPath);
    }

    if (!SDL_Init(SDL_INIT_VIDEO)) {
        const(char)* err = SDL_GetError();
        if (err !is null) {
            writefln("SDL init failed: %s", err[0 .. strlen(err)]);
        }
        return;
    }
    scope(exit) {
        SDL_Quit();
    }

    SDL_Window* window = SDL_CreateWindow("mined", 1280, 720, WINDOW_VULKAN | WINDOW_RESIZABLE);
    if (window is null) {
        writeln("Window creation failed");
        return;
    }
    scope(exit) {
        SDL_DestroyWindow(window);
    }

    uint props = SDL_GetWindowProperties(window);
    ulong xWindowId = SDL_GetNumberProperty(props, "SDL.window.x11.window", 0);

    Renderer renderer;
    if (!renderer.init(cast(void*) window, CHUNK_DIMENSION)) {
        writeln("Renderer initialization failed");
        return;
    }
    scope(exit) {
        renderer.cleanup();
    }
    Game game = Game.create(CHUNK_DIMENSION, flatWorldgen, cfg.reach);

    bool running = true;
    bool mouseCaptured = false;
    SDL_Event ev;
    InputState input;
    int shotIndex = 0;
    float mouseDx = 0;
    float mouseDy = 0;
    float lastFps = 0;
    ulong lastTicks = SDL_GetTicks();
    ulong framesSinceReport = 0;
    ulong lastFpsReport = lastTicks;

    updateWindowTitle(window, mouseCaptured, game, lastFps);

    float frameMaxMs = 0;
    float vaccMax = 0;

    while (running) {
        ulong nowTicks = SDL_GetTicks();
        float dt = (nowTicks - lastTicks) / 1000.0f;
        lastTicks = nowTicks;
        if (dt * 1000.0f > frameMaxMs) {
            frameMaxMs = dt * 1000.0f;
        }
        if (dt > MAX_FRAME_SECONDS) {
            dt = MAX_FRAME_SECONDS;
        }

        mouseDx = 0;
        mouseDy = 0;
        bool titleDirty = false;

        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_EVENT_QUIT) {
                running = false;
            }
            processInteractiveInput(
                ev, window, input, game, session, mouseCaptured,
                mouseDx, mouseDy, titleDirty, xWindowId, shotIndex);
        }
        if (!running) {
            break;
        }

        float invY = cfg.invertY ? -1.0f : 1.0f;
        float yawRate = (axis(input[Key.yawRight]) - axis(input[Key.yawLeft])) * cfg.turnSpeed;
        float pitchRate = (axis(input[Key.pitchDown]) - axis(input[Key.pitchUp])) * cfg.turnSpeed;
        FrameInput frame;
        frame.keys = input;
        frame.yaw = yawRate * dt + mouseDx * cfg.mouseSensitivity;
        frame.pitch = pitchRate * dt + mouseDy * cfg.mouseSensitivity * invY;
        if (session.recorder.isOpen()) {
            session.recorder.frame(frame, dt);
        }

        game.step(frame, dt);
        if (game.vacc > vaccMax) {
            vaccMax = game.vacc;
        }
        renderer.render(game.world, dt);

        framesSinceReport++;
        if (nowTicks - lastFpsReport >= 1000) {
            lastFps = framesSinceReport * 1000.0f / (nowTicks - lastFpsReport);
            writefln("FPS=%.1f frame max=%.0fms | mode=%s ground=%s vel=[%.3f %.3f %.3f] traveled=%.3f vacc=%.2f",
                lastFps, frameMaxMs, modeName(game.flyMode, game.noClip), game.onGround,
                game.velocity[0], game.velocity[1], game.velocity[2], game.traveled, vaccMax);
            vaccMax = 0;
            stdout.flush();
            framesSinceReport = 0;
            frameMaxMs = 0;
            lastFpsReport = nowTicks;
            titleDirty = true;
        }

        if (titleDirty) {
            updateWindowTitle(window, mouseCaptured, game, lastFps);
        }
    }

    if (session.recorder.isOpen()) {
        session.recorder.close();
        writefln("recording saved to %s", recordPath);
    }
    writefln("session: traveled=%.3f", game.traveled);
}

void updateWindowTitle(SDL_Window* window, bool mouseCaptured, const ref Game game, float fps) {
    string mode = modeName(game.flyMode, game.noClip);
    string title;
    if (mouseCaptured) {
        title = format("mined — %s (V) — [%d] %s — Esc to release mouse — FPS %.0f",
            mode, game.materialIndex + 1, game.material(), fps);
    } else {
        title = format("mined — %s (V) — click to capture mouse — FPS %.0f", mode, fps);
    }
    SDL_SetWindowTitle(window, title.toStringz);
}

// Per-run interaction state threaded through the input handlers.
struct Session {
    // True when SDL relative mouse mode is unavailable (e.g. X11 without
    // XInput2) and we emulate it by warping the cursor back to the window
    // center every frame.
    bool warpFallback;
    // --record: live play written as a replayable Lua script.
    ScriptRecorder recorder;
}

void recordEvent(ref Session session, string call) {
    if (session.recorder.isOpen()) {
        session.recorder.event(call);
    }
}

void setMouseCaptured(SDL_Window* window, ref Session session, ref bool mouseCaptured, ref InputState input, bool captured) {
    if (mouseCaptured == captured) {
        return;
    }
    if (captured) {
        if (!SDL_SetWindowRelativeMouseMode(window, true)) {
            const(char)* err = SDL_GetError();
            if (err !is null && !session.warpFallback) {
                writefln("relative mouse mode unavailable (%s), using warp fallback", err[0 .. strlen(err)]);
            }
            session.warpFallback = true;
            SDL_SetWindowMouseGrab(window, true);
            SDL_HideCursor();
            warpToCenter(window);
        }
    } else {
        if (session.warpFallback) {
            SDL_SetWindowMouseGrab(window, false);
            SDL_ShowCursor();
        } else {
            SDL_SetWindowRelativeMouseMode(window, false);
        }
    }
    mouseCaptured = captured;
    if (!captured) {
        input.clear();
    }
}

void warpToCenter(SDL_Window* window) {
    int w = 0;
    int h = 0;
    SDL_GetWindowSize(window, &w, &h);
    SDL_WarpMouseInWindow(window, cast(float)(w / 2), cast(float)(h / 2));
}

void processInteractiveInput(
    ref SDL_Event ev,
    SDL_Window* window,
    ref InputState input,
    ref Game game,
    ref Session session,
    ref bool mouseCaptured,
    ref float mouseDx,
    ref float mouseDy,
    ref bool titleDirty,
    ulong xWindowId,
    ref int shotIndex,
) {
    if (ev.type == SDL_EVENT_KEY_DOWN) {
        if (ev.key.key == SDLK_ESCAPE) {
            if (mouseCaptured) {
                setMouseCaptured(window, session, mouseCaptured, input, false);
                titleDirty = true;
            }
        } else if (ev.key.key == SDLK_F12) {
            string path = format("mined_shot_%03d.png", shotIndex++);
            // Run in the background so capture doesn't stall the frame loop.
            string cmd = format("import -window 0x%x %s &", xWindowId, path);
            writefln("F12 screenshot -> %s", path);
            system(cmd.toStringz);
        } else if (ev.key.scancode == SDL_SCANCODE_V && !ev.key.repeat) {
            game.flyMode = !game.flyMode;
            writefln("mode: %s", modeName(game.flyMode, game.noClip));
            recordModeChange(session, game);
            titleDirty = true;
        } else if (ev.key.scancode == SDL_SCANCODE_N && !ev.key.repeat) {
            game.noClip = !game.noClip;
            writefln("mode: %s", modeName(game.flyMode, game.noClip));
            recordModeChange(session, game);
            titleDirty = true;
        } else if (ev.key.scancode >= SDL_SCANCODE_1 && ev.key.scancode <= SDL_SCANCODE_9) {
            int idx = cast(int)(ev.key.scancode - SDL_SCANCODE_1);
            if (idx < MATERIAL_PALETTE.length && idx != game.materialIndex) {
                game.materialIndex = idx;
                writefln("material: [%d] %s", idx + 1, game.material());
                recordEvent(session, format("material(%d)", idx + 1));
                titleDirty = true;
            }
        } else {
            setMovementKey(ev.key.scancode, input, true);
        }
    }

    if (ev.type == SDL_EVENT_KEY_UP) {
        setMovementKey(ev.key.scancode, input, false);
    }

    if (ev.type == SDL_EVENT_WINDOW_FOCUS_LOST) {
        // Key-up events stop arriving once focus is gone; drop all held keys
        // and release the mouse so the player isn't stuck moving or captured.
        input.clear();
        setMouseCaptured(window, session, mouseCaptured, input, false);
        titleDirty = true;
    }

    if (ev.type == SDL_EVENT_MOUSE_MOTION && mouseCaptured) {
        if (session.warpFallback) {
            // Deltas are measured against the window center and the cursor is
            // warped straight back, so the warp's own motion event lands at
            // the center and contributes zero — no events need skipping.
            int w = 0;
            int h = 0;
            SDL_GetWindowSize(window, &w, &h);
            float cx = cast(float)(w / 2);
            float cy = cast(float)(h / 2);
            mouseDx += ev.motion.x - cx;
            mouseDy += ev.motion.y - cy;
            if (ev.motion.x != cx || ev.motion.y != cy) {
                SDL_WarpMouseInWindow(window, cx, cy);
            }
        } else {
            mouseDx += ev.motion.xrel;
            mouseDy += ev.motion.yrel;
        }
    }

    if (ev.type == SDL_EVENT_MOUSE_BUTTON_DOWN) {
        if (!mouseCaptured) {
            setMouseCaptured(window, session, mouseCaptured, input, true);
            titleDirty = true;
        } else if (ev.button.button == SDL_BUTTON_LEFT) {
            game.breakBlock();
            recordEvent(session, "break_block()");
        } else if (ev.button.button == SDL_BUTTON_RIGHT) {
            game.placeBlock();
            recordEvent(session, "place_block()");
        }
    }
}

/// The noclip and fly toggles don't commute, so the resulting mode is
/// recorded rather than the keypress.
void recordModeChange(ref Session session, const ref Game game) {
    recordEvent(session, format("mode(\"%s\")", modeName(game.flyMode, game.noClip)));
}

/// Movement uses scancodes (physical key positions) so WASD stays WASD on
/// non-QWERTY layouts.
void setMovementKey(uint scancode, ref InputState input, bool held) {
    switch (scancode) {
        case SDL_SCANCODE_W: input.held[Key.fwd] = held; break;
        case SDL_SCANCODE_S: input.held[Key.back] = held; break;
        case SDL_SCANCODE_A: input.held[Key.left] = held; break;
        case SDL_SCANCODE_D: input.held[Key.right] = held; break;
        case SDL_SCANCODE_SPACE: input.held[Key.up] = held; break;
        case SDL_SCANCODE_LSHIFT: input.held[Key.down] = held; break;
        case SDL_SCANCODE_LEFT: input.held[Key.yawLeft] = held; break;
        case SDL_SCANCODE_RIGHT: input.held[Key.yawRight] = held; break;
        case SDL_SCANCODE_UP: input.held[Key.pitchUp] = held; break;
        case SDL_SCANCODE_DOWN: input.held[Key.pitchDown] = held; break;
        default: break;
    }
}
