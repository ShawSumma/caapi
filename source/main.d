import std.stdio;
import std.file : exists, readText;
import std.format : format;
import std.string : toStringz;
import core.stdc.string : strlen;
import core.stdc.stdlib : system;
import std.conv : to;
import bindings.sdl3;
import client.config : ClientConfig;
import client.graphics;
import client.script;
import common.world;
import worldcheck : dumpWorld, benchNearby, benchGen, benchDrive;

enum : ulong {
    WINDOW_VULKAN    = 0x0000000010000000,
    WINDOW_RESIZABLE = 0x0000000000000020,
}

immutable Material[9] MATERIAL_PALETTE = [
    Material.WoodPlanks,
    Material.Wood,
    Material.Leaves,
    Material.GreyBrick,
    Material.WhiteBrick,
    Material.Sandstone,
    Material.Marble,
    Material.Granite,
    Material.Basalt,
];

/// Held-key state, tracked per key so opposite keys don't cancel each
/// other's release, and clearable in one go when the window loses focus.
struct InputState {
    bool fwd;
    bool back;
    bool left;
    bool right;
    bool up;
    bool down;
    bool rollLeft;
    bool rollRight;
    bool yawLeft;
    bool yawRight;
    bool pitchUp;
    bool pitchDown;

    void clear() {
        this = InputState.init;
    }
}

