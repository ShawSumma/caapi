module common.traversal;

import common.array : Array;
import common.hash_map : HashMap;
import common.dodeca : Side, sideReflection, BOUNDING_SPHERE_RADIUS;
import common.graph : Graph, NodeId, NO_SLOT;
import common.math : MIsometry, MPoint, MVector, cosh;

struct PendingNode {
    NodeId id;
    MIsometry!float transform;
}

void ensureNearby(
    ref Graph graph,
    NodeId startNode,
    MIsometry!float startLocal,
    float distance,
    size_t maxNewNodes = 256,
) {
    float maxNodeCenterDistance = distance + BOUNDING_SPHERE_RADIUS;
    float coshThreshold = cosh(maxNodeCenterDistance);

    Array!PendingNode queue;
    HashMap!(NodeId, bool) visited;
    scope(exit) {
        queue.release();
        visited.release();
    }
    queue.reserve(4096);
    size_t queueFront = 0;
    size_t created = 0;

    queue.push(PendingNode(startNode, MIsometry!float.identity()));
    visited.insert(startNode, true);
    MPoint!float startP = startLocal * MPoint!float.origin();

    while (queueFront < queue.length()) {
        PendingNode current = queue[queueFront];
        queueFront = queueFront + 1;

        foreach (sideIdx; 0 .. 12) {
            Side side = cast(Side) sideIdx;
            NodeId existing = graph.neighbor(current.id, side);
            if (existing != NodeId.init) {
                if (visited.contains(existing)) {
                    continue;
                }
                MIsometry!float neighborTransform =
                    current.transform * sideReflection(side);
                MPoint!float neighborP = neighborTransform * MPoint!float.origin();
                if (-startP.mip(neighborP.vec) > coshThreshold) {
                    continue;
                }
                visited.insert(existing, true);
                queue.push(PendingNode(existing, neighborTransform));
            } else if (created < maxNewNodes) {
                MIsometry!float neighborTransform =
                    current.transform * sideReflection(side);
                MPoint!float neighborP = neighborTransform * MPoint!float.origin();
                if (-startP.mip(neighborP.vec) > coshThreshold) {
                    continue;
                }
                NodeId neighbor = graph.ensureNeighbor(current.id, side);
                if (neighbor == NodeId.init || visited.contains(neighbor)) {
                    continue;
                }
                created = created + 1;
                visited.insert(neighbor, true);
                queue.push(PendingNode(neighbor, neighborTransform));
            }
        }
    }
}

struct NearbyNode {
    NodeId id;
    MIsometry!float transform;
    uint slot = NO_SLOT;
}

// Reusable scratch buffers so the per-frame traversal doesn't reallocate the
// node array or the visited set. The single `nodes` array doubles as the BFS
// queue and the result (every queued node is eventually popped, so they hold
// the same elements in the same order). Visited tracking is a per-slot stamp
// array: comparing against the current generation avoids both hashing and
// clearing between runs.
struct NearbyScratch {
    Array!NearbyNode nodes;
    Array!uint stamp;
    uint generation;
    // True when the last collection ran out of node-creation budget; the
    // caller should collect again soon to finish expanding the frontier.
    bool creationCapped;

    void release() {
        nodes.release();
        stamp.release();
    }
}

NearbyNode[] ensureAndCollectNearby(
    ref NearbyScratch scratch,
    ref Graph graph,
    NodeId startNode,
    MIsometry!float startLocal,
    float distance,
    size_t maxNewNodes = 1024,
) {
    float coshThreshold = cosh(distance + BOUNDING_SPHERE_RADIUS);
    size_t created = 0;
    scratch.creationCapped = false;

    scratch.nodes.clear();
    scratch.generation = scratch.generation + 1;
    uint gen = scratch.generation;
    if (scratch.stamp.length() < graph.slotCount()) {
        scratch.stamp.resize(graph.slotCount());
    }

    uint startSlot = graph.slotOf(startNode);
    if (startSlot == NO_SLOT) {
        return scratch.nodes.slice();
    }
    scratch.nodes.push(
        NearbyNode(startNode, MIsometry!float.identity(), startSlot),
    );
    scratch.stamp[startSlot] = gen;
    MPoint!float startP = startLocal * MPoint!float.origin();

    size_t front = 0;
    while (front < scratch.nodes.length()) {
        NearbyNode current = scratch.nodes[front];
        front = front + 1;

        foreach (sideIdx; 0 .. 12) {
            Side side = cast(Side) sideIdx;
            uint neighbor = graph.neighborSlot(current.slot, side);
            if (neighbor != NO_SLOT && scratch.stamp[neighbor] == gen) {
                continue;
            }
            // Cull on the translation column alone (one matrix-vector product)
            // before paying for the full transform of an accepted node.
            MIsometry!float refl = sideReflection(side);
            MVector!float reflOrigin = MVector!float(
                refl.mat.data[3][0], refl.mat.data[3][1],
                refl.mat.data[3][2], refl.mat.data[3][3]);
            MVector!float neighborOrigin = current.transform * reflOrigin;
            if (-startP.mip(neighborOrigin) > coshThreshold) {
                continue;
            }
            MIsometry!float neighborTransform = current.transform * refl;
            if (neighbor == NO_SLOT) {
                // Creating a node can add several slots; grow the stamps
                // after. Creation is budgeted per call: entering unexplored
                // territory expands the graph across several rebuilds instead
                // of flooding one frame (BFS order creates nearest first).
                if (created >= maxNewNodes) {
                    scratch.creationCapped = true;
                    continue;
                }
                uint before = graph.slotCount();
                neighbor = graph.ensureNeighborSlot(current.slot, side);
                created = created + (graph.slotCount() - before);
                if (scratch.stamp.length() < graph.slotCount()) {
                    scratch.stamp.resize(graph.slotCount());
                }
                if (neighbor == NO_SLOT || scratch.stamp[neighbor] == gen) {
                    continue;
                }
            }
            scratch.stamp[neighbor] = gen;
            scratch.nodes.push(
                NearbyNode(graph.idAt(neighbor), neighborTransform, neighbor),
            );
        }
    }

    return scratch.nodes.slice();
}
