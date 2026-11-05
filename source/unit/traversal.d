module unit.traversal;

import core.stdc.stdlib : free;
import base.array : Array;
import base.parallel : Executor, TaskSource, WorkerPool;
import base.vector3 : Vec3;
import common.graph : Graph;
import common.position : Position;
import common.traversal : NearbyNode, NearbyScratch;
import common.worldgen.generation : Worldgen;
import geometry.honeycomb : FACE_COUNT;
import geometry.lorentz : Motion, Point;

enum ubyte DIMENSION = 4;
enum float SET_RADIUS = 3.0f;
enum float DERIVE_RADIUS = 2.5f;
enum uint WORKERS = 3;
immutable Vec3!float DRIFT = Vec3!float(0.3f, -0.2f, 0.1f);

bool takesNoTask(void* context, uint worker) {
    return false;
}

bool isSameMotion(Motion!float a, Motion!float b) {
    foreach (column; 0 .. 4) {
        foreach (row; 0 .. 4) {
            if (a.m.c[column][row] != b.m.c[column][row]) {
                return false;
            }
        }
    }
    return true;
}

unittest {
    Graph graph = Graph.make(DIMENSION, Worldgen.makeTerrain());
    NearbyScratch scratch;
    scratch.collectAll(graph, Position.origin(), SET_RADIUS);
    Motion!float drift = Motion!float.shift(DRIFT);
    foreach (ref node; scratch.nodes.slice()) {
        node.transform = drift * node.transform;
    }
    scratch.nodes.ptr[0].transform = Motion!float.identity();
    Array!NearbyNode drifted;
    drifted.appendAll(scratch.nodes.slice());
    uint first = scratch.nodes.ptr[0].slot;
    scratch.rederive(graph, first, Point!float.origin(), DERIVE_RADIUS, Executor.init);
    Array!NearbyNode alone;
    alone.appendAll(scratch.nodes.slice());
    scratch.nodes.clear();
    scratch.nodes.appendAll(drifted.slice());
    WorkerPool* pool = WorkerPool.make(WORKERS, TaskSource(&takesNoTask, null));
    scratch.rederive(graph, first, Point!float.origin(), DERIVE_RADIUS, Executor(pool));
    pool.release();
    free(pool);
    size_t changed = 0;
    foreach (index, node; scratch.nodes.slice()) {
        assert(isSameMotion(node.transform, alone.ptr[index].transform));
        if (!isSameMotion(node.transform, drifted.ptr[index].transform)) {
            changed += 1;
        }
    }
    assert(changed > FACE_COUNT);
    drifted.release();
    alone.release();
    scratch.release();
    graph.release();
}
