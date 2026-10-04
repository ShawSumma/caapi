module common.traversal;

import core.stdc.math : coshf;
import core.sys.posix.time : CLOCK_MONOTONIC, clock_gettime, timespec;
import common.array : Array;
import common.dodeca : BOUNDING_SPHERE_RADIUS, SIDE_COUNT, Side, reflection;
import common.graph : Graph, NO_SLOT, NodeId;
import common.math : MIsometry, MPoint, MVector;
import common.proto : Position;

enum uint NODES_PER_CLOCK_CHECK = 64;
enum double NO_DEADLINE = double.infinity;
enum double NANOSECONDS_PER_MILLISECOND = 1e6;
enum double MILLISECONDS_PER_SECOND = 1e3;
enum uint NOT_COLLECTED = uint.max;

struct NearbyNode {
    NodeId id;
    MIsometry!float transform;
    uint slot;
}

struct NearbyScratch {
    Array!NearbyNode nodes;
    Array!uint stamp;
    Array!uint position;
    MPoint!float startPoint;
    size_t front;
    float coshThreshold = 0;
    uint generation;
    bool isBuilding;

    void release() {
        nodes.release();
        stamp.release();
        position.release();
    }

    uint indexOf(uint slot) const {
        if (slot < stamp.length && stamp.ptr[slot] == generation) {
            return position.ptr[slot];
        } else {
            return NOT_COLLECTED;
        }
    }

    void begin(Graph* graph, Position start, float distance) {
        coshThreshold = coshf(distance + BOUNDING_SPHERE_RADIUS);
        nodes.clear();
        front = 0;
        generation += 1;
        isBuilding = true;
        startPoint = start.local * MPoint!float.origin();
        collect(graph, NearbyNode(start.node, MIsometry!float.identity(), graph.slotOf(start.node)));
    }

    void collect(Graph* graph, NearbyNode node) {
        if (stamp.length < graph.nodeCount) {
            stamp.resize(graph.nodeCount);
            position.resize(graph.nodeCount);
        }
        stamp.ptr[node.slot] = generation;
        position.ptr[node.slot] = cast(uint) nodes.length;
        nodes.append(node);
    }

    bool advance(Graph* graph, double deadline) {
        uint processed = 0;
        while (front < nodes.length) {
            expand(graph, nodes.ptr[front]);
            front += 1;
            processed += 1;
            if (processed % NODES_PER_CLOCK_CHECK == 0 && nowMilliseconds() >= deadline) {
                return false;
            }
        }
        isBuilding = false;
        return true;
    }

    bool isWithinReach(NearbyNode current, Side side) const {
        MIsometry!float step = side.reflection;
        MVector!float reflectedOrigin = MVector!float(step.mat.data[3][0], step.mat.data[3][1], step.mat.data[3][2], step.mat.data[3][3]);
        return !(-startPoint.mip(current.transform * reflectedOrigin) > coshThreshold);
    }

    void expand(Graph* graph, NearbyNode current) {
        foreach (sideIndex; 0 .. SIDE_COUNT) {
            Side side = cast(Side) sideIndex;
            uint existing = graph.neighborSlot(current.slot, side);
            if ((existing == NO_SLOT || indexOf(existing) == NOT_COLLECTED) && isWithinReach(current, side)) {
                uint neighbor = graph.ensureNeighborSlot(current.slot, side);
                if (indexOf(neighbor) == NOT_COLLECTED) {
                    collect(graph, NearbyNode(graph.idAt(neighbor), current.transform * side.reflection, neighbor));
                }
            }
        }
    }

    NearbyNode[] collectAll(Graph* graph, Position start, float distance) {
        begin(graph, start, distance);
        advance(graph, NO_DEADLINE);
        return nodes.slice();
    }
}

double nowMilliseconds() {
    timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec * MILLISECONDS_PER_SECOND + now.tv_nsec / NANOSECONDS_PER_MILLISECOND;
}
