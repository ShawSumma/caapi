module common.traversal;

import core.atomic : atomicExchange;
import core.stdc.math : acoshf, coshf, fabs;
import base.array : Array;
import base.clock : Deadline, nowMilliseconds;
import base.flags : Bits;
import base.maybe : MaybeIndex;
import base.numbers : higherOf, lowerOf;
import base.parallel : Executor, ParallelJob;
import common.graph : Graph, NodeContent;
import common.position : Position;
import common.worldgen.horospheres : probeMayHoldContent;
import geometry.honeycomb : FACE_COUNT, FACE_DISTANCE, Face, NODE_RADIUS, mirror;
import geometry.lorentz : Motion, Point, Vec4;

enum size_t EXPAND_BATCH = 256;
version (WebAssembly) {
    enum size_t PAINT_BATCH = 16;
} else {
    enum size_t PAINT_BATCH = 256;
}
enum size_t DERIVE_BATCH = 64;
enum double SHELL_FLOOR = 0.01;
enum double SHELL_ROUNDING = 64 * float.epsilon;
enum size_t KEEP_BLOCK = 4096;

enum KeepKind : ubyte {
    dropped,
    kept,
    frontier,
}

struct NodeVisit {
    uint slot;
    Motion!float inverse;
}

bool isListed(T)(const(T)[] list, T value) {
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
        MaybeIndex!uint neighbor = graph.neighborSlot(visit.slot, side);
        return neighbor.exists && !isVisited(neighbor.value) && !((side.mirror * visit.inverse * point).c[3] > nodeThreshold);
    }

    void expand(ref const Graph graph, NodeVisit visit, Vec4!float point, float nodeThreshold) {
        foreach (sideIndex; 0 .. FACE_COUNT) {
            Face side = cast(Face) sideIndex;
            if (count < capacity && isUnvisitedWithin(graph, visit, side, point, nodeThreshold)) {
                visits[count] = NodeVisit(graph.neighborSlot(visit.slot, side).value, side.mirror * visit.inverse);
                count += 1;
            }
        }
        front += 1;
    }
}

struct NearbyNode {
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
    size_t last = lowerOf(first + EXPAND_BATCH, job.end);
    foreach (position; first .. last) {
        NearbyNode current = scratch.nodes.ptr[position];
        NodeContent content = job.graph.nodeAt(current.slot).content;
        if (scratch.isInner(current) || content == NodeContent.holding) {
            scratch.expandKnown(*job.graph, current, cast(uint) position, *output);
        } else if (content == NodeContent.unknown && scratch.hasOpenSide(*job.graph, current)) {
            output.unknown.append(cast(uint) position);
        }
    }
}

struct BlockCounts {
    uint kept;
    uint frontier;
}

enum KeepPass : ubyte {
    none,
    sorting,
    copying,
}

enum Drain : ubyte {
    flowing,
    stalled,
}

struct KeepJob {
    const(NearbyNode)* from;
    size_t count;
    size_t base;
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
        return lowerOf((block + 1) * KEEP_BLOCK, count);
    }

    bool hasNeighborNewlyInReach(Motion!float transform) const {
        Vec4!float toCamera;
        Vec4!float toPrevious;
        foreach (column; 0 .. 4) {
            toCamera.c[column] = -camera.minkowski(transform.m.column(column));
            toPrevious.c[column] = -previous.minkowski(transform.m.column(column));
        }
        uint face = 0;
        while (face < FACE_COUNT && !isNewlyInReach(dot(toCamera, MIRRORED_ORIGINS[face]), dot(toPrevious, MIRRORED_ORIGINS[face]))) {
            face += 1;
        }
        return face < FACE_COUNT;
    }

    bool isNewlyInReach(float coshToCamera, float coshToPrevious) const {
        return !(coshToCamera > coshReach) && coshToPrevious > coshPreviousReach;
    }
}

bool isOffHyperboloid(Vec4!float center) {
    Vec4!double exact = center.as!double();
    return fabs(-exact.minkowski(exact) - 1) > SHELL_FLOOR + SHELL_ROUNDING * exact.c[3] * exact.c[3];
}

float dot(Vec4!float a, Vec4!float b) {
    return a.c[0] * b.c[0] + a.c[1] * b.c[1] + a.c[2] * b.c[2] + a.c[3] * b.c[3];
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
    const(Bits)* rederived;
    size_t count;
    Motion!float toFrame;
}

