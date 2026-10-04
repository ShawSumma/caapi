module common.traversal;

import core.stdc.math : coshf;
import common.array : Array;
import common.clock : nowMilliseconds;
import common.dodeca : BOUNDING_SPHERE_RADIUS, SIDE_COUNT, Side, reflection;
import common.graph : Graph, NO_SLOT, NodeId;
import common.math : MIsometry, MPoint, MVector;
import common.position : Position;

enum uint NODES_PER_CLOCK_CHECK = 64;
enum double NO_DEADLINE = double.infinity;
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

    bool isBuilding() const {
        return front < nodes.length;
    }

    void begin(ref Graph graph, Position start, float distance) {
        coshThreshold = coshf(distance + BOUNDING_SPHERE_RADIUS);
        nodes.clear();
        front = 0;
        generation += 1;
        startPoint = start.local * MPoint!float.origin();
        collect(graph, NearbyNode(start.node, MIsometry!float.identity(), graph.slotOf(start.node)));
    }

    void collect(ref Graph graph, NearbyNode node) {
        if (stamp.length < graph.nodeCount) {
            stamp.resize(graph.nodeCount);
            position.resize(graph.nodeCount);
        }
        stamp.ptr[node.slot] = generation;
        position.ptr[node.slot] = cast(uint) nodes.length;
        nodes.append(node);
    }

    bool isOverBudget(uint processed, double deadline) const {
        return processed > 0 && processed % NODES_PER_CLOCK_CHECK == 0 && nowMilliseconds() >= deadline;
    }

    void advance(ref Graph graph, double deadline) {
        uint processed = 0;
        while (isBuilding() && !isOverBudget(processed, deadline)) {
            expand(graph, nodes.ptr[front]);
            front += 1;
            processed += 1;
        }
    }

    bool isWithinReach(NearbyNode current, Side side) const {
        MIsometry!float step = side.reflection;
        MVector!float reflectedOrigin = MVector!float(step.mat.data[3]);
        return !(-startPoint.mip(current.transform * reflectedOrigin) > coshThreshold);
    }

    void expand(ref Graph graph, NearbyNode current) {
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

    NearbyNode[] collectAll(ref Graph graph, Position start, float distance) {
        begin(graph, start, distance);
        advance(graph, NO_DEADLINE);
        return nodes.slice();
    }
}
