module main;

import std.stdio : writefln, stdout;
import std.math : tanh;
import client.glfw;
import client.window : Window;
import client.renderer : Renderer, CubeMesh;
import common.math : Matrix4, MVector, translation, rotation, inverseIsometry;
import common.graph : Node, Chunk, State;
import common.geometry : SIDES, sideTransform, inRadius, faceNormalF;
import common.walk : Placed, walk;
import common.worldgen_thread : WorldgenThread, SHELLS;

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

    WorldgenThread* worldgen = WorldgenThread.create();
    worldgen.start();

    // Camera pose RELATIVE TO THE CURRENT ROOT NODE. It never accumulates a global
    // position: when the camera crosses a face, we re-root and rebase this pose by
    // the inverse side reflection, so it stays small and bounded.
    Node* root = worldgen.currentRoot();
    Matrix4 camera = translation([0.0f, 0.8f, 0.0f]) * rotation(1, 2, -1.5707963f);

    MeshCache[Chunk*] meshes;

    double last = glfwGetTime();
    double fpsTime = last;
    int frames = 0;

    while (!window.shouldClose()) {
        double now = glfwGetTime();
        float dt = cast(float)(now - last);
        last = now;

        window.poll();
        camera = applyInput(window, camera, dt, autoDrive);

        // Re-root if the camera left the root node through one of its faces.
        reroot(root, camera);
        worldgen.setRoot(root);

        Matrix4 camInverse = inverseIsometry(camera);
        int drawn = drawWorld(renderer, root, camInverse, meshes);
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

/// If the camera has moved past one of the root's faces, step the root to that
/// neighbor and rebase the camera pose into the new root's frame. Repeats until
/// the camera is inside the root. Pure topology + the local side reflection; no
/// global position is ever formed.
void reroot(ref Node* root, ref Matrix4 camera) {
    foreach (_; 0 .. 8) {
        MVector camPos = (camera * MVector.origin()).normalized();
        int crossed = sideExited(camPos);
        if (crossed < 0) {
            return;
        }
        Node* n = root.neighbor(crossed);
        if (n is null) {
            return; // not generated yet; stay put this frame
        }
        // Move into the neighbor: the new root is n, and the camera expressed in
        // n's frame is the inverse face reflection applied to the old pose.
        Matrix4 refl = sideTransform(crossed);
        camera = inverseIsometry(refl) * camera;
        root = n;
    }
}

/// Which face (if any) the camera position lies beyond, in the root's frame.
/// Returns -1 if the camera is still inside the root cell. The cell boundary
/// along a face is at Klein coordinate tanh(in-radius) toward that face normal.
int sideExited(MVector camPos) {
    float bound = cast(float) tanh(inRadius());
    int best = -1;
    float worst = bound;
    foreach (side; 0 .. SIDES) {
        float[3] d = faceNormalF(side);
        // Klein coordinate of the camera projected onto this face normal.
        float kx = camPos.data[0] / camPos.data[3];
        float ky = camPos.data[1] / camPos.data[3];
        float kz = camPos.data[2] / camPos.data[3];
        float along = kx * d[0] + ky * d[1] + kz * d[2];
        if (along > worst) {
            worst = along;
            best = side;
        }
    }
    return best;
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
    Node* root,
    Matrix4 camInverse,
    ref MeshCache[Chunk*] meshes,
) {
    renderer.beginFrame();

    Placed[] placed = walk(root, SHELLS);
    int drawn = 0;

    foreach (ref p; placed) {
        foreach (side; 0 .. SIDES) {
            Chunk* chunk = &p.node.chunks[side];
            if (chunk.loadState() != State.Ready) {
                continue;
            }

            uint generation = chunk.loadGeneration();
            MeshCache* cached = chunk in meshes;
            if (cached is null || !cached.present || cached.generation != generation) {
                CubeMesh built = renderer.upload(chunk.voxels);
                meshes[chunk] = MeshCache(built, generation, true);
                cached = chunk in meshes;
            }

            renderer.draw(cached.mesh, camInverse * p.frame * sideTransform(side));
            drawn++;
        }
    }

    return drawn;
}