void rebaseBlock(void* context, size_t block, uint worker) {
    RebaseJob* job = cast(RebaseJob*) context;
    size_t end = lowerOf((block + 1) * KEEP_BLOCK, job.count);
    foreach (index; block * KEEP_BLOCK .. end) {
        if (!job.rederived.has(index)) {
            job.nodes[index].transform = job.toFrame * job.nodes[index].transform;
        }
    }
}

void sortKept(void* context, size_t item, uint worker) {
    KeepJob* job = cast(KeepJob*) context;
    size_t block = job.base + item;
    BlockCounts counts;
    foreach (index; block * KEEP_BLOCK .. job.end(block)) {
        Motion!float transform = job.from[index].transform;
        Vec4!float center = transform * Vec4!float.origin();
        float product = -job.camera.minkowski(center);
        KeepKind kind = KeepKind.kept;
        if (product > job.coshReach || isOffHyperboloid(center)) {
            kind = KeepKind.dropped;
        } else if ((!(product > job.coshInner) && -job.previous.minkowski(center) > job.coshInner) || (product > job.coshFrontier && job.hasNeighborNewlyInReach(transform))) {
            kind = KeepKind.frontier;
            counts.frontier += 1;
        } else {
            counts.kept += 1;
        }
        job.scratch.kinds.ptr[index] = kind;
    }
    job.blocks[block] = counts;
}

void copyKept(void* context, size_t item, uint worker) {
    KeepJob* job = cast(KeepJob*) context;
    size_t block = job.base + item;
    NearbyScratch* scratch = job.scratch;
    uint kept = job.blocks[block].kept;
    uint frontier = job.keptTotal + job.blocks[block].frontier;
    foreach (index; block * KEEP_BLOCK .. job.end(block)) {
        KeepKind kind = scratch.kinds.ptr[index];
        if (kind != KeepKind.dropped) {
            uint at;
            if (kind == KeepKind.kept) {
                at = kept;
                kept += 1;
            } else {
                at = frontier;
                frontier += 1;
            }
            NearbyNode node = job.from[index];
            scratch.nodes.ptr[at] = node;
            scratch.collected.ptr[node.slot] = Collected(scratch.generation, at);
        }
    }
}

struct DeriveStep {
    uint index;
    uint from;
    Face side;
}

struct DeriveJob {
    NearbyScratch* scratch;
    const(Graph)* graph;
    Point!float center;
    float coshRadius;
    size_t first;
    size_t end;
}

void findDerived(void* context, size_t batch, uint worker) {
    DeriveJob* job = cast(DeriveJob*) context;
    NearbyScratch* scratch = job.scratch;
    Array!DeriveStep* found = &scratch.derived.ptr[batch];
    found.clear();
    size_t start = job.first + batch * DERIVE_BATCH;
    size_t end = lowerOf(start + DERIVE_BATCH, job.end);
    foreach (position; start .. end) {
        uint from = scratch.chain.ptr[position];
        NearbyNode current = scratch.nodes.ptr[from];
        foreach (sideIndex; 0 .. FACE_COUNT) {
            MaybeIndex!uint neighbor = job.graph.neighborSlot(current.slot, cast(Face) sideIndex);
            MaybeIndex!uint index;
            if (neighbor.exists) {
                index = scratch.indexOf(neighbor.value);
            }
            if (index.exists && !scratch.rederived.has(index.value) && !(-job.center.minkowski(current.transform * MIRRORED_ORIGINS[sideIndex]) > job.coshRadius)) {
                found.append(DeriveStep(index.value, from, cast(Face) sideIndex));
            }
        }
    }
}

void applyDerived(void* context, size_t item, uint worker) {
    NearbyScratch* scratch = (cast(DeriveJob*) context).scratch;
    DeriveStep step = scratch.claimed.ptr[item];
    scratch.nodes.ptr[step.index].transform = scratch.nodes.ptr[step.from].transform * step.side.mirror;
}

struct Collected {
    uint stamp;
    uint position;
}

