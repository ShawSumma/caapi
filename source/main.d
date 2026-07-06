import std.stdio;
import std.file : exists, readText;
import std.format : format;
import std.string : split, splitLines, startsWith, strip, toStringz;
import core.stdc.string : strlen;
import core.stdc.stdlib : system;
import std.conv : to;
import std.math : tanh;
import bindings.sdl3;
import client.config : ClientConfig;
import client.graphics;
import client.local_character_controller : LocalCharacterController;
import client.script;
import common.character_controller : runCharacterStep, getRelativeUp;
import common.proto : CharacterInput;
import common.sim_config : SimConfig, SimConfigRaw;
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
    string recordPath;
    string replayPath;
    foreach (i, a; args) {
        if (a == "--script" && i + 1 < args.length) {
            scriptPath = args[i + 1];
        }
        if (a == "--config" && i + 1 < args.length) {
            configPath = args[i + 1];
        }
        if (a == "--record" && i + 1 < args.length) {
            recordPath = args[i + 1];
        }
        if (a == "--replay" && i + 1 < args.length) {
            replayPath = args[i + 1];
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

    if (recordPath.length > 0 && replayPath.length == 0 && scriptPath.length == 0) {
        recordFile = File(recordPath, "w");
        recordFile.writeln("# mined-actions v1");
        recording = true;
        writefln("recording actions to %s", recordPath);
    }

    string[] replayLines;
    size_t replayCursor = 0;
    bool replayMode = false;
    if (replayPath.length > 0) {
        if (!exists(replayPath)) {
            writefln("replay not found: %s", replayPath);
            return;
        }
        foreach (line; readText(replayPath).splitLines()) {
            string trimmed = line.strip();
            if (trimmed.length > 0 && trimmed[0] != '#') {
                replayLines ~= trimmed;
            }
        }
        replayMode = true;
        writefln("replaying %d action lines from %s", replayLines.length, replayPath);
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
    SimConfig simCfg = SimConfig.fromRaw();
    // Config reach is in voxel-meters; the caster wants the tanh of the
    // absolute hyperbolic distance.
    renderer.reach = tanh(cfg.reach * simCfg.metersToAbsolute);
    LocalCharacterController character = LocalCharacterController.create();
    character.position = renderer.camPos;
    character.up = getRelativeUp(&renderer.graph, &character.position);
    character.alignToGravity();
    float[3] velocity = [0, 0, 0];
    bool onGround = false;
    bool noClip = true;

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

    updateWindowTitle(window, mouseCaptured, materialIndex, noClip, lastFps);

    float frameMaxMs = 0;

    while (running) {
        ulong nowTicks = SDL_GetTicks();
        float dt = (nowTicks - lastTicks) / 1000.0f;
        lastTicks = nowTicks;
        if (dt * 1000.0f > frameMaxMs) {
            frameMaxMs = dt * 1000.0f;
        }
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

            if (replayMode) {
                if (ev.type == SDL_EVENT_KEY_DOWN && ev.key.key == SDLK_ESCAPE) {
                    running = false;
                }
            } else if (script.events.length == 0) {
                processInteractiveInput(
                    ev, window, input, renderer, mouseCaptured,
                    mouseDx, mouseDy, materialIndex, noClip, titleDirty,
                    xWindowId, shotIndex);
            }
        }

        float replayYaw = 0;
        float replayPitch = 0;
        if (replayMode) {
            bool gotFrame = false;
            while (replayCursor < replayLines.length) {
                string line = replayLines[replayCursor++];
                if (line.startsWith("f ")) {
                    string[] parts = line.split();
                    if (parts.length >= 5) {
                        dt = parts[1].to!float;
                        replayYaw = parts[2].to!float;
                        replayPitch = parts[3].to!float;
                        input = unpackInput(parts[4].to!uint(16));
                        gotFrame = true;
                    }
                    break;
                } else if (line == "b") {
                    renderer.breakBlock();
                } else if (line == "p") {
                    renderer.placeBlock(cast(ushort) MATERIAL_PALETTE[materialIndex]);
                } else if (line.startsWith("m ")) {
                    materialIndex = line.split()[1].to!int;
                } else if (line == "v") {
                    noClip = !noClip;
                }
            }
            if (!gotFrame) {
                writeln("replay finished");
                running = false;
            }
        }

        if (script.events.length > 0) {
            script.tick(simTime, xWindowId, running);
            cam.fwd = script.fwd;
            cam.strafe = script.strafe;
            cam.vert = script.vert;
            cam.yawRate = script.yawRate;
            cam.pitchRate = script.pitchRate;
        } else {
            cam.yawRate = (axis(input.yawRight) - axis(input.yawLeft)) * cfg.turnSpeed;
            cam.pitchRate = (axis(input.pitchDown) - axis(input.pitchUp)) * cfg.turnSpeed;
        }

        if (!running) {
            break;
        }

        float invY = cfg.invertY ? -1.0f : 1.0f;
        float yaw = cam.yawRate * dt + mouseDx * cfg.mouseSensitivity;
        float pitch = cam.pitchRate * dt + mouseDy * cfg.mouseSensitivity * invY;
        if (replayMode) {
            yaw = replayYaw;
            pitch = replayPitch;
        }
        if (recording) {
            // One line per frame: dt, final look deltas (sensitivity and
            // invert baked in), and the held-key bits. Event lines (b/p/m/v)
            // are written as they happen and precede their frame line.
            recordFile.writefln("f %.6f %.6f %.6f %x", dt, yaw, pitch, packInput(input));
        }

        if (script.events.length > 0) {
            // Script mode keeps direct camera control for reproducibility.
            renderer.rotateCamera(yaw, pitch, 0);
            renderer.moveCamera(cam.strafe * dt, cam.vert * dt, cam.fwd * dt);
        } else {
            // The quaternion axes are mirrored relative to the renderer's
            // rotation matrices, hence the negated deltas.
            character.lookLevel(-yaw, -pitch);

            float mx = axis(input.right) - axis(input.left);
            float my = axis(input.up) - axis(input.down);
            float mz = axis(input.back) - axis(input.fwd);

            CharacterInput cin;
            cin.noClip = noClip;
            if (noClip) {
                cin.movement = character.orientation.rotate([mx, my, mz]);
            } else {
                cin.movement = character.horizontalOrientation().rotate([mx, 0, mz]);
                cin.jump = input.up;
            }
            runCharacterStep(simCfg, renderer.graph, character.position,
                velocity, onGround, cin, dt);

            // Holonomy mitigation: "down" is re-derived from the world at the
            // new position every step, the view is transported to follow it,
            // and any residual roll is aligned away — so carrying the frame
            // around a loop can't accumulate rotation.
            float[3] newUp = getRelativeUp(&renderer.graph, &character.position);
            character.updatePosition(character.position, newUp, true);
            character.alignToGravity(cfg.rollAlignSpeed * dt);
            character.renormalizeOrientation();
            renderer.camPos = character.orientedPosition();
        }
        renderer.render(dt);
        simTime += dt;

        framesSinceReport++;
        if (nowTicks - lastFpsReport >= 1000) {
            lastFps = framesSinceReport * 1000.0f / (nowTicks - lastFpsReport);
            writefln("FPS=%.1f frame max=%.0fms", lastFps, frameMaxMs);
            stdout.flush();
            framesSinceReport = 0;
            frameMaxMs = 0;
            lastFpsReport = nowTicks;
            titleDirty = true;
        }

        if (titleDirty) {
            updateWindowTitle(window, mouseCaptured, materialIndex, noClip, lastFps);
        }
    }

    if (recording) {
        recording = false;
        recordFile.close();
        writefln("recording saved to %s", recordPath);
    }
}

float axis(bool held) {
    return held ? 1.0f : 0.0f;
}

void updateWindowTitle(SDL_Window* window, bool mouseCaptured, int materialIndex, bool noClip, float fps) {
    string mode = noClip ? "fly" : "walk";
    string title;
    if (mouseCaptured) {
        title = format("mined — %s (V) — [%d] %s — Esc to release mouse — FPS %.0f",
            mode, materialIndex + 1, MATERIAL_PALETTE[materialIndex], fps);
    } else {
        title = format("mined — %s (V) — click to capture mouse — FPS %.0f", mode, fps);
    }
    SDL_SetWindowTitle(window, title.toStringz);
}

// True when SDL relative mouse mode is unavailable (e.g. X11 without
// XInput2) and we emulate it by warping the cursor back to the window
// center every frame.
bool warpFallback = false;

// Action recording (--record): open sink for event/frame lines.
File recordFile;
bool recording = false;

void recordEvent(string line) {
    if (recording) {
        recordFile.writeln(line);
    }
}

ushort packInput(const ref InputState s) {
    ushort b = 0;
    if (s.fwd) b |= 1;
    if (s.back) b |= 2;
    if (s.left) b |= 4;
    if (s.right) b |= 8;
    if (s.up) b |= 16;
    if (s.down) b |= 32;
    if (s.yawLeft) b |= 64;
    if (s.yawRight) b |= 128;
    if (s.pitchUp) b |= 256;
    if (s.pitchDown) b |= 512;
    return b;
}

InputState unpackInput(uint b) {
    InputState s;
    s.fwd = (b & 1) != 0;
    s.back = (b & 2) != 0;
    s.left = (b & 4) != 0;
    s.right = (b & 8) != 0;
    s.up = (b & 16) != 0;
    s.down = (b & 32) != 0;
    s.yawLeft = (b & 64) != 0;
    s.yawRight = (b & 128) != 0;
    s.pitchUp = (b & 256) != 0;
    s.pitchDown = (b & 512) != 0;
    return s;
}

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
    ref bool noClip,
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
        } else if (ev.key.scancode == SDL_SCANCODE_V && !ev.key.repeat) {
            noClip = !noClip;
            writefln("mode: %s", noClip ? "fly" : "walk");
            recordEvent("v");
            titleDirty = true;
        } else if (ev.key.scancode >= SDL_SCANCODE_1 && ev.key.scancode <= SDL_SCANCODE_9) {
            int idx = cast(int)(ev.key.scancode - SDL_SCANCODE_1);
            if (idx < MATERIAL_PALETTE.length && idx != materialIndex) {
                materialIndex = idx;
                writefln("material: [%d] %s", idx + 1, MATERIAL_PALETTE[idx]);
                recordEvent(format("m %d", idx));
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
            recordEvent("b");
        } else if (ev.button.button == SDL_BUTTON_RIGHT) {
            renderer.placeBlock(cast(ushort) MATERIAL_PALETTE[materialIndex]);
            recordEvent("p");
        }
    }
}

struct CameraInput {
    float yawRate = 0;
    float pitchRate = 0;
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
        case SDL_SCANCODE_SPACE: input.up = held; break;
        case SDL_SCANCODE_LSHIFT: input.down = held; break;
        case SDL_SCANCODE_LEFT: input.yawLeft = held; break;
        case SDL_SCANCODE_RIGHT: input.yawRight = held; break;
        case SDL_SCANCODE_UP: input.pitchUp = held; break;
        case SDL_SCANCODE_DOWN: input.pitchDown = held; break;
        default: break;
    }
}
