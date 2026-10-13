module common.traversal;

import core.atomic : atomicExchange;
import core.stdc.math : coshf;
import base.array : Array;
import base.clock : nowMilliseconds;
import base.parallel : Executor, ParallelJob;
import common.graph : Graph, NO_SLOT, NodeContent, NodeId;
import common.position : Position;
import common.worldgen.sky : mayHoldContent;
import geometry.honeycomb : FACE_COUNT, FACE_DISTANCE, Face, NODE_RADIUS, mirror;
import geometry.lorentz : Motion, Point, Vec4;

enum double NO_DEADLINE = double.infinity;
enum uint NOT_COLLECTED = uint.max;
enum size_t EXPAND_BATCH = 256;
enum size_t PAINT_BATCH = 256;

struct NodeVisit {
    uint slot;
    Motion!float inverse;
}

bool isListed(const(uint)[] list, uint value) {
    size_t index = 0;
    while (index < list.length && list[index] != value) {
        index += 1;
    }
    return index < list.length;
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
        queue.visits[0] = NodeVisit(slot, Motion!float.identity());
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

    bool isUnvisitedWithin(ref const Graph graph, NodeVisit visit, Face side, Vec4!float point, float nodeThreshold) const {
        uint neighbor = graph.neighborSlot(visit.slot, side);
        return neighbor != NO_SLOT && !isVisited(neighbor) && !((side.mirror * visit.inverse * point).c[3] > nodeThreshold);
    }

    void expand(ref const Graph graph, NodeVisit visit, Vec4!float point, float nodeThreshold) {
        foreach (sideIndex; 0 .. FACE_COUNT) {
            Face side = cast(Face) sideIndex;
            if (count < capacity && isUnvisitedWithin(graph, visit, side, point, nodeThreshold)) {
                visits[count] = NodeVisit(graph.neighborSlot(visit.slot, side), side.mirror * visit.inverse);
                count += 1;
            }
        }
        front += 1;
    }
}

struct NearbyNode {
    NodeId id;
    Motion!float transform;
    uint slot;
}

struct MissingSide {
    uint index;
    Face side;
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

enum ubyte DROPPED = 0;
enum ubyte KEPT = 1;
enum ubyte FRONTIER = 2;
enum size_t KEEP_BLOCK = 4096;

struct BlockCounts {
    uint kept;
    uint frontier;
}

struct KeepJob {
    const(NearbyNode)* from;
    size_t count;
    NearbyScratch* scratch;
    BlockCounts* blocks;
    Point!float camera;
    Point!float previous;
    float coshReach;
    float coshPreviousReach;
    float coshFrontier;
    float coshInner;
    uint keptTotal;

    size_t end(size_t block) const {
        return (block + 1) * KEEP_BLOCK < count ? (block + 1) * KEEP_BLOCK : count;
    }

    bool hasNeighborNewlyInReach(Motion!float transform) const {
        uint face = 0;
        while (face < FACE_COUNT && !isNewlyInReach(transform * MIRRORED_ORIGINS[face])) {
            face += 1;
        }
        return face < FACE_COUNT;
    }

