import std.stdio;
import std.format : format;
import std.string : toStringz;
import core.stdc.string : strlen;
import core.stdc.stdlib : system;
import bindings.sdl3;
import client.graphics;
import client.script;
import common.world;

enum : ulong {
    WINDOW_VULKAN    = 0x0000000010000000,
    WINDOW_RESIZABLE = 0x0000000000000020,
}

void main(string[] args) {
    writeln("mined - hyperbolic voxel engine");

    string scriptPath;
    foreach (i, a; args) {
        if (a == "--script" && i + 1 < args.length) {
            scriptPath = args[i + 1];
        }
    }

    Script script;
    if (scriptPath.length > 0) {
        import std.file : exists, readText;
        if (!exists(scriptPath)) {
            writefln("script not found: %s", scriptPath);
            return;
        }
        script = Script.parse(readText(scriptPath));
        writefln("Loaded script %s (%d events)", scriptPath, script.events.length);
    }

    if (!SDL_Init(SDL_INIT_VIDEO)) {
        auto err = SDL_GetError();
        if (err !is null) {
            writefln("SDL init failed: %s", err[0 .. strlen(err)]);
        }
        return;
    }
    scope(exit) {
        SDL_Quit();
    }

    auto window = SDL_CreateWindow("mined", 1280, 720, WINDOW_VULKAN | WINDOW_RESIZABLE);
    if (window is null) {
        writeln("Window creation failed");
        return;
    }
    scope(exit) {
        SDL_DestroyWindow(window);
    }

    auto props = SDL_GetWindowProperties(window);
    ulong xWindowId = SDL_GetNumberProperty(props, "SDL.window.x11.window", 0);

    Renderer renderer;
    if (!renderer.init(cast(void*) window)) {
        writeln("Renderer initialization failed");
        return;
    }
    scope(exit) {
        renderer.cleanup();
    }

    bool running = true;
    bool mouseCaptured = false;
    bool skipNextMotion = false;
    SDL_Event ev;
    CameraInput cam;
    int shotIndex = 0;
    float simTime = 0;
    float mouseDx = 0;
    float mouseDy = 0;
    ulong lastTicks = SDL_GetTicks();
    ulong framesSinceReport = 0;
    ulong lastFpsReport = lastTicks;

    while (running) {
        auto nowTicks = SDL_GetTicks();
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

        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_EVENT_QUIT) {
                running = false;
            }

            if (script.events.length == 0) {
                processInteractiveInput(
                    ev, window, cam, renderer, mouseCaptured,
                    skipNextMotion, mouseDx, mouseDy,
                    running, xWindowId, shotIndex);
            }
        }

        if (mouseCaptured) {
            int w = 0;
            int h = 0;
            SDL_GetWindowSize(window, &w, &h);
            SDL_WarpMouseInWindow(window, cast(float)(w / 2), cast(float)(h / 2));
            skipNextMotion = true;
        }

        if (script.events.length > 0) {
            script.tick(simTime, xWindowId, running);
            cam.fwd = script.fwd;
            cam.strafe = script.strafe;
            cam.vert = script.vert;
            cam.yawRate = script.yawRate;
            cam.pitchRate = script.pitchRate;
        }

        if (!running) {
            break;
        }

        enum float MOUSE_SENS = 0.003f;
        float yaw = cam.yawRate * dt + mouseDx * MOUSE_SENS;
        float pitch = cam.pitchRate * dt + mouseDy * MOUSE_SENS;
        float roll = cam.rollRate * dt;
        renderer.rotateCamera(yaw, pitch, roll);
        renderer.moveCamera(cam.strafe * dt, cam.vert * dt, cam.fwd * dt);
        renderer.render(dt);
        simTime += dt;

        framesSinceReport++;
        if (nowTicks - lastFpsReport >= 5000) {
            float fps = framesSinceReport * 1000.0f / (nowTicks - lastFpsReport);
            writefln("FPS=%.0f", fps);
            stdout.flush();
            framesSinceReport = 0;
            lastFpsReport = nowTicks;
        }
    }
}

private void processInteractiveInput(
    ref SDL_Event ev,
    SDL_Window* window,
    ref CameraInput cam,
    ref Renderer renderer,
    ref bool mouseCaptured,
    ref bool skipNextMotion,
    ref float mouseDx,
    ref float mouseDy,
    ref bool running,
    ulong xWindowId,
    ref int shotIndex,
) {
    if (ev.type == SDL_EVENT_KEY_DOWN) {
        if (ev.key.key == SDLK_ESCAPE) {
            if (mouseCaptured) {
                SDL_SetWindowMouseGrab(window, false);
                SDL_ShowCursor();
                mouseCaptured = false;
            } else {
                running = false;
            }
        } else if (ev.key.key == SDLK_F12) {
            auto path = format("/tmp/mined_shot_%03d.png", shotIndex++);
            auto cmd = format("import -window 0x%x %s", xWindowId, path);
            writefln("F12 screenshot -> %s", path);
            system(cmd.toStringz);
        } else {
            handleKeyDown(ev.key.key, cam);
        }
    }

    if (ev.type == SDL_EVENT_KEY_UP) {
        handleKeyUp(ev.key.key, cam);
    }

    if (ev.type == SDL_EVENT_MOUSE_MOTION && mouseCaptured) {
        if (skipNextMotion) {
            skipNextMotion = false;
        } else {
            mouseDx += ev.motion.xrel;
            mouseDy += ev.motion.yrel;
        }
    }

    if (ev.type == SDL_EVENT_MOUSE_BUTTON_DOWN) {
        if (!mouseCaptured) {
            SDL_SetWindowMouseGrab(window, true);
            SDL_HideCursor();
            int w = 0;
            int h = 0;
            SDL_GetWindowSize(window, &w, &h);
            SDL_WarpMouseInWindow(window, cast(float)(w / 2), cast(float)(h / 2));
            skipNextMotion = true;
            mouseCaptured = true;
        } else if (ev.button.button == SDL_BUTTON_LEFT) {
            renderer.breakBlock();
        } else if (ev.button.button == SDL_BUTTON_RIGHT) {
            renderer.placeBlock(cast(ushort) Material.WoodPlanks);
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

private void handleKeyDown(uint key, ref CameraInput cam) {
    enum float TURN = 1.5f;
    enum float MOVE = 1.0f;
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
    if (key == SDLK_Q) {
        cam.rollRate = TURN;
    }
    if (key == SDLK_E) {
        cam.rollRate = -TURN;
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
    if (key == SDLK_Q || key == SDLK_E) {
        cam.rollRate = 0;
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
