import std.stdio;
import core.stdc.string : strlen;
import bindings.sdl3;
import client.graphics;
import client.sim;
import common.sim_config;
import common.proto;

enum : ulong {
    WINDOW_VULKAN    = 0x0000000010000000,
    WINDOW_RESIZABLE = 0x0000000000000020,
}

void main() {
    writeln("mined - hyperbolic voxel engine");

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
    writeln("Controls: arrow keys = look, WASD = unused (rotation only for now), Esc = quit");

    bool running = true;
    SDL_Event ev;
    CameraInput cam;
    while (running) {
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_EVENT_QUIT) {
                running = false;
            }
            if (ev.type == SDL_EVENT_KEY_DOWN) {
                handleKeyDown(ev.key.key, cam);
            }
            if (ev.type == SDL_EVENT_KEY_UP) {
                handleKeyUp(ev.key.key, cam);
            }
        }

        if (!running) {
            break;
        }
        float dt = 0.016f;
        cam.yaw   += cam.yawRate * dt;
        cam.pitch += cam.pitchRate * dt;
        if (cam.pitch >  1.5f) {
            cam.pitch = 1.5f;
        }
        if (cam.pitch < -1.5f) {
            cam.pitch = -1.5f;
        }
        sim.step++;
        renderer.setCamera(cam.yaw, cam.pitch);
        renderer.render(dt);
    }

    writeln("Exiting.");
}

struct CameraInput {
    float yaw = 0;
    float pitch = 0;
    float yawRate = 0;
    float pitchRate = 0;
}

private void handleKeyDown(uint key, ref CameraInput cam) {
    enum float TURN = 1.5f;
    if (key == SDLK_ESCAPE) {
        return; // handled by main loop
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
}

private void handleKeyUp(uint key, ref CameraInput cam) {
    if (key == SDLK_LEFT || key == SDLK_RIGHT) {
        cam.yawRate = 0;
    }
    if (key == SDLK_UP || key == SDLK_DOWN) {
        cam.pitchRate = 0;
    }
}
