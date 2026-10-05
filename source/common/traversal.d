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

struct NodeVisit {
    uint slot;
    MIsometry!float inverse;
}

bool isVisited(const(NodeVisit)[] visits, uint slot) {
    size_t index = 0;
    while (index < visits.length && visits[index].slot != slot) {
        index += 1;
    }
    return index < visits.length;
}

struct VisitQueue(uint capacity) {
    NodeVisit[capacity] visits = void;
    uint count;
    uint front;

    static VisitQueue fromSlot(uint slot) {
        VisitQueue queue;
        queue.visits[0] = NodeVisit(slot, MIsometry!float.identity());
        queue.count = 1;
        return queue;
    }

    bool hasNext() const {
        return front < count;
    }

    NodeVisit current() const {
        return visits[front];
    }

    bool isVisited(uint slot) const {
        return visits[0 .. count].isVisited(slot);
    }

    bool isUnvisitedWithin(ref const Graph graph, NodeVisit visit, Side side, MVector!float point, float nodeThreshold) const {
        uint neighbor = graph.neighborSlot(visit.slot, side);
        return neighbor != NO_SLOT && !isVisited(neighbor) && !((side.reflection * visit.inverse * point).data[3] > nodeThreshold);
    }

    void expand(ref const Graph graph, NodeVisit visit, MVector!float point, float nodeThreshold) {
        foreach (sideIndex; 0 .. SIDE_COUNT) {
            Side side = cast(Side) sideIndex;
            if (count < capacity && isUnvisitedWithin(graph, visit, side, point, nodeThreshold)) {
                visits[count] = NodeVisit(graph.neighborSlot(visit.slot, side), side.reflection * visit.inverse);
                count += 1;
            }
        }
        front += 1;
    }
}

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
