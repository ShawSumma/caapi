module main;

import std.stdio : writefln, stdout;
import client.glfw;
import client.window : Window;
import client.renderer : Renderer, CubeMesh;
import common.math : Matrix4, MVector, translation, rotation, inverseIsometry, hyperbolicDistance;
import common.graph : Cube, State;
import common.geometry : FACES;
import common.worldgen_thread : WorldgenThread;

enum float VIEW_RADIUS = 2.5f;
enum float WORLDGEN_RADIUS = 2.8f;

struct MeshCache {
    CubeMesh mesh;
    uint generation;
    bool present;
}

void main(string[] args) {
    bool autoDrive = false;
    foreach (a; args) {
        if (a == "drive") {
            autoDrive = true;
        }
    }

    Window* window = Window.open(1280, 800, "hyped - hyperbolic voxels");
    if (window is null) {
        writefln("window creation failed");
        return;
    }

    Renderer renderer;
    renderer.init(window.width, window.height);

    Matrix4 camera = translation([0.0f, 0.8f, 0.0f]) * rotation(1, 2, -1.5707963f);

    WorldgenThread* worldgen = WorldgenThread.create(WORLDGEN_RADIUS);
    worldgen.setCamera(camera);
    worldgen.start();

    MeshCache[Cube*] meshes;

    double last = glfwGetTime();
    double fpsTime = last;
    int frames = 0;

    while (!window.shouldClose()) {
        double now = glfwGetTime();
        float dt = cast(float)(now - last);
        last = now;

        window.poll();
        camera = applyInput(window, camera, dt, autoDrive);
        worldgen.setCamera(camera);

        MVector camPos = (camera * MVector.origin()).normalized();
        Matrix4 camInverse = inverseIsometry(camera);
        Cube* anchor = worldgen.currentCube();

        int drawn = drawWorld(renderer, anchor, camPos, camInverse, meshes);
        window.swap();

        frames++;
        if (now - fpsTime >= 1.0) {
            writefln(
                "FPS=%.0f  drawn=%d  cached=%d",
                frames / (now - fpsTime),
                drawn,
                meshes.length,
            );
            stdout.flush();
            frames = 0;
            fpsTime = now;
        }
    }

    worldgen.stop();
    window.close();
}

Matrix4 applyInput(Window* window, Matrix4 camera, float dt, bool autoDrive) {
    float speed = 0.9f * dt;
    float turn = 1.4f * dt;

    if (window.key(GLFW_KEY_ESCAPE)) {
        window.requestClose();
    }
    if (autoDrive) {
        camera = camera * translation([0, 0, -speed * 0.35f]);
    }
    if (window.key(GLFW_KEY_W)) {
        camera = camera * translation([0, 0, -speed]);
    }
    if (window.key(GLFW_KEY_S)) {
        camera = camera * translation([0, 0, speed]);
    }
    if (window.key(GLFW_KEY_A)) {
        camera = camera * translation([-speed, 0, 0]);
    }
    if (window.key(GLFW_KEY_D)) {
        camera = camera * translation([speed, 0, 0]);
    }
    if (window.key(GLFW_KEY_SPACE)) {
        camera = camera * translation([0, speed, 0]);
    }
    if (window.key(GLFW_KEY_LEFT_SHIFT)) {
        camera = camera * translation([0, -speed, 0]);
    }
    if (window.key(GLFW_KEY_LEFT)) {
        camera = camera * rotation(0, 2, -turn);
    }
    if (window.key(GLFW_KEY_RIGHT)) {
        camera = camera * rotation(0, 2, turn);
    }
    if (window.key(GLFW_KEY_UP)) {
        camera = camera * rotation(1, 2, -turn);
    }
    if (window.key(GLFW_KEY_DOWN)) {
        camera = camera * rotation(1, 2, turn);
    }
    return camera;
}

int drawWorld(
    ref Renderer renderer,
    Cube* anchor,
    MVector camPos,
    Matrix4 camInverse,
    ref MeshCache[Cube*] meshes,
) {
    renderer.beginFrame();

    bool[Cube*] seen;
    Cube*[] queue = [anchor];
    seen[anchor] = true;
    int drawn = 0;

    for (size_t i = 0; i < queue.length; i++) {
        Cube* c = queue[i];

        MVector center = (c.transform * MVector.origin()).normalized();
        if (hyperbolicDistance(camPos, center) > VIEW_RADIUS) {
            continue;
        }

        foreach (f; 0 .. FACES) {
            Cube* n = c.neighbor(f);
            if (n !is null && (n in seen) is null) {
                seen[n] = true;
                queue ~= n;
            }
        }

        if (c.loadState() != State.Ready) {
            continue;
        }

        uint generation = c.loadGeneration();
        MeshCache* cached = c in meshes;
        if (cached is null || !cached.present || cached.generation != generation) {
            CubeMesh built = renderer.upload(c.voxels);
            meshes[c] = MeshCache(built, generation, true);
            cached = c in meshes;
        }

        renderer.draw(cached.mesh, camInverse * c.transform);
        drawn++;
    }

    return drawn;
}
