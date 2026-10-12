module common.traversal;

import core.atomic : atomicExchange;
import core.stdc.math : coshf;
import common.array : Array;
import common.clock : nowMilliseconds;
import common.dodeca : BOUNDING_SPHERE_RADIUS, SIDE_COUNT, Side, reflection;
import common.graph : Graph, NO_SLOT, NodeContent, NodeId;
import common.math : MIsometry, MPoint, MVector;
import common.parallel : Executor, ParallelJob;
import common.position : Position;
import common.worldgen.sky : mayHoldContent;

enum double NO_DEADLINE = double.infinity;
enum uint NOT_COLLECTED = uint.max;
enum size_t EXPAND_BATCH = 256;
enum size_t PREPARE_BATCH = 256;

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

struct MissingSide {
    uint index;
    Side side;
}

struct ExpandOutput {
    Array!NearbyNode found;
    Array!uint unknown;
    Array!MissingSide missing;

    void clear() {
        found.clear();
        unknown.clear();
        missing.clear();
    }

    void release() {
        found.release();
        unknown.release();
        missing.release();
    }
}

struct ExpandJob {
    NearbyScratch* scratch;
    const(Graph)* graph;
    size_t front;
    size_t end;
}

void expandBatch(void* context, size_t index, uint worker) {
    ExpandJob* job = cast(ExpandJob*) context;
    NearbyScratch* scratch = job.scratch;
    ExpandOutput* output = &scratch.outputs.ptr[worker];
    size_t first = job.front + index * EXPAND_BATCH;
    size_t last = first + EXPAND_BATCH;
    if (last > job.end) {
        last = job.end;
    }
    foreach (position; first .. last) {
        NearbyNode current = scratch.nodes.ptr[position];
        NodeContent content = job.graph.nodeAt(current.slot).content;
        if (scratch.isInner(current) || content == NodeContent.holding) {
            scratch.expandKnown(*job.graph, current, cast(uint) position, *output);
        } else if (content == NodeContent.unknown) {
            output.unknown.append(cast(uint) position);
        }
    }
}

struct NearbyScratch {
    Array!NearbyNode nodes;
    Array!uint stamp;
    Array!uint position;
    Array!ExpandOutput outputs;
    ExpandOutput serial;
    Array!uint candidates;
    MPoint!float startPoint;
    size_t front;
    size_t missingHead;
    size_t unknownHead;
    size_t preparedHead;
    float coshThreshold = 0;
    float coshInner = 0;
    double preparingMs = 0;
    uint generation;
    bool hasPrepared;

    void release() {
        nodes.release();
        stamp.release();
        position.release();
        foreach (ref output; outputs.slice()) {
            output.release();
        }
        outputs.release();
        serial.release();
        candidates.release();
    }

    uint indexOf(uint slot) const {
        if (slot < stamp.length && stamp.ptr[slot] == generation) {
            return position.ptr[slot];
        } else {
            return NOT_COLLECTED;
        }
    }

    // The next nodes to have their content checked need their structure, which is painted for them all at once here.
    // Painting stops at a task budget, so the next batch starts at the first node this one left uncovered.
    void prepareUnknown(ref Graph graph, Executor executor) {
        candidates.clear();
        size_t index = unknownHead;
        while (index < serial.unknown.length && candidates.length < PREPARE_BATCH) {
            if (!isUnknownReady(graph, index)) {
                candidates.append(nodes.ptr[serial.unknown.ptr[index]].slot);
            }
            index += 1;
        }
        graph.prepareStructures(candidates.slice(), executor);
        preparedHead = unknownHead + 1;
        while (preparedHead < index && isUnknownReady(graph, preparedHead)) {
            preparedHead += 1;
        }
    }

    bool isUnknownReady(ref const Graph graph, size_t index) const {
        uint slot = nodes.ptr[serial.unknown.ptr[index]].slot;
        return graph.hasStructureAt(slot) || graph.nodeAt(slot).isCovered;
    }

    bool hasSerialWork() const {
        return missingHead < serial.missing.length || unknownHead < serial.unknown.length;
    }

    bool isBuilding() const {
        return front < nodes.length || hasSerialWork();
    }

    void begin(ref Graph graph, Position start, float distance, float inner) {
        coshThreshold = coshf(distance + BOUNDING_SPHERE_RADIUS);
        coshInner = coshf(inner);
        nodes.clear();
        serial.clear();
        front = 0;
        missingHead = 0;
        unknownHead = 0;
        preparedHead = 0;
        generation += 1;
        startPoint = start.local * MPoint!float.origin();
        collect(graph, NearbyNode(start.node, MIsometry!float.identity(), graph.slotOf(start.node)));
    }

    void reserveStamps(ref const Graph graph) {
        if (stamp.length < graph.nodeCount) {
            stamp.resize(graph.nodeCount);
            position.resize(graph.nodeCount);
        }
    }