struct NearbyScratch {
    Array!NearbyNode nodes;
    Array!Collected collected;
    Array!ExpandOutput outputs;
    ExpandOutput serial;
    Array!uint candidates;
    Array!KeepKind kinds;
    Array!BlockCounts blocks;
    Array!uint around;
    Array!uint chain;
    Array!(Array!DeriveStep) derived;
    Array!DeriveStep claimed;
    Bits rederived;
    KeepJob keeping;
    Point!float startPoint;
    size_t front;
    size_t missingHead;
    size_t unknownHead;
    size_t paintedHead;
    size_t keptBlocks;
    size_t keptNodes;
    size_t reexpandedNodes;
    float coshThreshold = 0;
    float coshInner = 0;
    double paintingMs = 0;
    uint generation;
    uint paintsThisAdvance;
    KeepPass keepPass;

    void release() {
        nodes.release();
        collected.release();
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
        foreach (ref batch; derived.slice()) {
            batch.release();
        }
        derived.release();
        claimed.release();
        rederived.release();
    }

    MaybeIndex!uint indexOf(uint slot) const {
        if (slot < collected.length && collected.ptr[slot].stamp == generation) {
            return MaybeIndex!uint.of(collected.ptr[slot].position);
        } else {
            return MaybeIndex!uint.init;
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
        return isKeeping() || front < nodes.length || hasSerialWork();
    }

    bool isKeeping() const {
        return keepPass != KeepPass.none;
    }

    void begin(ref Graph graph, Position start, float distance, float inner) {
        coshThreshold = coshf(distance + NODE_RADIUS);
        coshInner = coshf(inner);
        keepPass = KeepPass.none;
        nodes.clear();
        serial.clear();
        front = 0;
        missingHead = 0;
        unknownHead = 0;
        paintedHead = 0;
        generation += 1;
        startPoint = start.local * Point!float.origin();
        collect(graph, NearbyNode(Motion!float.identity(), graph.slotOf(start.node).value));
    }

    void reserveStamps(ref const Graph graph) {
        if (collected.length < graph.slotCount) {
            collected.resize(graph.slotCount);
        }
    }

    void collect(ref Graph graph, NearbyNode node) {
        reserveStamps(graph);
        collected.ptr[node.slot] = Collected(generation, cast(uint) nodes.length);
        nodes.append(node);
    }

    bool claim(uint slot) {
        uint before = atomicExchange(cast(shared(uint)*) &collected.ptr[slot].stamp, generation);
        return before != generation;
    }

    bool collectAround(ref Graph graph, uint cameraSlot, Point!float camera, float reach) {
        MaybeIndex!uint first = indexOf(cameraSlot);
        if (!first.exists) {
            return false;
        } else {
            bool wasBuilding = isBuilding();
            walkAround(graph, first.value, camera, coshf(reach));
            if (!wasBuilding) {
                front = nodes.length;
            }
            return true;
        }
    }

    void walkAround(ref Graph graph, uint first, Point!float camera, float coshReach) {
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
                    MaybeIndex!uint found = indexOf(neighbor);
                    uint position = cast(uint) nodes.length;
                    if (found.exists) {
                        position = found.value;
                    } else {
                        collect(graph, NearbyNode(transform, neighbor));
                    }
                    if (!isListed(around.slice(), position)) {
                        around.append(position);
                    }
                }
            }
            head += 1;
        }
    }

    void advance(ref Graph graph, Deadline deadline, Executor executor) {
        while (outputs.length < executor.workers) {
            outputs.append(ExpandOutput.init);
        }
        paintsThisAdvance = 0;
        while (!isKeeping() && isBuilding()) {
            if (hasSerialWork()) {
                Drain drained = drainSerial(graph, deadline, executor);
                if (drained == Drain.stalled) {
                    return;
                }
            } else {
                reserveStamps(graph);
                ExpandJob expansion = ExpandJob(&this, &graph, front, nodes.length);
                ParallelJob job = ParallelJob(&expandBatch, &expansion, deadline, (expansion.end - front + EXPAND_BATCH - 1) / EXPAND_BATCH);
                executor.run(&job);
                front = lowerOf(front + job.count * EXPAND_BATCH, expansion.end);
                gather();
            }
            double now = nowMilliseconds();
            if (deadline.hasPassed(now)) {
                return;
            }
        }
    }

    void gather() {
        foreach (ref output; outputs.slice()) {
            foreach (found; output.found.slice()) {
                collected.ptr[found.slot].position = cast(uint) nodes.length;
                nodes.append(found);
            }
            serial.missing.appendAll(output.missing.slice());
            serial.unknown.appendAll(output.unknown.slice());
            output.clear();
        }
    }

    Drain drainSerial(ref Graph graph, Deadline deadline, Executor executor) {
        double now = nowMilliseconds();
        while (hasSerialWork() && !deadline.hasPassed(now)) {
            if (missingHead < serial.missing.length) {
                MissingSide missing = serial.missing.ptr[missingHead];
                missingHead += 1;
                NearbyNode current = nodes.ptr[missing.index];
                uint neighbor = graph.ensureNeighborSlot(current.slot, missing.side);
                if (!indexOf(neighbor).exists) {
                    collect(graph, NearbyNode(current.transform * missing.side.mirror, neighbor));
                }
            } else if (unknownHead >= paintedHead && paintsThisAdvance > 0 && deadline.hasPassed(now + paintingMs)) {
                return Drain.stalled;
            } else if (unknownHead >= paintedHead) {
                double start = nowMilliseconds();
                paintUnknownAhead(graph, executor);
                paintingMs = nowMilliseconds() - start;
                paintsThisAdvance += 1;
            } else {
                NearbyNode current = nodes.ptr[serial.unknown.ptr[unknownHead]];
                unknownHead += 1;
                NodeContent content = graph.ensureContentAt(current.slot);
                if (content == NodeContent.holding) {
                    expandAll(graph, current);
                }
            }
            now = nowMilliseconds();
        }
        if (!hasSerialWork()) {
            serial.clear();
            missingHead = 0;
            unknownHead = 0;
            paintedHead = 0;
        }
        return Drain.flowing;
    }

    bool isWithinReach(NearbyNode current, Face side) const {
        Vec4!float mirroredOrigin = side.mirror.m.column(3);
        return !(-startPoint.minkowski(current.transform * mirroredOrigin) > coshThreshold);
    }

    bool isInner(NearbyNode current) const {
        return !(-startPoint.minkowski(current.transform * Vec4!float.origin()) > coshInner);
    }

    bool isOpenSide(ref const Graph graph, NearbyNode current, Face side) const {
        MaybeIndex!uint existing = graph.neighborSlot(current.slot, side);
        return (!existing.exists || collected.ptr[existing.value].stamp != generation) && isWithinReach(current, side);
    }

    bool hasOpenSide(ref const Graph graph, NearbyNode current) const {
        uint side = 0;
        while (side < FACE_COUNT && !isOpenSide(graph, current, cast(Face) side)) {
            side += 1;
        }
        return side < FACE_COUNT;
    }

    void narrow(float distance) {
        coshThreshold = coshf(distance + NODE_RADIUS);
    }

    void expandKnown(ref const Graph graph, NearbyNode current, uint index, ref ExpandOutput output) {
        foreach (sideIndex; 0 .. FACE_COUNT) {
            Face side = cast(Face) sideIndex;
            if (isOpenSide(graph, current, side)) {
                MaybeIndex!uint existing = graph.neighborSlot(current.slot, side);
                if (existing.exists) {
                    bool claimed = claim(existing.value);
                    if (claimed) {
                        output.found.append(NearbyNode(current.transform * side.mirror, existing.value));
                    }
                } else {
                    output.missing.append(MissingSide(index, side));
                }
            }
        }
    }

    void expandAll(ref Graph graph, NearbyNode current) {
        foreach (sideIndex; 0 .. FACE_COUNT) {
            Face side = cast(Face) sideIndex;
            MaybeIndex!uint existing = graph.neighborSlot(current.slot, side);
            if ((!existing.exists || !indexOf(existing.value).exists) && isWithinReach(current, side)) {
                uint neighbor = graph.ensureNeighborSlot(current.slot, side);
                if (!indexOf(neighbor).exists) {
                    collect(graph, NearbyNode(current.transform * side.mirror, neighbor));
                }
            }
        }
    }

    void beginFrom(ref const NearbyScratch finished, ref Graph graph, Point!float camera, float distance, float inner) {
        float moved = camera.distance(finished.startPoint);
        float frontier = acoshf(finished.coshThreshold) - 2 * FACE_DISTANCE - moved;
        float coshFrontier = coshf(higherOf(frontier, 0.0f));
        kinds.resize(finished.nodes.length);
        blocks.resize((finished.nodes.length + KEEP_BLOCK - 1) / KEEP_BLOCK);
        nodes.clear();
        serial.clear();
        front = 0;
        missingHead = 0;
        unknownHead = 0;
        paintedHead = 0;
        generation += 1;
        reserveStamps(graph);
        keeping = KeepJob.init;
        keeping.count = finished.nodes.length;
        keeping.camera = camera;
        keeping.previous = finished.startPoint;
        keeping.coshReach = coshf(distance + NODE_RADIUS);
        keeping.coshPreviousReach = finished.coshThreshold;
        keeping.coshFrontier = coshFrontier;
        keeping.coshInner = coshf(inner);
        keepPass = KeepPass.sorting;
        keptBlocks = 0;
    }

    void continueKeeping(ref const NearbyScratch finished, Deadline deadline, Executor executor) {
        while (isKeeping()) {
            keeping.from = finished.nodes.ptr;
            keeping.scratch = &this;
            keeping.blocks = blocks.ptr;
            keeping.base = keptBlocks;
            ParallelJob job = ParallelJob(&sortKept, &keeping, deadline, blocks.length - keptBlocks);
            if (keepPass == KeepPass.copying) {
                job.run = &copyKept;
            }
            executor.run(&job);
            keptBlocks += job.count;
            if (keptBlocks == blocks.length) {
                finishPass();
            } else {
                break;
            }
        }
    }

    void finishPass() {
        if (keepPass == KeepPass.sorting) {
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
            keepPass = KeepPass.copying;
            keptBlocks = 0;
        } else {
            coshThreshold = keeping.coshReach;
            coshInner = keeping.coshInner;
            startPoint = keeping.camera;
            front = keeping.keptTotal;
            keptNodes += front;
            reexpandedNodes += nodes.length - front;
            keepPass = KeepPass.none;
        }
    }

    void rederive(ref const Graph graph, uint firstSlot, Point!float center, float radius, Executor executor) {
        uint first = indexOf(firstSlot).value;
        rederived.cover(nodes.length);
        rederived.clearAll();
        chain.clear();
        chain.append(first);
        rederived.set(first);
        size_t levelStart = 0;
        while (levelStart < chain.length) {
            DeriveJob job = DeriveJob(&this, &graph, center, coshf(radius), levelStart, chain.length);
            size_t batches = (job.end - job.first + DERIVE_BATCH - 1) / DERIVE_BATCH;
            while (derived.length < batches) {
                derived.append(Array!DeriveStep.init);
            }
            ParallelJob finding = ParallelJob(&findDerived, &job, Deadline.init, batches);
            executor.run(&finding);
            claimed.clear();
            foreach (batch; derived.slice()[0 .. batches]) {
                foreach (step; batch.slice()) {
                    if (!rederived.has(step.index)) {
                        rederived.set(step.index);
                        chain.append(step.index);
                        claimed.append(step);
                    }
                }
            }
            ParallelJob applying = ParallelJob(&applyDerived, &job, Deadline.init, claimed.length);
            executor.run(&applying);
            levelStart = job.end;
        }
    }

    void rebase(ref const Graph graph, uint cameraSlot, Motion!float toFrame, float radius, Executor executor) {
        nodes.ptr[indexOf(cameraSlot).value].transform = Motion!float.identity();
        rederive(graph, cameraSlot, Point!float.origin(), radius, executor);
        RebaseJob job = RebaseJob(nodes.ptr, &rederived, nodes.length, toFrame);
        ParallelJob rebasing = ParallelJob(&rebaseBlock, &job, Deadline.init, (nodes.length + KEEP_BLOCK - 1) / KEEP_BLOCK);
        executor.run(&rebasing);
        startPoint = toFrame * startPoint;
    }

    NearbyNode[] collectAll(ref Graph graph, Position start, float distance) {
        begin(graph, start, distance, distance + NODE_RADIUS);
        advance(graph, Deadline.init, Executor.init);
        return nodes.slice();
    }
}

NodeContent ensureContentAt(ref Graph graph, uint slot) {
    if (graph.nodeAt(slot).content == NodeContent.unknown) {
        bool holding = graph.probeMayHoldContent(slot);
        if (holding) {
            graph.nodeAt(slot).content = NodeContent.holding;
        } else {
            graph.nodeAt(slot).content = NodeContent.empty;
        }
    }
    return graph.nodeAt(slot).content;
}
