module common.worldgen_thread;

import core.thread : Thread;
import core.atomic : atomicLoad, atomicStore, MemoryOrder;
import core.sync.mutex : Mutex;
import common.math : Matrix4, MVector, hyperbolicDistance;
import common.geometry : FACES;
import common.graph : Graph, Cube, State;
import common.worldgen : generate;

/// Owns the cube graph and grows it on a dedicated thread. The render thread
/// reads the graph by atomic pointer load and only writes the camera transform.
struct WorldgenThread {
    private Graph* graph;
    private Thread thread;
    private shared bool stopping;
    private Mutex camLock;
    private Matrix4 camTransform;
    private float radius;
    private Cube* anchor;
    private shared(Cube)* published; // camera's cube, for the render thread
    private Cube*[] queue;
    private bool[Cube*] seen;

    static WorldgenThread* create(float radius) {
        WorldgenThread* w = new WorldgenThread;
        w.graph = Graph.create();
        w.camTransform = Matrix4.identity();
        w.radius = radius;
        w.camLock = new Mutex();
        w.thread = new Thread(&w.run);
        w.thread.isDaemon = true;
        return w;
    }

    void start() {
        thread.start();
    }

    void stop() {
        atomicStore!(MemoryOrder.rel)(stopping, true);
        thread.join();
    }

    void setCamera(Matrix4 t) {
        camLock.lock();
        camTransform = t;
        camLock.unlock();
    }

    /// The cube the camera is currently in, for the render thread's read-only
    /// walk. Returns the root until the worldgen thread has run its first pass.
    Cube* currentCube() {
        Cube* c = cast(Cube*) atomicLoad!(MemoryOrder.acq)(published);
        return c is null ? graph.root : c;
    }

    Cube* rootCube() {
        return graph.root;
    }

    private void run() {
        while (!atomicLoad!(MemoryOrder.acq)(stopping)) {
            camLock.lock();
            Matrix4 cam = camTransform;
            camLock.unlock();

            if (step(cam) == 0) {
                Thread.yield();
            }
        }
    }

    private int step(Matrix4 cam) {
        MVector camPos = (cam * MVector.origin()).normalized();

        if (anchor is null) {
            anchor = graph.root;
        }
        anchor = graph.findCube(anchor, camPos);
        atomicStore!(MemoryOrder.rel)(published, cast(shared(Cube)*) anchor);

        // BFS outward from the camera's cube, generating any Empty cube within
        // radius. Stop after a bounded number of generations per pass: hyperbolic
        // volume grows exponentially, so the in-radius ball holds a huge number of
        // cubes — re-walking all of them every pass would starve the camera
        // follow above. Capping keeps each pass short and the anchor fresh.
        enum int MAX_PER_PASS = 32;

        queue.length = 0;
        seen.clear();
        queue ~= anchor;
        seen[anchor] = true;

        int generated = 0;
        for (size_t i = 0; i < queue.length && generated < MAX_PER_PASS; i++) {
            Cube* c = queue[i];

            if (hyperbolicDistance(camPos, graph.center(c)) > radius) {
                continue;
            }

            if (c.loadState() == State.Empty) {
                c.setState(State.Generating);
                generate(c);
                c.setState(State.Ready);
                generated++;
            }

            foreach (f; 0 .. FACES) {
                Cube* n = graph.ensureNeighbor(c, f);
                if (n !is null && (n in seen) is null) {
                    seen[n] = true;
                    queue ~= n;
                }
            }
        }
        return generated;
    }
}