    void collect(ref Graph graph, NearbyNode node) {
        reserveStamps(graph);
        stamp.ptr[node.slot] = generation;
        position.ptr[node.slot] = cast(uint) nodes.length;
        nodes.append(node);
    }

    bool claim(uint slot) {
        return atomicExchange(cast(shared(uint)*) &stamp.ptr[slot], generation) != generation;
    }

    void advance(ref Graph graph, double deadline, Executor executor) {
        while (outputs.length < executor.workers) {
            outputs.append(ExpandOutput.init);
        }
        bool isLate = false;
        hasPrepared = false;
        while (isBuilding() && !isLate) {
            if (hasSerialWork()) {
                isLate = !drainSerial(graph, deadline, executor);
            } else {
                reserveStamps(graph);
                ExpandJob expansion = ExpandJob(&this, &graph, front, nodes.length);
                ParallelJob job = ParallelJob(&expandBatch, &expansion, deadline, (expansion.end - front + EXPAND_BATCH - 1) / EXPAND_BATCH);
                executor.run(&job);
                front += job.count * EXPAND_BATCH;
                if (front > expansion.end) {
                    front = expansion.end;
                }
                gather();
            }
            isLate = isLate || nowMilliseconds() >= deadline;
        }
    }

    void gather() {
        foreach (ref output; outputs.slice()) {
            foreach (found; output.found.slice()) {
                position.ptr[found.slot] = cast(uint) nodes.length;
                nodes.append(found);
            }
            serial.missing.appendAll(output.missing.slice());
            serial.unknown.appendAll(output.unknown.slice());
            output.clear();
        }
    }

    // Returns false when a batch of structure would not fit before the deadline; every advance prepares at least one,
    // so the search always moves on.
    bool drainSerial(ref Graph graph, double deadline, Executor executor) {
        bool isStalled = false;
        while (hasSerialWork() && nowMilliseconds() < deadline && !isStalled) {
            if (missingHead < serial.missing.length) {
                MissingSide missing = serial.missing.ptr[missingHead];
                missingHead += 1;
                NearbyNode current = nodes.ptr[missing.index];
                uint neighbor = graph.ensureNeighborSlot(current.slot, missing.side);
                if (indexOf(neighbor) == NOT_COLLECTED) {
                    collect(graph, NearbyNode(graph.idAt(neighbor), current.transform * missing.side.reflection, neighbor));
                }
            } else if (unknownHead >= preparedHead && hasPrepared && nowMilliseconds() + preparingMs > deadline) {
                isStalled = true;
            } else if (unknownHead >= preparedHead) {
                double start = nowMilliseconds();
                prepareUnknown(graph, executor);
                preparingMs = nowMilliseconds() - start;
                hasPrepared = true;
            } else {
                NearbyNode current = nodes.ptr[serial.unknown.ptr[unknownHead]];
                unknownHead += 1;
                if (graph.contentAt(current.slot) == NodeContent.holding) {
                    expandAll(graph, current);
                }
            }
        }
        if (!hasSerialWork()) {
            serial.clear();
            missingHead = 0;
            unknownHead = 0;
            preparedHead = 0;
        }
        return !isStalled;
    }

    bool isWithinReach(NearbyNode current, Side side) const {
        MIsometry!float step = side.reflection;
        MVector!float reflectedOrigin = MVector!float(step.mat.data[3]);
        return !(-startPoint.mip(current.transform * reflectedOrigin) > coshThreshold);
    }

    bool isInner(NearbyNode current) const {
        return !(-startPoint.mip(current.transform * MVector!float.origin()) > coshInner);
    }

    void expandKnown(ref const Graph graph, NearbyNode current, uint index, ref ExpandOutput output) {
        foreach (sideIndex; 0 .. SIDE_COUNT) {
            Side side = cast(Side) sideIndex;
            uint existing = graph.neighborSlot(current.slot, side);
            if ((existing == NO_SLOT || stamp.ptr[existing] != generation) && isWithinReach(current, side)) {
                if (existing == NO_SLOT) {
                    output.missing.append(MissingSide(index, side));
                } else if (claim(existing)) {
                    output.found.append(NearbyNode(graph.idAt(existing), current.transform * side.reflection, existing));
                }
            }
        }
    }

    void expandAll(ref Graph graph, NearbyNode current) {
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
        begin(graph, start, distance, distance + BOUNDING_SPHERE_RADIUS);
        advance(graph, NO_DEADLINE, Executor.init);
        return nodes.slice();
    }
}

NodeContent contentAt(ref Graph graph, uint slot) {
    if (graph.nodeAt(slot).content == NodeContent.unknown) {
        bool holds = graph.mayHoldContent(slot);
        graph.nodeAt(slot).content = holds ? NodeContent.holding : NodeContent.empty;
    }
    return graph.nodeAt(slot).content;
}
