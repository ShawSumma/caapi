import core.stdc.math : acoshf, tanhf;
import core.stdc.stdio : FILE, fclose, fflush, fopen, fprintf;
import core.stdc.stdio : printf, snprintf, sscanf, stdout;
import core.stdc.stdlib : system;
import bindings.sdl3;
import client.config : ClientConfig;
import client.graphics;
import client.local_character_controller : LocalCharacterController;
import client.script;
import common.array : Array;
import common.text : FileText, ParsedFloat, ParsedInt;
import common.text : collectLines, cstrEq, cstrStartsWith, parseFloat;
import common.text : parseInt, readWholeFile;
import common.character_controller : runCharacterStep, getRelativeUp;
import common.character_controller.vector_bounds : dot3;
import common.math : MIsometry, MPoint;
import common.proto : CharacterInput, Position;
import common.sim_config : SimConfig, SimConfigRaw;
import common.world;
import worldcheck : dumpWorld, benchNearby, benchGen, benchDrive;

enum ulong WINDOW_VULKAN = 0x0000000010000000;
enum ulong WINDOW_RESIZABLE = 0x0000000000000020;
enum ulong WINDOW_HIDDEN = 0x0000000000000008;

enum uint PRODUCER_DIFFUSION = 1;
enum uint PRODUCER_CYCLIC = 2;

// Held movement keys. One bit per key so opposite keys do not cancel each
// other's release, and so the whole set clears, records and replays as a
// single value.
enum ushort HELD_FWD = 1;
enum ushort HELD_BACK = 2;
enum ushort HELD_LEFT = 4;
enum ushort HELD_RIGHT = 8;
enum ushort HELD_UP = 16;
enum ushort HELD_DOWN = 32;
enum ushort HELD_YAW_LEFT = 64;
enum ushort HELD_YAW_RIGHT = 128;
enum ushort HELD_PITCH_UP = 256;
enum ushort HELD_PITCH_DOWN = 512;

