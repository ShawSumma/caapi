module common.worldgen_thread;

import core.thread : Thread;
import core.atomic : atomicLoad, atomicStore, MemoryOrder;
import common.geometry : SIDES, sideTransform;
import common.graph : Graph, Node, Chunk, State;
import common.walk : Placed, walk;
import common.worldgen : generate;
import common.math : Matrix4;

enum int SHELLS = 3;

/// Owns the node graph and fills it on a dedicated thread. Purely local: it keeps
/// the root's N-shell neighborhood generated. The render thread re-roots by
/// reporting which side the camera crossed (setRoot); there are no positions.
struct WorldgenThread {
    private Graph* graph;
    private Thread thread;
    private shared bool stopping;
    private shared(Node)* root;

    static WorldgenThread* create() {
        WorldgenThread* w = new WorldgenThread;
        w.graph = Graph.create();
        atomicStore!(MemoryOrder.rel)(w.root, cast(shared(Node)*) w.graph.root);
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

    /// Render thread -> worldgen thread: the player crossed into this node; make
    /// it the new root so the N-shell neighborhood recenters on it.
    void setRoot(Node* node) {
        atomicStore!(MemoryOrder.rel)(root, cast(shared(Node)*) node);
    }

    Node* currentRoot() {
        return cast(Node*) atomicLoad!(MemoryOrder.acq)(root);
    }

    private void run() {
        while (!atomicLoad!(MemoryOrder.acq)(stopping)) {
            Node* r = currentRoot();
            int generated = fill(r);
            if (generated == 0) {
                Thread.yield();
            }
        }
    }

    /// Ensure the N-shell neighborhood of `r` exists and every chunk is generated.
    /// Returns how many chunks it generated this pass.
    private int fill(Node* r) {
        // Create + link the topology out to N shells, then walk it to get each
        // node's transient local frame for terrain generation.
        graph.neighborhoodFrom(r, SHELLS);
        Placed[] placed = walk(r, SHELLS);

        int generated = 0;
        foreach (ref p; placed) {
            foreach (side; 0 .. SIDES) {
                Chunk* chunk = &p.node.chunks[side];
                if (chunk.loadState() == State.Empty) {
                    chunk.setState(State.Generating);
                    // The chunk sits across face `side`; its frame is the node
                    // frame reflected across that face.
                    generate(p.node, side, chunk, p.frame * sideTransform(side));
                    chunk.setState(State.Ready);
                    generated++;
                }
            }
        }
        return generated;
    }
}
