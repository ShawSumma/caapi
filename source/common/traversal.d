module common.traversal;

import core.stdc.math : coshf;
import core.sys.posix.time : CLOCK_MONOTONIC, clock_gettime, timespec;
import common.array : Array;
import common.dodeca : BOUNDING_SPHERE_RADIUS, SIDE_COUNT, Side, sideReflection;
import common.graph : Graph, NO_SLOT, NodeId;
import common.math : MIsometry, MPoint, MVector;

enum uint NODES_PER_CLOCK_CHECK = 64;
enum double NO_DEADLINE = double.infinity;
enum double NANOSECONDS_PER_MILLISECOND = 1e6;
enum double MILLISECONDS_PER_SECOND = 1e3;
enum uint NOT_COLLECTED = uint.max;

struct NearbyNode {
    NodeId id;
    MIsometry!float transform;
    uint slot = NO_SLOT;
}

struct NearbyScratch {
    Array!NearbyNode nodes;
    Array!uint stamp;
    Array!uint position;
    MPoint!float startPoint;
    size_t front;
    float coshThreshold = 0;
    uint generation;
    bool building;

    void release() {
        nodes.release();
        stamp.release();
        position.release();
    }

    uint indexOf(uint slot) const {
        uint result = NOT_COLLECTED;
        if (slot < stamp.length && stamp.ptr[slot] == generation) {
            result = position.ptr[slot];
        }
        return result;
    }
}

void beginNearby(NearbyScratch* scratch, Graph* graph, NodeId startNode, MIsometry!float startLocal, float distance) {
    scratch.coshThreshold = coshf(distance + BOUNDING_SPHERE_RADIUS);
    scratch.nodes.clear();
    scratch.front = 0;
    scratch.generation += 1;
    scratch.building = true;
    scratch.startPoint = startLocal * MPoint!float.origin();
    uint startSlot = graph.slotOf(startNode);
    if (startSlot != NO_SLOT) {
        collect(scratch, graph, NearbyNode(startNode, MIsometry!float.identity(), startSlot));
    }
}

void collect(NearbyScratch* scratch, Graph* graph, NearbyNode node) {
    if (scratch.stamp.length < graph.nodeCount) {
        scratch.stamp.resize(graph.nodeCount);
        scratch.position.resize(graph.nodeCount);
    }
    scratch.stamp.ptr[node.slot] = scratch.generation;
    scratch.position.ptr[node.slot] = cast(uint) scratch.nodes.length;
    scratch.nodes.append(node);
}

bool continueNearby(NearbyScratch* scratch, Graph* graph, double deadline) {
    uint processed = 0;
    bool inTime = true;
    while (scratch.building && inTime) {
        if (scratch.front == scratch.nodes.length) {
            scratch.building = false;
        } else {
            expand(scratch, graph, scratch.nodes.ptr[scratch.front]);
            scratch.front += 1;
            processed += 1;
            if (processed % NODES_PER_CLOCK_CHECK == 0) {
                inTime = nowMilliseconds() < deadline;
            }
        }
    }
    return !scratch.building;
}

void expand(NearbyScratch* scratch, Graph* graph, NearbyNode current) {
    foreach (sideIndex; 0 .. SIDE_COUNT) {
        Side side = cast(Side) sideIndex;
        uint neighbor = graph.neighborSlot(current.slot, side);
        if (neighbor == NO_SLOT || scratch.indexOf(neighbor) == NOT_COLLECTED) {
            MIsometry!float reflection = sideReflection(side);
            MVector!float reflectedOrigin = MVector!float(reflection.mat.data[3][0], reflection.mat.data[3][1], reflection.mat.data[3][2], reflection.mat.data[3][3]);
            if (!(-scratch.startPoint.mip(current.transform * reflectedOrigin) > scratch.coshThreshold)) {
                if (neighbor == NO_SLOT) {
                    neighbor = graph.ensureNeighborSlot(current.slot, side);
                }
                if (scratch.indexOf(neighbor) == NOT_COLLECTED) {
                    collect(scratch, graph, NearbyNode(graph.idAt(neighbor), current.transform * reflection, neighbor));
                }
            }
        }
    }
}

NearbyNode[] ensureAndCollectNearby(NearbyScratch* scratch, Graph* graph, NodeId startNode, MIsometry!float startLocal, float distance) {
    beginNearby(scratch, graph, startNode, startLocal, distance);
    continueNearby(scratch, graph, NO_DEADLINE);
    return scratch.nodes.slice();
}

double nowMilliseconds() {
    timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec * MILLISECONDS_PER_SECOND + now.tv_nsec / NANOSECONDS_PER_MILLISECOND;
}
