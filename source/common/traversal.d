module common.traversal;

import core.atomic : atomicExchange;
import core.stdc.math : acoshf, coshf, fabs;
import base.array : Array;
import base.clock : nowMilliseconds;
import base.parallel : Executor, ParallelJob;
import common.graph : Graph, NO_SLOT, NodeContent;
import common.position : Position;
import common.worldgen.sky : mayHoldContent;
import geometry.honeycomb : FACE_COUNT, FACE_DISTANCE, Face, NODE_RADIUS, mirror;
import geometry.lorentz : Motion, Point, Vec4;

enum double NO_DEADLINE = double.infinity;
enum uint NOT_COLLECTED = uint.max;
enum size_t EXPAND_BATCH = 256;
enum size_t PAINT_BATCH = 256;
enum size_t DERIVE_BATCH = 64;

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

enum double SHELL_FLOOR = 0.01;
enum double SHELL_ROUNDING = 64 * float.epsilon;
enum ubyte DROPPED = 0;
enum ubyte KEPT = 1;
enum ubyte FRONTIER = 2;
enum size_t KEEP_BLOCK = 4096;

struct BlockCounts {
    uint kept;
    uint frontier;
}

enum KeepPass : ubyte {
    none,
    sorting,
    copying,
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
        return (block + 1) * KEEP_BLOCK < count ? (block + 1) * KEEP_BLOCK : count;
    }

    // Most of a set lies near its edge, so this runs for most nodes. The products with each column are taken once,
    // leaving four multiplications per neighbor instead of a matrix product.
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

// A transform made or moved while far from the frame origin carries float error of about cosh^2 of that distance
// times float epsilon in its center's Minkowski norm, and later rebases keep that error exactly. Once the frame comes
// near, the error is far more than rounding at the new distance allows, the center no longer places the node, and
// expanding from it pulls a far region into the set.
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

