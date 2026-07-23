import std.stdio;
import std.format : format;
import core.time : MonoTime;
import bindings.cocoa;
import client.graphics;
import client.script;
import common.world;

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

    void* window = minedCreateWindow(1280, 720, "mined");
    if (window is null) {
        writeln("Window creation failed");
        return;
    }
    scope(exit) {
        minedDestroyWindow(window);
    }

    void* metalLayer = minedGetMetalLayer(window);

    Renderer renderer;
    if (!renderer.init(metalLayer)) {
        writeln("Renderer initialization failed");
        return;
    }
    scope(exit) {
        renderer.cleanup();
    }

    bool running = true;
    bool mouseCaptured = false;
    MinedEvent ev;
    CameraInput cam;
    int shotIndex = 0;
    float simTime = 0;
    float mouseDx = 0;
    float mouseDy = 0;
    MonoTime startTime = MonoTime.currTime;
    ulong lastTicks = 0;
    ulong framesSinceReport = 0;
    ulong lastFpsReport = 0;

    while (running) {
        ulong nowTicks = cast(ulong) (MonoTime.currTime - startTime).total!"msecs";
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

        while (minedPollEvent(window, &ev) != 0) {
            if (script.events.length == 0) {
                processInteractiveInput(
                    ev, window, cam, renderer, mouseCaptured,
                    mouseDx, mouseDy, running, shotIndex);
            }
        }

        if (minedShouldClose(window) != 0) {
            running = false;
        }

        if (script.events.length > 0) {
            string shot;
            script.tick(simTime, running, shot);
            if (shot.length > 0) {
                renderer.requestScreenshot(shot);
            }
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
    ref MinedEvent ev,
    void* window,
    ref CameraInput cam,
    ref Renderer renderer,
    ref bool mouseCaptured,
    ref float mouseDx,
    ref float mouseDy,
    ref bool running,
    ref int shotIndex,
) {
    if (ev.type == MINED_EVENT_KEY_DOWN) {
        if (ev.keycode == KEY_ESCAPE) {
            if (mouseCaptured) {
                minedSetCapture(window, 0);
                mouseCaptured = false;
            } else {
                running = false;
            }
        } else if (ev.keycode == KEY_F12) {
            auto path = format("/tmp/mined_shot_%03d.png", shotIndex++);
            writefln("F12 screenshot -> %s", path);
            renderer.requestScreenshot(path);
        } else {
            handleKeyDown(ev.keycode, cam);
        }
    }

    if (ev.type == MINED_EVENT_KEY_UP) {
        handleKeyUp(ev.keycode, cam);
    }

    if (ev.type == MINED_EVENT_MOUSE_MOTION && mouseCaptured) {
        mouseDx += ev.dx;
        mouseDy += ev.dy;
    }

    if (ev.type == MINED_EVENT_MOUSE_BUTTON_DOWN) {
        if (!mouseCaptured) {
            minedSetCapture(window, 1);
            mouseCaptured = true;
        } else if (ev.button == MINED_BUTTON_LEFT) {
            renderer.breakBlock();
        } else if (ev.button == MINED_BUTTON_RIGHT) {
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
    if (key == KEY_LEFT) {
        cam.yawRate = -TURN;
    }
    if (key == KEY_RIGHT) {
        cam.yawRate = TURN;
    }
    if (key == KEY_UP) {
        cam.pitchRate = -TURN;
    }
    if (key == KEY_DOWN) {
        cam.pitchRate = TURN;
    }
    if (key == KEY_W) {
        cam.fwd = -MOVE;
    }
    if (key == KEY_S) {
        cam.fwd = MOVE;
    }
    if (key == KEY_A) {
        cam.strafe = -MOVE;
    }
    if (key == KEY_D) {
        cam.strafe = MOVE;
    }
    if (key == KEY_Q) {
        cam.rollRate = TURN;
    }
    if (key == KEY_E) {
        cam.rollRate = -TURN;
    }
    if (key == KEY_SPACE) {
        cam.vert = MOVE;
    }
    if (key == KEY_SHIFT) {
        cam.vert = -MOVE;
    }
}

private void handleKeyUp(uint key, ref CameraInput cam) {
    if (key == KEY_LEFT || key == KEY_RIGHT) {
        cam.yawRate = 0;
    }
    if (key == KEY_UP || key == KEY_DOWN) {
        cam.pitchRate = 0;
    }
    if (key == KEY_Q || key == KEY_E) {
        cam.rollRate = 0;
    }
    if (key == KEY_W || key == KEY_S) {
        cam.fwd = 0;
    }
    if (key == KEY_A || key == KEY_D) {
        cam.strafe = 0;
    }
    if (key == KEY_SPACE || key == KEY_SHIFT) {
        cam.vert = 0;
    }
}