static immutable Material[9] MATERIAL_PALETTE = [
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

static immutable string[9] MATERIAL_NAMES = [
    "WoodPlanks",
    "Wood",
    "Leaves",
    "GreyBrick",
    "WhiteBrick",
    "Sandstone",
    "Marble",
    "Granite",
    "Basalt",
];

// betterC has no druntime entry point, so this is the real C main. The body
// lives in run() so its many early exits stay plain `return;`.
extern(C) int main(int argc, char** argv) {
    run(argc, argv);
    return 0;
}

void run(int argc, char** argv) {
    foreach (i; 0 .. argc) {
        if (cstrEq(argv[i], "--dump-world")) {
            dumpWorld(argFloat(argc, argv, i + 1, 3.0f), 12);
            return;
        }
        if (cstrEq(argv[i], "--bench-gen")) {
            benchGen(argFloat(argc, argv, i + 1, 2.5f), 12);
            return;
        }
        if (cstrEq(argv[i], "--bench-drive")) {
            benchDrive(argFloat(argc, argv, i + 1, 2.5f), 12);
            return;
        }
        if (cstrEq(argv[i], "--bench-nearby")) {
            benchNearby(
                argFloat(argc, argv, i + 1, 4.5f),
                argInt(argc, argv, i + 2, 50),
                12,
            );
            return;
        }
    }

    printf("mined - hyperbolic voxel engine\n");

    const(char)* scriptPath = null;
    const(char)* configPath = "mined.cfg";
    const(char)* recordPath = null;
    const(char)* replayPath = null;
    const(char)* shotPath = null;
    bool shotHiddenWindow = false;
    int shotFrame = 120;
    bool headlessMode = false;
    bool flatWorldgen = false;
    bool tripMode = false;
    uint fieldMode = 1;
    uint producer = PRODUCER_DIFFUSION;
    // Negative means "leave the renderer's default alone".
    float renderRadius = -1.0f;
    bool noVsync = false;

    foreach (i; 0 .. argc) {
        char* a = argv[i];
        if (cstrEq(a, "--shot") && i + 1 < argc) {
            shotPath = argv[i + 1];
        }
        if (cstrEq(a, "--shot-window") && i + 1 < argc) {
            shotPath = argv[i + 1];
            shotHiddenWindow = true;
        }
        if (cstrEq(a, "--shot-frame") && i + 1 < argc) {
            shotFrame = argInt(argc, argv, i + 1, shotFrame);
        }
        if (cstrEq(a, "--script") && i + 1 < argc) {
            scriptPath = argv[i + 1];
        }
        if (cstrEq(a, "--config") && i + 1 < argc) {
            configPath = argv[i + 1];
        }
        if (cstrEq(a, "--record") && i + 1 < argc) {
            recordPath = argv[i + 1];
        }
        if (cstrEq(a, "--replay") && i + 1 < argc) {
            replayPath = argv[i + 1];
        }
        if (cstrEq(a, "--radius") && i + 1 < argc) {
            renderRadius = argFloat(argc, argv, i + 1, renderRadius);
        }
        if (cstrEq(a, "--novsync")) {
            noVsync = true;
        }
        if (cstrEq(a, "--headless")) {
            headlessMode = true;
        }
        if (cstrEq(a, "--flat")) {
            flatWorldgen = true;
            printf("flat worldgen enabled\n");
        }
        if (cstrEq(a, "--trip")) {
            tripMode = true;
            if (i + 1 < argc && !cstrStartsWith(argv[i + 1], "-")) {
                const(char)* which = argv[i + 1];
                if (cstrEq(which, "none")) {
                    tripMode = false;
                } else if (cstrEq(which, "rps") || cstrEq(which, "cyclic")) {
                    producer = PRODUCER_CYCLIC;
                } else if (cstrEq(which, "diffusion")) {
                    producer = PRODUCER_DIFFUSION;
                } else {
                    printf("unknown --trip option: %s\n", which);
                    return;
                }
            }
            printf("trip: %s\n", producerName(tripMode, producer));
        }
        if (cstrEq(a, "--field") && i + 1 < argc) {
            tripMode = true;
            fieldMode = cast(uint) argInt(argc, argv, i + 1, cast(int) fieldMode);
        }
    }

    ClientConfig cfg = ClientConfig.load(configPath);
    foreach (i; 0 .. argc) {
        if (cstrEq(argv[i], "--sensitivity") && i + 1 < argc) {
            cfg.mouseSensitivity = argFloat(argc, argv, i + 1, cfg.mouseSensitivity);
        }
        if (cstrEq(argv[i], "--invert-y")) {
            cfg.invertY = true;
        }
    }

    Session session;
    scope(exit) {
        session.release();
    }
    bool wantRecord = recordPath !is null;
    bool haveReplay = replayPath !is null;
    bool haveScript = scriptPath !is null;
    if (wantRecord && !haveReplay && !haveScript) {
        session.recordFile = fopen(recordPath, "w");
        if (session.recordFile is null) {
            printf("cannot open record file: %s\n", recordPath);
            return;
        }
        fprintf(session.recordFile, "# mined-actions v1\n");
        session.recording = true;
        printf("recording actions to %s\n", recordPath);
    }

    FileText replayText;
    Array!(char*) replayLines;
    // Qualified because the SDL3 C header also declares a size_t.
    object.size_t replayCursor = 0;
    bool replayMode = false;
    scope(exit) {
        replayLines.release();
        replayText.release();
    }
    if (haveReplay) {
        replayText = readWholeFile(replayPath);
        if (replayText.data is null) {
            printf("replay not found: %s\n", replayPath);
            return;
        }
        collectLines(replayText, replayLines, true);
        replayMode = true;
        printf(
            "replaying %zu action lines from %s\n",
            replayLines.length(),
            replayPath,
        );
    }

    Script script;
    FileText scriptText;
    scope(exit) {
        scriptText.release();
    }
    if (haveScript) {
        scriptText = readWholeFile(scriptPath);
        if (scriptText.data is null) {
            printf("script not found: %s\n", scriptPath);
            return;
        }
        script = Script.parse(scriptText);
        printf(
            "Loaded script %s (%zu events)\n",
            scriptPath,
            script.events.length(),
        );
    }
    scope(exit) {
        script.release();
    }

    if (shotPath !is null && !shotHiddenWindow) {
        import core.sys.posix.stdlib : setenv;
        setenv("SDL_VIDEO_DRIVER", "offscreen", 1);
    }

    if (!SDL_Init(SDL_INIT_VIDEO)) {
        const(char)* err = SDL_GetError();
        if (err !is null) {
            printf("SDL init failed: %s\n", err);
        }
        return;
    }
    scope(exit) {
        SDL_Quit();
    }

    ulong windowFlags = WINDOW_VULKAN | WINDOW_RESIZABLE;
    if (shotHiddenWindow) {
        windowFlags = windowFlags | WINDOW_HIDDEN;
    }
    SDL_Window* window = SDL_CreateWindow("mined", 1280, 720, windowFlags);
    if (window is null) {
        printf("Window creation failed\n");
        return;
    }
    scope(exit) {
        SDL_DestroyWindow(window);
    }

    uint props = SDL_GetWindowProperties(window);
    ulong xWindowId = SDL_GetNumberProperty(props, "SDL.window.x11.window", 0);

    Renderer renderer;
    renderer.swapState.offscreen = shotPath !is null && !shotHiddenWindow;
    renderer.swapState.preferImmediate = noVsync;
    if (!renderer.init(cast(void*) window)) {
        printf("Renderer initialization failed\n");
        return;
    }
    scope(exit) {
        renderer.cleanup();
    }
    SimConfig simCfg = SimConfig.fromRaw();
    // Config reach is in voxel-meters; the caster wants the tanh of the
    // absolute hyperbolic distance.
    renderer.reach = tanhf(cfg.reach * simCfg.metersToAbsolute);
    renderer.headless = headlessMode;
    if (renderRadius > 0) {
        renderer.renderRadius = renderRadius;
        renderer.viewRadius = renderRadius + 0.5f;
        printf("render radius: %.2f\n", cast(double) renderRadius);
    }
    renderer.worldgenDriver.flatWorldgen = flatWorldgen;
    renderer.trip = tripMode;
    renderer.fieldMode = fieldMode;
    renderer.producer = producer;
    LocalCharacterController character = LocalCharacterController.create();
    character.position = renderer.camPos;
    character.up = getRelativeUp(&renderer.graph, &character.position);
    character.eyeOffset = simCfg.character.eyeOffset;
    character.alignToGravity();
    float[3] velocity = [0, 0, 0];
    bool onGround = false;

    bool running = true;
    SDL_Event ev;
    CameraInput cam;
    float simTime = 0;
    float lastFps = 0;
    ulong lastTicks = SDL_GetTicks();
    ulong framesSinceReport = 0;
    ulong lastFpsReport = lastTicks;

    updateWindowTitle(
        window,
        session.mouseCaptured,
        session.materialIndex,
        session.flyMode,
        session.noClip,
        lastFps,
    );

    float frameMaxMs = 0;
    float traveled = 0;
    Position odoPrev = character.position;

    // Vertical camera kinematics monitor: worst |acceleration| per window.
    Position camPrev = renderer.camPos;
    float prevVertVel = 0;
    bool haveVertVel = false;
    float vaccMax = 0;

    bool scripted = script.events.length() > 0;

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

        if (scripted) {
            dt = 0.016f;
        }

        session.mouseDx = 0;
        session.mouseDy = 0;
        session.titleDirty = false;

        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_EVENT_QUIT) {
                running = false;
            }

            if (replayMode) {
                if (ev.type == SDL_EVENT_KEY_DOWN && ev.key.key == SDLK_ESCAPE) {
                    running = false;
                }
            } else if (!scripted) {
                session.handleEvent(ev, window, renderer, xWindowId);
            }
        }

        float replayYaw = 0;
        float replayPitch = 0;
        if (replayMode) {
            bool gotFrame = false;
            while (replayCursor < replayLines.length()) {
                char* line = replayLines[replayCursor];
                replayCursor = replayCursor + 1;
                if (cstrStartsWith(line, "f ")) {
                    float lineDt = 0;
                    float lineYaw = 0;
                    float linePitch = 0;
                    uint lineHeld = 0;
                    int fields = sscanf(
                        line,
                        "f %f %f %f %x",
                        &lineDt,
                        &lineYaw,
                        &linePitch,
                        &lineHeld,
                    );
                    if (fields == 4) {
                        dt = lineDt;
                        replayYaw = lineYaw;
                        replayPitch = linePitch;
                        session.held = cast(ushort) lineHeld;
                        gotFrame = true;
                    }
                    break;
                } else if (cstrEq(line, "b")) {
                    renderer.breakBlock();
                } else if (cstrEq(line, "p")) {
                    renderer.placeBlock(session.selectedMaterial());
                } else if (cstrStartsWith(line, "m ")) {
                    int idx = 0;
                    if (sscanf(line, "m %d", &idx) == 1) {
                        session.materialIndex = idx;
                    }
                } else if (cstrEq(line, "v")) {
                    session.flyMode = !session.flyMode;
                } else if (cstrEq(line, "n")) {
                    session.noClip = !session.noClip;
                } else if (cstrEq(line, "c")) {
                    renderer.cycleChannelMap();
                }
            }
            if (!gotFrame) {
                printf("replay finished\n");
                running = false;
            }
        }

        if (scripted) {
            if (!script.tick(simTime, xWindowId)) {
                running = false;
            }
            if (script.resizePending) {
                SDL_SetWindowSize(window, script.resizeWidth, script.resizeHeight);
                script.resizePending = false;
            }
            cam.fwd = script.fwd;
            cam.strafe = script.strafe;
            cam.vert = script.vert;
            cam.yawRate = script.yawRate;
            cam.pitchRate = script.pitchRate;
        } else {
            float yawIn = axis(session.held, HELD_YAW_RIGHT)
                - axis(session.held, HELD_YAW_LEFT);
            float pitchIn = axis(session.held, HELD_PITCH_DOWN)
                - axis(session.held, HELD_PITCH_UP);
            cam.yawRate = yawIn * cfg.turnSpeed;
            cam.pitchRate = pitchIn * cfg.turnSpeed;
        }

        if (!running) {
            break;
        }

        float invY = 1.0f;
        if (cfg.invertY) {
            invY = -1.0f;
        }
        float yaw = cam.yawRate * dt + session.mouseDx * cfg.mouseSensitivity;
        float pitch = cam.pitchRate * dt + session.mouseDy * cfg.mouseSensitivity * invY;
        if (replayMode) {
            yaw = replayYaw;
            pitch = replayPitch;
        }
        if (session.recording) {
            // One line per frame: dt, final look deltas (sensitivity and
            // invert baked in), and the held-key bits. Event lines (b/p/m/v)
            // are written as they happen and precede their frame line.
            fprintf(
                session.recordFile,
                "f %.6f %.6f %.6f %x\n",
                cast(double) dt,
                cast(double) yaw,
                cast(double) pitch,
                cast(uint) session.held,
            );
        }

        if (scripted) {
            // Script mode keeps direct camera control for reproducibility.
            renderer.rotateCamera(yaw, pitch, 0);
            renderer.moveCamera(cam.strafe * dt, cam.vert * dt, cam.fwd * dt);
        } else {
            // The quaternion axes are mirrored relative to the renderer's
            // rotation matrices, hence the negated deltas.
            character.lookLevel(-yaw, -pitch);

            float mx = axis(session.held, HELD_RIGHT) - axis(session.held, HELD_LEFT);
            float my = axis(session.held, HELD_UP) - axis(session.held, HELD_DOWN);
            float mz = axis(session.held, HELD_BACK) - axis(session.held, HELD_FWD);

            Position beforeStep = character.position;
            bool wasGround = onGround;

            CharacterInput cin;
            cin.noClip = session.noClip;
            cin.fly = session.flyMode;
            if (session.noClip) {
                // Debug free-flight: fully view-relative.
                cin.movement = character.viewOrientation().rotate([mx, my, mz]);
            } else if (session.flyMode) {
                // Creative flight: forward/strafe in the yaw plane, and
                // Space/Shift along actual world up/down.
                cin.movement = character.horizontalOrientation().rotate([mx, my, mz]);
            } else {
                cin.movement = character.horizontalOrientation().rotate([mx, 0, mz]);
                cin.jump = (session.held & HELD_UP) != 0;
            }
            runCharacterStep(
                simCfg,
                renderer.graph,
                character.position,
                velocity,
                onGround,
                cin,
                dt,
            );

            // Holonomy mitigation: "down" is re-derived from the world at the
            // new position every step, the view is transported to follow it,
            // and any residual roll is aligned away — so carrying the frame
            // around a loop can't accumulate rotation.
            float[3] newUp = getRelativeUp(&renderer.graph, &character.position);

            // Smooth grounded vertical motion (stair steps, hop launches and
            // landings) out of the eye.
            float groundedRise = 0;
            if ((wasGround || onGround) && beforeStep.node == character.position.node) {
                MPoint!float moved = (beforeStep.local.inverse() * character.position.local)
                    * MPoint!float.origin();
                groundedRise = dot3(moved.vec.xyz(), newUp);
            }
            character.smoothEyeVertical(groundedRise, dt);

            character.updatePosition(character.position, newUp, true);
            // The yaw frame stays up-aligned by construction; this only
            // scrubs out accumulated float noise.
            character.alignToGravity();
            character.renormalizeOrientation();
            renderer.camPos = character.orientedPosition();

            // Vertical camera acceleration (what the eye feels).
            if (renderer.camPos.node == camPrev.node && dt > 1e-6f) {
                MPoint!float camMoved = (camPrev.local.inverse() * renderer.camPos.local)
                    * MPoint!float.origin();
                float vertVel = dot3(camMoved.vec.xyz(), newUp) / dt;
                if (haveVertVel) {
                    float vacc = (vertVel - prevVertVel) / dt;
                    if (vacc < 0) {
                        vacc = -vacc;
                    }
                    if (vacc > vaccMax) {
                        vaccMax = vacc;
                    }
                }
                prevVertVel = vertVel;
                haveVertVel = true;
            } else {
                haveVertVel = false;
            }
            camPrev = renderer.camPos;

            // Odometer: real distance covered, robust across node changes.
            if (character.position.node == odoPrev.node) {
                MPoint!float a = odoPrev.local * MPoint!float.origin();
                MPoint!float b = character.position.local * MPoint!float.origin();
                float m = -a.mip(b.vec);
                if (m > 1.0f) {
                    traveled = traveled + acoshf(m);
                }
            }
            odoPrev = character.position;
        }
        renderer.render(dt);
        simTime = simTime + dt;

        if (shotPath !is null) {
            if (renderer.captureDone) {
                running = false;
            } else {
                shotFrame = shotFrame - 1;
                if (shotFrame <= 0) {
                    renderer.capturePath = shotPath;
                }
            }
        }

        framesSinceReport = framesSinceReport + 1;
        bool secondElapsed = nowTicks - lastFpsReport >= 1000;
        bool replayBatchDone = replayMode && framesSinceReport >= 60;
        if (secondElapsed || replayBatchDone) {
            lastFps = framesSinceReport * 1000.0f / (nowTicks - lastFpsReport);
            printf(
                "FPS=%.1f frame max=%.0fms | mode=%s ground=%d",
                cast(double) lastFps,
                cast(double) frameMaxMs,
                modeName(session.flyMode, session.noClip),
                cast(int) onGround,
            );
            printf(
                " vel=[%.3f %.3f %.3f] traveled=%.3f vacc=%.2f\n",
                cast(double) velocity[0],
                cast(double) velocity[1],
                cast(double) velocity[2],
                cast(double) traveled,
                cast(double) vaccMax,
            );
            vaccMax = 0;
            fflush(stdout);
            framesSinceReport = 0;
            frameMaxMs = 0;
            lastFpsReport = nowTicks;
            session.titleDirty = true;
        }

        if (session.titleDirty) {
            updateWindowTitle(
                window,
                session.mouseCaptured,
                session.materialIndex,
                session.flyMode,
                session.noClip,
                lastFps,
            );
        }
    }

    if (session.recording) {
        session.recording = false;
        fclose(session.recordFile);
        session.recordFile = null;
        printf("recording saved to %s\n", recordPath);
    }
    printf("session: traveled=%.3f\n", cast(double) traveled);
}