void sortKept(void* context, size_t item, uint worker) {
    KeepJob* job = cast(KeepJob*) context;
    size_t block = job.base + item;
    BlockCounts counts;
    foreach (index; block * KEEP_BLOCK .. job.end(block)) {
        Motion!float transform = job.from[index].transform;
        Vec4!float center = transform * Vec4!float.origin();
        float product = -job.camera.minkowski(center);
        bool isNewlyInner = !(product > job.coshInner) && -job.previous.minkowski(center) > job.coshInner;
        ubyte kind = KEPT;
        if (product > job.coshReach || isOffHyperboloid(center)) {
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

void copyKept(void* context, size_t item, uint worker) {
    KeepJob* job = cast(KeepJob*) context;
    size_t block = job.base + item;
    NearbyScratch* scratch = job.scratch;
    uint kept = job.blocks[block].kept;
    uint frontier = job.keptTotal + job.blocks[block].frontier;
    foreach (index; block * KEEP_BLOCK .. job.end(block)) {
        ubyte kind = scratch.kinds.ptr[index];
        if (kind != DROPPED) {
            uint at = kind == KEPT ? kept++ : frontier++;
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

// The shell just outside the radius is as large as everything inside it, so its neighbors are turned away on their
// center alone before the whole transform is worked out.
void findDerived(void* context, size_t batch, uint worker) {
    DeriveJob* job = cast(DeriveJob*) context;
    NearbyScratch* scratch = job.scratch;
    Array!DeriveStep* found = &scratch.derived.ptr[batch];
    found.clear();
    size_t start = job.first + batch * DERIVE_BATCH;
    size_t end = start + DERIVE_BATCH < job.end ? start + DERIVE_BATCH : job.end;
    foreach (position; start .. end) {
        uint from = scratch.chain.ptr[position];
        NearbyNode current = scratch.nodes.ptr[from];
        foreach (sideIndex; 0 .. FACE_COUNT) {
            uint neighbor = job.graph.neighborSlot(current.slot, cast(Face) sideIndex);
            uint index = neighbor == NO_SLOT ? NOT_COLLECTED : scratch.indexOf(neighbor);
            if (index != NOT_COLLECTED && !scratch.isRederived.ptr[index] && !(-job.center.minkowski(current.transform * MIRRORED_ORIGINS[sideIndex]) > job.coshRadius)) {
                found.append(DeriveStep(index, from, cast(Face) sideIndex));
            }
        }
    }
}

void applyDerived(void* context, size_t item, uint worker) {
    NearbyScratch* scratch = (cast(DeriveJob*) context).scratch;
    DeriveStep step = scratch.claimed.ptr[item];
    scratch.nodes.ptr[step.index].transform = scratch.nodes.ptr[step.from].transform * step.side.mirror;
}

// Where a slot sits in the set, valid while its stamp is the set's generation; the two are read together on every
// lookup, so they share a cache line.
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
    Array!ubyte kinds;
    Array!BlockCounts blocks;
    Array!uint around;
    Array!uint chain;
    Array!(Array!DeriveStep) derived;
    Array!DeriveStep claimed;
    Array!bool isRederived;
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
    KeepPass keepPass;
    bool hasPainted;

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
        isRederived.release();
    }

    uint indexOf(uint slot) const {
        if (slot < collected.length && collected.ptr[slot].stamp == generation) {
            return collected.ptr[slot].position;
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
        collect(graph, NearbyNode(Motion!float.identity(), graph.slotOf(start.node)));
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
        return atomicExchange(cast(shared(uint)*) &collected.ptr[slot].stamp, generation) != generation;
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
                            collect(graph, NearbyNode(transform, neighbor));
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
        while (!isKeeping() && isBuilding() && !isLate) {
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
                collected.ptr[found.slot].position = cast(uint) nodes.length;
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
                    collect(graph, NearbyNode(current.transform * missing.side.mirror, neighbor));
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
            if ((existing == NO_SLOT || collected.ptr[existing].stamp != generation) && isWithinReach(current, side)) {
                if (existing == NO_SLOT) {
                    output.missing.append(MissingSide(index, side));
                } else if (claim(existing)) {
                    output.found.append(NearbyNode(current.transform * side.mirror, existing));
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
                    collect(graph, NearbyNode(current.transform * side.mirror, neighbor));
                }
            }
        }
    }

    // Starts a set from the finished one, keeping its nodes still in reach; continueKeeping sorts and copies them.
    void beginFrom(ref const NearbyScratch finished, ref Graph graph, Point!float camera, float distance, float inner) {
        float moved = camera.distance(finished.startPoint);
        float frontier = acoshf(finished.coshThreshold) - 2 * FACE_DISTANCE - moved;
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
        keeping = KeepJob(null, finished.nodes.length, 0, null, null, camera, finished.startPoint, coshf(distance + NODE_RADIUS), finished.coshThreshold, frontier > 0 ? coshf(frontier) : 1, coshf(inner));
        keepPass = KeepPass.sorting;
        keptBlocks = 0;
    }

    // At full reach the finished set holds millions of nodes, too many to sort and copy in one frame, so it goes a
    // slice of blocks per call. Until it is done the finished set must keep its transforms and order; it may grow, so
    // its nodes are found again on each call.
    void continueKeeping(ref const NearbyScratch finished, double deadline, Executor executor) {
        while (isKeeping()) {
            keeping.from = finished.nodes.ptr;
            keeping.scratch = &this;
            keeping.blocks = blocks.ptr;
            keeping.base = keptBlocks;
            ParallelJob job = ParallelJob(keepPass == KeepPass.sorting ? &sortKept : &copyKept, &keeping, deadline, blocks.length - keptBlocks);
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

    // A breadth-first walk out from the first slot that works each transform out again from the one it was reached
    // from. Each level's neighbors are found in parallel, then claimed in the order of the level, which picks the same
    // node each was reached from as a walk one node at a time would.
    void rederive(ref const Graph graph, uint firstSlot, Point!float center, float radius, Executor executor) {
        uint first = indexOf(firstSlot);
        isRederived.clear();
        isRederived.resize(nodes.length);
        chain.clear();
        chain.append(first);
        isRederived.ptr[first] = true;
        size_t levelStart = 0;
        while (levelStart < chain.length) {
            DeriveJob job = DeriveJob(&this, &graph, center, coshf(radius), levelStart, chain.length);
            size_t batches = (job.end - job.first + DERIVE_BATCH - 1) / DERIVE_BATCH;
            while (derived.length < batches) {
                derived.append(Array!DeriveStep.init);
            }
            ParallelJob finding = ParallelJob(&findDerived, &job, NO_DEADLINE, batches);
            executor.run(&finding);
            claimed.clear();
            foreach (batch; derived.slice()[0 .. batches]) {
                foreach (step; batch.slice()) {
                    if (!isRederived.ptr[step.index]) {
                        isRederived.ptr[step.index] = true;
                        chain.append(step.index);
                        claimed.append(step);
                    }
                }
            }
            ParallelJob applying = ParallelJob(&applyDerived, &job, NO_DEADLINE, claimed.length);
            executor.run(&applying);
            levelStart = job.end;
        }
    }

    void rebase(ref const Graph graph, uint cameraSlot, Motion!float toFrame, float radius, Executor executor) {
        nodes.ptr[indexOf(cameraSlot)].transform = Motion!float.identity();
        rederive(graph, cameraSlot, Point!float.origin(), radius, executor);
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

enum ubyte TEST_DIMENSION = 4;
enum float TEST_SET_RADIUS = 3.0f;
enum float TEST_DERIVE_RADIUS = 2.5f;
enum uint TEST_WORKERS = 3;
immutable float[3] TEST_DRIFT = [0.3f, -0.2f, 0.1f];

bool takesNoTask(void* context, uint worker) {
    return false;
}

bool isSameMotion(Motion!float a, Motion!float b) {
    bool isSame = true;
    foreach (column; 0 .. 4) {
        foreach (row; 0 .. 4) {
            isSame = isSame && a.m.c[column][row] == b.m.c[column][row];
        }
    }
    return isSame;
}

// Rederiving on every worker has to work each transform out from the same node as one thread does.
unittest {
    import core.stdc.stdlib : free;
    import base.parallel : TaskSource, WorkerPool;
    import common.worldgen.generation : Worldgen;

    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.makeTerrain());
    NearbyScratch scratch;
    scratch.collectAll(graph, Position.origin(), TEST_SET_RADIUS);
    Motion!float drift = Motion!float.shift(TEST_DRIFT);
    foreach (ref node; scratch.nodes.slice()) {
        node.transform = drift * node.transform;
    }
    scratch.nodes.ptr[0].transform = Motion!float.identity();
    Array!NearbyNode drifted;
    drifted.appendAll(scratch.nodes.slice());
    uint first = scratch.nodes.ptr[0].slot;
    scratch.rederive(graph, first, Point!float.origin(), TEST_DERIVE_RADIUS, Executor.init);
    Array!NearbyNode alone;
    alone.appendAll(scratch.nodes.slice());
    scratch.nodes.clear();
    scratch.nodes.appendAll(drifted.slice());
    WorkerPool* pool = WorkerPool.make(TEST_WORKERS, TaskSource(&takesNoTask, null));
    scratch.rederive(graph, first, Point!float.origin(), TEST_DERIVE_RADIUS, Executor(pool));
    pool.release();
    free(pool);
    size_t changed = 0;
    foreach (index, node; scratch.nodes.slice()) {
        assert(isSameMotion(node.transform, alone.ptr[index].transform));
        changed += !isSameMotion(node.transform, drifted.ptr[index].transform);
    }
    assert(changed > FACE_COUNT);
    drifted.release();
    alone.release();
    scratch.release();
    graph.release();
}