    bool isNewlyInReach(Vec4!float center) const {
        return !(-camera.minkowski(center) > coshReach) && -previous.minkowski(center) > coshPreviousReach;
    }
}

immutable Vec4!float[FACE_COUNT] MIRRORED_ORIGINS = mirroredOrigins();

Vec4!float[FACE_COUNT] mirroredOrigins() {
    Vec4!float[FACE_COUNT] origins;
    foreach (face; 0 .. FACE_COUNT) {
        origins[face] = mirror(cast(Face) face).m.column(3);
    }
    return origins;
}

struct RebaseJob {
    NearbyNode* nodes;
    const(bool)* isRederived;
    size_t count;
    Motion!float toFrame;
}

void rebaseBlock(void* context, size_t block, uint worker) {
    RebaseJob* job = cast(RebaseJob*) context;
    size_t end = (block + 1) * KEEP_BLOCK < job.count ? (block + 1) * KEEP_BLOCK : job.count;
    foreach (index; block * KEEP_BLOCK .. end) {
        if (!job.isRederived[index]) {
            job.nodes[index].transform = job.toFrame * job.nodes[index].transform;
        }
    }
}

void sortKept(void* context, size_t block, uint worker) {
    KeepJob* job = cast(KeepJob*) context;
    BlockCounts counts;
    foreach (index; block * KEEP_BLOCK .. job.end(block)) {
        Motion!float transform = job.from[index].transform;
        Vec4!float center = transform * Vec4!float.origin();
        float product = -job.camera.minkowski(center);
        bool isNewlyInner = !(product > job.coshInner) && -job.previous.minkowski(center) > job.coshInner;
        ubyte kind = KEPT;
        if (product > job.coshReach) {
            kind = DROPPED;
        } else if (isNewlyInner || (product > job.coshFrontier && job.hasNeighborNewlyInReach(transform))) {
            kind = FRONTIER;
            counts.frontier += 1;
        } else {
            counts.kept += 1;
        }
        job.scratch.kinds.ptr[index] = kind;
    }
    job.blocks[block] = counts;
}

void copyKept(void* context, size_t block, uint worker) {
    KeepJob* job = cast(KeepJob*) context;
    NearbyScratch* scratch = job.scratch;
    uint kept = job.blocks[block].kept;
    uint frontier = job.keptTotal + job.blocks[block].frontier;
    foreach (index; block * KEEP_BLOCK .. job.end(block)) {
        ubyte kind = scratch.kinds.ptr[index];
        if (kind != DROPPED) {
            uint at = kind == KEPT ? kept++ : frontier++;
            NearbyNode node = job.from[index];
            scratch.nodes.ptr[at] = node;
            scratch.stamp.ptr[node.slot] = scratch.generation;
            scratch.position.ptr[node.slot] = at;
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
    Array!ubyte kinds;
    Array!BlockCounts blocks;
    Array!uint around;
    Array!uint chain;
    Array!bool isRederived;
    Point!float startPoint;
    size_t front;
    size_t missingHead;
    size_t unknownHead;
    size_t paintedHead;
    float coshThreshold = 0;
    float coshInner = 0;
    double paintingMs = 0;
    uint generation;
    bool hasPainted;

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
        kinds.release();
        blocks.release();
        around.release();
        chain.release();
        isRederived.release();
    }

    uint indexOf(uint slot) const {
        if (slot < stamp.length && stamp.ptr[slot] == generation) {
            return position.ptr[slot];
        } else {
            return NOT_COLLECTED;
        }
    }

    void paintUnknownAhead(ref Graph graph, Executor executor) {
        candidates.clear();
        size_t index = unknownHead;
        while (index < serial.unknown.length && candidates.length < PAINT_BATCH) {
            if (!isUnknownReady(graph, index)) {
                candidates.append(nodes.ptr[serial.unknown.ptr[index]].slot);
            }
            index += 1;
        }
        graph.paintAhead(candidates.slice(), executor);
        paintedHead = unknownHead + 1;
        while (paintedHead < index && isUnknownReady(graph, paintedHead)) {
            paintedHead += 1;
        }
    }

    bool isUnknownReady(ref const Graph graph, size_t index) const {
        uint slot = nodes.ptr[serial.unknown.ptr[index]].slot;
        return graph.isFinished(slot) || graph.structures.at(slot).isCovered;
    }

    bool hasSerialWork() const {
        return missingHead < serial.missing.length || unknownHead < serial.unknown.length;
    }

    bool isBuilding() const {
        return front < nodes.length || hasSerialWork();
    }

    void begin(ref Graph graph, Position start, float distance, float inner) {
        coshThreshold = coshf(distance + NODE_RADIUS);
        coshInner = coshf(inner);
        nodes.clear();
        serial.clear();
        front = 0;
        missingHead = 0;
        unknownHead = 0;
        paintedHead = 0;
        generation += 1;
        startPoint = start.local * Point!float.origin();
        collect(graph, NearbyNode(start.node, Motion!float.identity(), graph.slotOf(start.node)));
    }

    void reserveStamps(ref const Graph graph) {
        if (stamp.length < graph.slotCount) {
            stamp.resize(graph.slotCount);
            position.resize(graph.slotCount);
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

    bool collectAround(ref Graph graph, uint cameraSlot, Point!float camera, float reach) {
        uint first = indexOf(cameraSlot);
        if (first == NOT_COLLECTED) {
            return false;
        } else {
            bool isFinished = !isBuilding();
            float coshReach = coshf(reach);
            around.clear();
            around.append(first);
            size_t head = 0;
            while (head < around.length) {
                NearbyNode current = nodes.ptr[around.ptr[head]];
                foreach (index; 0 .. FACE_COUNT) {
                    Face face = cast(Face) index;
                    Motion!float transform = current.transform * face.mirror;
                    if (head == 0 || !(-camera.minkowski(transform * Vec4!float.origin()) > coshReach)) {
                        uint neighbor = graph.ensureNeighborSlot(current.slot, face);
                        uint position = indexOf(neighbor);
                        if (position == NOT_COLLECTED) {
                            position = cast(uint) nodes.length;
                            collect(graph, NearbyNode(graph.idAt(neighbor), transform, neighbor));
                        }
                        if (!isListed(around.slice(), position)) {
                            around.append(position);
                        }
                    }
                }
                head += 1;
            }
            if (isFinished) {
                front = nodes.length;
            }
            return true;
        }
    }

    void advance(ref Graph graph, double deadline, Executor executor) {
        while (outputs.length < executor.workers) {
            outputs.append(ExpandOutput.init);
        }
        bool isLate = false;
        hasPainted = false;
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

    bool drainSerial(ref Graph graph, double deadline, Executor executor) {
        bool isStalled = false;
        while (hasSerialWork() && nowMilliseconds() < deadline && !isStalled) {
            if (missingHead < serial.missing.length) {
                MissingSide missing = serial.missing.ptr[missingHead];
                missingHead += 1;
                NearbyNode current = nodes.ptr[missing.index];
                uint neighbor = graph.ensureNeighborSlot(current.slot, missing.side);
                if (indexOf(neighbor) == NOT_COLLECTED) {
                    collect(graph, NearbyNode(graph.idAt(neighbor), current.transform * missing.side.mirror, neighbor));
                }
            } else if (unknownHead >= paintedHead && hasPainted && nowMilliseconds() + paintingMs > deadline) {
                isStalled = true;
            } else if (unknownHead >= paintedHead) {
                double start = nowMilliseconds();
                paintUnknownAhead(graph, executor);
                paintingMs = nowMilliseconds() - start;
                hasPainted = true;
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
            paintedHead = 0;
        }
        return !isStalled;
    }

    bool isWithinReach(NearbyNode current, Face side) const {
        Vec4!float mirroredOrigin = side.mirror.m.column(3);
        return !(-startPoint.minkowski(current.transform * mirroredOrigin) > coshThreshold);
    }

    bool isInner(NearbyNode current) const {
        return !(-startPoint.minkowski(current.transform * Vec4!float.origin()) > coshInner);
    }

    void expandKnown(ref const Graph graph, NearbyNode current, uint index, ref ExpandOutput output) {
        foreach (sideIndex; 0 .. FACE_COUNT) {
            Face side = cast(Face) sideIndex;
            uint existing = graph.neighborSlot(current.slot, side);
            if ((existing == NO_SLOT || stamp.ptr[existing] != generation) && isWithinReach(current, side)) {
                if (existing == NO_SLOT) {
                    output.missing.append(MissingSide(index, side));
                } else if (claim(existing)) {
                    output.found.append(NearbyNode(graph.idAt(existing), current.transform * side.mirror, existing));
                }
            }
        }
    }

    void expandAll(ref Graph graph, NearbyNode current) {
        foreach (sideIndex; 0 .. FACE_COUNT) {
            Face side = cast(Face) sideIndex;
            uint existing = graph.neighborSlot(current.slot, side);
            if ((existing == NO_SLOT || indexOf(existing) == NOT_COLLECTED) && isWithinReach(current, side)) {
                uint neighbor = graph.ensureNeighborSlot(current.slot, side);
                if (indexOf(neighbor) == NOT_COLLECTED) {
                    collect(graph, NearbyNode(graph.idAt(neighbor), current.transform * side.mirror, neighbor));
                }
            }
        }
    }

    void beginFrom(ref const NearbyScratch finished, ref Graph graph, Point!float camera, float distance, float inner, Executor executor) {
        float moved = camera.distance(finished.startPoint);
        float frontier = distance + NODE_RADIUS - 2 * FACE_DISTANCE - moved;
        size_t blockCount = (finished.nodes.length + KEEP_BLOCK - 1) / KEEP_BLOCK;
        kinds.resize(finished.nodes.length);
        blocks.resize(blockCount);
        serial.clear();
        missingHead = 0;
        unknownHead = 0;
        paintedHead = 0;
        generation += 1;
        reserveStamps(graph);
        KeepJob keeping = KeepJob(finished.nodes.ptr, finished.nodes.length, &this, blocks.ptr, camera, finished.startPoint, coshf(distance + NODE_RADIUS), finished.coshThreshold, frontier > 0 ? coshf(frontier) : 1, coshf(inner));
        ParallelJob sorting = ParallelJob(&sortKept, &keeping, NO_DEADLINE, blockCount);
        executor.run(&sorting);
        BlockCounts total;
        foreach (ref counts; blocks.slice()) {
            BlockCounts own = counts;
            counts = total;
            total.kept += own.kept;
            total.frontier += own.frontier;
        }
        keeping.keptTotal = total.kept;
        nodes.reserve(total.kept + total.frontier);
        nodes.length = total.kept + total.frontier;
        ParallelJob copying = ParallelJob(&copyKept, &keeping, NO_DEADLINE, blockCount);
        executor.run(&copying);
        coshThreshold = keeping.coshReach;
        coshInner = keeping.coshInner;
        startPoint = camera;
        front = total.kept;
    }

    void rebase(ref const Graph graph, uint cameraSlot, Motion!float toFrame, float radius, Executor executor) {
        float coshRadius = coshf(radius);
        uint first = indexOf(cameraSlot);
        isRederived.clear();
        isRederived.resize(nodes.length);
        chain.clear();
        chain.append(first);
        isRederived.ptr[first] = true;
        nodes.ptr[first].transform = Motion!float.identity();
        size_t head = 0;
        while (head < chain.length) {
            NearbyNode current = nodes.ptr[chain.ptr[head]];
            foreach (sideIndex; 0 .. FACE_COUNT) {
                Face side = cast(Face) sideIndex;
                uint neighbor = graph.neighborSlot(current.slot, side);
                uint index = neighbor == NO_SLOT ? NOT_COLLECTED : indexOf(neighbor);
                if (index != NOT_COLLECTED && !isRederived.ptr[index]) {
                    Motion!float transform = current.transform * side.mirror;
                    if (!((transform * Point!float.origin()).v.c[3] > coshRadius)) {
                        nodes.ptr[index].transform = transform;
                        isRederived.ptr[index] = true;
                        chain.append(index);
                    }
                }
            }
            head += 1;
        }
        RebaseJob job = RebaseJob(nodes.ptr, isRederived.ptr, nodes.length, toFrame);
        ParallelJob rebasing = ParallelJob(&rebaseBlock, &job, NO_DEADLINE, (nodes.length + KEEP_BLOCK - 1) / KEEP_BLOCK);
        executor.run(&rebasing);
        startPoint = toFrame * startPoint;
    }

    NearbyNode[] collectAll(ref Graph graph, Position start, float distance) {
        begin(graph, start, distance, distance + NODE_RADIUS);
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