void main(string[] args) {
    foreach (i, a; args) {
        if (a == "--dump-world") {
            float radius = (i + 1 < args.length) ? args[i + 1].to!float : 3.0f;
            dumpWorld(radius, 12);
            return;
        }
        if (a == "--bench-gen") {
            float radius = (i + 1 < args.length) ? args[i + 1].to!float : 2.5f;
            benchGen(radius, 12);
            return;
        }
        if (a == "--bench-drive") {
            float radius = (i + 1 < args.length) ? args[i + 1].to!float : 2.5f;
            benchDrive(radius, 12);
            return;
        }
        if (a == "--bench-nearby") {
            float radius = (i + 1 < args.length) ? args[i + 1].to!float : 4.5f;
            int iters = (i + 2 < args.length) ? args[i + 2].to!int : 50;
            benchNearby(radius, iters, 12);
            return;
        }
    }

    writeln("mined - hyperbolic voxel engine");

    string scriptPath;
    string configPath = "mined.cfg";
    foreach (i, a; args) {
        if (a == "--script" && i + 1 < args.length) {
            scriptPath = args[i + 1];
        }
        if (a == "--config" && i + 1 < args.length) {
            configPath = args[i + 1];
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

    Script script;
    if (scriptPath.length > 0) {
        if (!exists(scriptPath)) {
            writefln("script not found: %s", scriptPath);
            return;
        }
        script = Script.parse(readText(scriptPath));
        writefln("Loaded script %s (%d events)", scriptPath, script.events.length);
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
    if (!renderer.init(cast(void*) window)) {
        writeln("Renderer initialization failed");
        return;
    }
    scope(exit) {
        renderer.cleanup();
    }
    renderer.reach = cfg.reach;

    bool running = true;
    bool mouseCaptured = false;
    int materialIndex = 0;
    SDL_Event ev;
    CameraInput cam;
    InputState input;
    int shotIndex = 0;
    float simTime = 0;
    float mouseDx = 0;
    float mouseDy = 0;
    float lastFps = 0;
    ulong lastTicks = SDL_GetTicks();
    ulong framesSinceReport = 0;
    ulong lastFpsReport = lastTicks;

    updateWindowTitle(window, mouseCaptured, materialIndex, lastFps);

    while (running) {
        ulong nowTicks = SDL_GetTicks();
        float dt = (nowTicks - lastTicks) / 1000.0f;
        lastTicks = nowTicks;
        if (dt > 0.1f) {
            dt = 0.1f;
        }

        if (script.events.length > 0) {
            dt = 0.016f;
        }

        mouseDx = 0;
        mouseDy = 0;
        bool titleDirty = false;

        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_EVENT_QUIT) {
                running = false;
            }

            if (script.events.length == 0) {
                processInteractiveInput(
                    ev, window, input, renderer, mouseCaptured,
                    mouseDx, mouseDy, materialIndex, titleDirty,
                    xWindowId, shotIndex);
            }
        }

        if (script.events.length > 0) {
            script.tick(simTime, xWindowId, running);
            cam.fwd = script.fwd;
            cam.strafe = script.strafe;
            cam.vert = script.vert;
            cam.yawRate = script.yawRate;
            cam.pitchRate = script.pitchRate;
            cam.rollRate = 0;
        } else {
            cam.fwd = (axis(input.back) - axis(input.fwd)) * cfg.moveSpeed;
            cam.strafe = (axis(input.right) - axis(input.left)) * cfg.moveSpeed;
            cam.vert = (axis(input.up) - axis(input.down)) * cfg.moveSpeed;
            cam.yawRate = (axis(input.yawRight) - axis(input.yawLeft)) * cfg.turnSpeed;
            cam.pitchRate = (axis(input.pitchDown) - axis(input.pitchUp)) * cfg.turnSpeed;
            cam.rollRate = (axis(input.rollLeft) - axis(input.rollRight)) * cfg.turnSpeed;
        }

        if (!running) {
            break;
        }

        float invY = cfg.invertY ? -1.0f : 1.0f;
        float yaw = cam.yawRate * dt + mouseDx * cfg.mouseSensitivity;
        float pitch = cam.pitchRate * dt + mouseDy * cfg.mouseSensitivity * invY;
        float roll = cam.rollRate * dt;
        renderer.rotateCamera(yaw, pitch, roll);
        renderer.moveCamera(cam.strafe * dt, cam.vert * dt, cam.fwd * dt);
        renderer.render(dt);
        simTime += dt;

        framesSinceReport++;
        if (nowTicks - lastFpsReport >= 1000) {
            lastFps = framesSinceReport * 1000.0f / (nowTicks - lastFpsReport);
            writefln("FPS=%.1f", lastFps);
            stdout.flush();
            framesSinceReport = 0;
            lastFpsReport = nowTicks;
            titleDirty = true;
        }

        if (titleDirty) {
            updateWindowTitle(window, mouseCaptured, materialIndex, lastFps);
        }
    }
}

float axis(bool held) {
    return held ? 1.0f : 0.0f;
}

void updateWindowTitle(SDL_Window* window, bool mouseCaptured, int materialIndex, float fps) {
    string title;
    if (mouseCaptured) {
        title = format("mined — [%d] %s — Esc to release mouse — FPS %.0f",
            materialIndex + 1, MATERIAL_PALETTE[materialIndex], fps);
    } else {
        title = format("mined — click to capture mouse — FPS %.0f", fps);
    }
    SDL_SetWindowTitle(window, title.toStringz);
}

// True when SDL relative mouse mode is unavailable (e.g. X11 without
// XInput2) and we emulate it by warping the cursor back to the window
// center every frame.
bool warpFallback = false;

void setMouseCaptured(SDL_Window* window, ref bool mouseCaptured, ref InputState input, bool captured) {
    if (mouseCaptured == captured) {
        return;
    }
    if (captured) {
        if (!SDL_SetWindowRelativeMouseMode(window, true)) {
            const(char)* err = SDL_GetError();
            if (err !is null && !warpFallback) {
                writefln("relative mouse mode unavailable (%s), using warp fallback", err[0 .. strlen(err)]);
            }
            warpFallback = true;
            SDL_SetWindowMouseGrab(window, true);
            SDL_HideCursor();
            warpToCenter(window);
        }
    } else {
        if (warpFallback) {
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
    ref Renderer renderer,
    ref bool mouseCaptured,
    ref float mouseDx,
    ref float mouseDy,
    ref int materialIndex,
    ref bool titleDirty,
    ulong xWindowId,
    ref int shotIndex,
) {
    if (ev.type == SDL_EVENT_KEY_DOWN) {
        if (ev.key.key == SDLK_ESCAPE) {
            if (mouseCaptured) {
                setMouseCaptured(window, mouseCaptured, input, false);
                titleDirty = true;
            }
        } else if (ev.key.key == SDLK_F12) {
            string path = format("mined_shot_%03d.png", shotIndex++);
            // Run in the background so capture doesn't stall the frame loop.
            string cmd = format("import -window 0x%x %s &", xWindowId, path);
            writefln("F12 screenshot -> %s", path);
            system(cmd.toStringz);
        } else if (ev.key.scancode >= SDL_SCANCODE_1 && ev.key.scancode <= SDL_SCANCODE_9) {
            int idx = cast(int)(ev.key.scancode - SDL_SCANCODE_1);
            if (idx < MATERIAL_PALETTE.length && idx != materialIndex) {
                materialIndex = idx;
                writefln("material: [%d] %s", idx + 1, MATERIAL_PALETTE[idx]);
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
        setMouseCaptured(window, mouseCaptured, input, false);
        titleDirty = true;
    }

    if (ev.type == SDL_EVENT_MOUSE_MOTION && mouseCaptured) {
        if (warpFallback) {
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
            setMouseCaptured(window, mouseCaptured, input, true);
            titleDirty = true;
        } else if (ev.button.button == SDL_BUTTON_LEFT) {
            renderer.breakBlock();
        } else if (ev.button.button == SDL_BUTTON_RIGHT) {
            renderer.placeBlock(cast(ushort) MATERIAL_PALETTE[materialIndex]);
        }
    }
}

struct CameraInput {
    float yawRate = 0;
    float pitchRate = 0;
    float rollRate = 0;
    float fwd = 0;
    float strafe = 0;
    float vert = 0;
}

/// Movement uses scancodes (physical key positions) so WASD stays WASD on
/// non-QWERTY layouts.
void setMovementKey(uint scancode, ref InputState input, bool held) {
    switch (scancode) {
        case SDL_SCANCODE_W: input.fwd = held; break;
        case SDL_SCANCODE_S: input.back = held; break;
        case SDL_SCANCODE_A: input.left = held; break;
        case SDL_SCANCODE_D: input.right = held; break;
        case SDL_SCANCODE_Q: input.rollLeft = held; break;
        case SDL_SCANCODE_E: input.rollRight = held; break;
        case SDL_SCANCODE_SPACE: input.up = held; break;
        case SDL_SCANCODE_LSHIFT: input.down = held; break;
        case SDL_SCANCODE_LEFT: input.yawLeft = held; break;
        case SDL_SCANCODE_RIGHT: input.yawRight = held; break;
        case SDL_SCANCODE_UP: input.pitchUp = held; break;
        case SDL_SCANCODE_DOWN: input.pitchDown = held; break;
        default: break;
    }
}