float argFloat(int argc, char** argv, int index, float fallback) {
    if (index >= argc) {
        return fallback;
    }
    ParsedFloat parsed = parseFloat(argv[index]);
    if (!parsed.ok) {
        return fallback;
    }
    return parsed.value;
}

int argInt(int argc, char** argv, int index, int fallback) {
    if (index >= argc) {
        return fallback;
    }
    ParsedInt parsed = parseInt(argv[index], 10);
    if (!parsed.ok) {
        return fallback;
    }
    return cast(int) parsed.value;
}

const(char)* producerName(bool tripMode, uint producer) {
    if (!tripMode) {
        return "none";
    }
    if (producer == PRODUCER_CYCLIC) {
        return "rps";
    }
    return "diffusion";
}

float axis(ushort held, ushort bit) {
    if ((held & bit) != 0) {
        return 1.0f;
    }
    return 0.0f;
}

const(char)* modeName(bool flyMode, bool noClip) {
    if (noClip) {
        return "noclip";
    }
    if (flyMode) {
        return "fly";
    }
    return "walk";
}

void updateWindowTitle(
    SDL_Window* window,
    bool mouseCaptured,
    int materialIndex,
    bool flyMode,
    bool noClip,
    float fps,
) {
    char[256] title;
    if (mouseCaptured) {
        snprintf(
            title.ptr,
            title.length,
            "mined - %s (V) - [%d] %s - Esc to release mouse - FPS %.0f",
            modeName(flyMode, noClip),
            materialIndex + 1,
            MATERIAL_NAMES[materialIndex].ptr,
            cast(double) fps,
        );
    } else {
        snprintf(
            title.ptr,
            title.length,
            "mined - %s (V) - click to capture mouse - FPS %.0f",
            modeName(flyMode, noClip),
            cast(double) fps,
        );
    }
    SDL_SetWindowTitle(window, title.ptr);
}

// Per-run interaction state threaded through the input handlers.
struct Session {
    // True when SDL relative mouse mode is unavailable, as on X11 without
    // XInput2. The cursor is then warped back to the window centre every
    // frame to emulate it.
    bool warpFallback;
    // Action recording (--record): open sink for event/frame lines.
    FILE* recordFile;
    bool recording;

    // Interaction state owned by the input handling below. These were loose
    // locals in main that every handler wrote back through its own ref
    // parameter, which is what made those signatures a wall of outputs.
    bool mouseCaptured;
    ushort held;
    int materialIndex;
    bool flyMode = true;
    bool noClip;
    bool titleDirty;
    int shotIndex;
    float mouseDx = 0;
    float mouseDy = 0;

    void release() {
        if (recordFile !is null) {
            fclose(recordFile);
            recordFile = null;
        }
        recording = false;
    }

    ushort selectedMaterial() const {
        return cast(ushort) MATERIAL_PALETTE[materialIndex];
    }

    void recordEvent(const(char)* line) {
        if (recording) {
            fprintf(recordFile, "%s\n", line);
        }
    }

    void setMouseCaptured(SDL_Window* window, bool captured) {
        if (mouseCaptured == captured) {
            return;
        }
        if (captured) {
            if (!SDL_SetWindowRelativeMouseMode(window, true)) {
                const(char)* err = SDL_GetError();
                if (err !is null && !warpFallback) {
                    printf(
                        "relative mouse mode unavailable (%s), using warp fallback\n",
                        err,
                    );
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
            held = 0;
        }
    }

    void handleEvent(
        ref SDL_Event ev,
        SDL_Window* window,
        ref Renderer renderer,
        ulong xWindowId,
    ) {
        if (ev.type == SDL_EVENT_KEY_DOWN) {
            handleKeyDown(ev, window, renderer, xWindowId);
        }

        if (ev.type == SDL_EVENT_KEY_UP) {
            applyMovementKey(ev.key.scancode, false);
        }

        if (ev.type == SDL_EVENT_WINDOW_FOCUS_LOST) {
            // Key-up events stop arriving once focus is gone; drop all held
            // keys and release the mouse so the player is not stuck moving.
            held = 0;
            setMouseCaptured(window, false);
            titleDirty = true;
        }

        if (ev.type == SDL_EVENT_MOUSE_MOTION && mouseCaptured) {
            accumulateMouseMotion(ev, window);
        }

        if (ev.type == SDL_EVENT_MOUSE_BUTTON_DOWN) {
            if (!mouseCaptured) {
                setMouseCaptured(window, true);
                titleDirty = true;
            } else if (ev.button.button == SDL_BUTTON_LEFT) {
                renderer.breakBlock();
                recordEvent("b");
            } else if (ev.button.button == SDL_BUTTON_RIGHT) {
                renderer.placeBlock(selectedMaterial());
                recordEvent("p");
            }
        }
    }

    void handleKeyDown(
        ref SDL_Event ev,
        SDL_Window* window,
        ref Renderer renderer,
        ulong xWindowId,
    ) {
        if (ev.key.key == SDLK_ESCAPE) {
            if (mouseCaptured) {
                setMouseCaptured(window, false);
                titleDirty = true;
            }
            return;
        }

        if (ev.key.key == SDLK_F12) {
            char[64] path;
            snprintf(path.ptr, path.length, "mined_shot_%03d.png", shotIndex);
            shotIndex = shotIndex + 1;
            // Run in the background so capture doesn't stall the frame loop.
            char[160] cmd;
            snprintf(
                cmd.ptr,
                cmd.length,
                "import -window 0x%llx %s &",
                xWindowId,
                path.ptr,
            );
            printf("F12 screenshot -> %s\n", path.ptr);
            system(cmd.ptr);
            return;
        }

        if (ev.key.scancode == SDL_SCANCODE_V && !ev.key.repeat) {
            flyMode = !flyMode;
            printf("mode: %s\n", modeName(flyMode, noClip));
            recordEvent("v");
            titleDirty = true;
            return;
        }

        if (ev.key.scancode == SDL_SCANCODE_N && !ev.key.repeat) {
            noClip = !noClip;
            printf("mode: %s\n", modeName(flyMode, noClip));
            recordEvent("n");
            titleDirty = true;
            return;
        }

        if (ev.key.scancode == SDL_SCANCODE_C && !ev.key.repeat) {
            renderer.cycleChannelMap();
            printf("channel map: %s\n", renderer.channelMapName());
            recordEvent("c");
            return;
        }

        if (ev.key.scancode >= SDL_SCANCODE_1 && ev.key.scancode <= SDL_SCANCODE_9) {
            int idx = cast(int)(ev.key.scancode - SDL_SCANCODE_1);
            if (idx < MATERIAL_PALETTE.length && idx != materialIndex) {
                materialIndex = idx;
                printf("material: [%d] %s\n", idx + 1, MATERIAL_NAMES[idx].ptr);
                char[16] line;
                snprintf(line.ptr, line.length, "m %d", idx);
                recordEvent(line.ptr);
                titleDirty = true;
            }
            return;
        }

        applyMovementKey(ev.key.scancode, true);
    }

    void applyMovementKey(uint scancode, bool down) {
        ushort bit = movementKeyBit(scancode);
        if (bit == 0) {
            return;
        }
        if (down) {
            held = cast(ushort)(held | bit);
        } else {
            held = cast(ushort)(held & ~bit);
        }
    }

    void accumulateMouseMotion(ref SDL_Event ev, SDL_Window* window) {
        if (!warpFallback) {
            mouseDx = mouseDx + ev.motion.xrel;
            mouseDy = mouseDy + ev.motion.yrel;
            return;
        }

        // Deltas are measured against the window centre and the cursor is
        // warped straight back, so the warp's own motion event lands at the
        // centre and contributes zero. No events need skipping.
        int w = 0;
        int h = 0;
        SDL_GetWindowSize(window, &w, &h);
        float cx = cast(float)(w / 2);
        float cy = cast(float)(h / 2);
        mouseDx = mouseDx + ev.motion.x - cx;
        mouseDy = mouseDy + ev.motion.y - cy;
        if (ev.motion.x != cx || ev.motion.y != cy) {
            SDL_WarpMouseInWindow(window, cx, cy);
        }
    }
}

void warpToCenter(SDL_Window* window) {
    int w = 0;
    int h = 0;
    SDL_GetWindowSize(window, &w, &h);
    SDL_WarpMouseInWindow(window, cast(float)(w / 2), cast(float)(h / 2));
}

struct CameraInput {
    float yawRate = 0;
    float pitchRate = 0;
    float fwd = 0;
    float strafe = 0;
    float vert = 0;
}

// Movement uses scancodes (physical key positions) so WASD stays WASD on
// non-QWERTY layouts. Returns 0 for keys that are not movement.
ushort movementKeyBit(uint scancode) {
    switch (scancode) {
        case SDL_SCANCODE_W: {
            return HELD_FWD;
        }
        case SDL_SCANCODE_S: {
            return HELD_BACK;
        }
        case SDL_SCANCODE_A: {
            return HELD_LEFT;
        }
        case SDL_SCANCODE_D: {
            return HELD_RIGHT;
        }
        case SDL_SCANCODE_SPACE: {
            return HELD_UP;
        }
        case SDL_SCANCODE_LSHIFT: {
            return HELD_DOWN;
        }
        case SDL_SCANCODE_LEFT: {
            return HELD_YAW_LEFT;
        }
        case SDL_SCANCODE_RIGHT: {
            return HELD_YAW_RIGHT;
        }
        case SDL_SCANCODE_UP: {
            return HELD_PITCH_UP;
        }
        case SDL_SCANCODE_DOWN: {
            return HELD_PITCH_DOWN;
        }
        default: {
            return 0;
        }
    }
}
