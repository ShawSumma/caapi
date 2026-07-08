module common.traversal;

import std.math : cosh;
import common.dodeca : Side, sideReflection, BOUNDING_SPHERE_RADIUS;
import common.graph : Graph, NodeId, NO_SLOT;
import common.math : MIsometry, MPoint, MVector;

void ensureNearby(ref Graph graph, NodeId startNode, MIsometry!float startLocal, float distance, size_t maxNewNodes = 256) {
    float maxNodeCenterDistance = distance + BOUNDING_SPHERE_RADIUS;
    float coshThreshold = cosh(maxNodeCenterDistance);

    struct Pending {
        NodeId node;
        MIsometry!float transform;
    }

    Pending[] queue;
    queue.reserve(4096);
    size_t queueFront = 0;
    bool[NodeId] visited;
    size_t created = 0;

    queue ~= Pending(startNode, MIsometry!float.identity());
    visited[startNode] = true;
    MPoint!float startP = startLocal * MPoint!float.origin();

    while (queueFront < queue.length) {
        Pending current = queue[queueFront];
        queueFront++;

        foreach (sideIdx; 0 .. 12) {
            Side side = cast(Side) sideIdx;
            NodeId existing = graph.neighbor(current.node, side);
            if (existing != NodeId.init) {
                if (existing in visited) {
                    continue;
                }
                MIsometry!float neighborTransform = current.transform * sideReflection(side);
                MPoint!float neighborP = neighborTransform * MPoint!float.origin();
                if (-startP.mip(neighborP.vec) > coshThreshold) {
                    continue;
                }
                visited[existing] = true;
                queue ~= Pending(existing, neighborTransform);
            }
            else if (created < maxNewNodes) {
                MIsometry!float neighborTransform = current.transform * sideReflection(side);
                MPoint!float neighborP = neighborTransform * MPoint!float.origin();
                if (-startP.mip(neighborP.vec) > coshThreshold) {
                    continue;
                }
                NodeId neighbor = graph.ensureNeighbor(current.node, side);
                if (neighbor == NodeId.init || neighbor in visited) {
                    continue;
                }
                created++;
                visited[neighbor] = true;
                queue ~= Pending(neighbor, neighborTransform);
            }
        }
    }
}

NearbyNode[] collectNearby(ref Graph graph, NodeId startNode, MIsometry!float startLocal, float distance) {
    float maxNodeCenterDistance = distance + BOUNDING_SPHERE_RADIUS;
    float coshThreshold = cosh(maxNodeCenterDistance);

    struct Pending {
        NodeId id;
        MIsometry!float transform;
    }

    NearbyNode[] result;
    result.reserve(4096);
    Pending[] queue;
    queue.reserve(4096);
    size_t queueFront = 0;
    bool[NodeId] visited;

    queue ~= Pending(startNode, MIsometry!float.identity());
    visited[startNode] = true;
    MPoint!float startP = startLocal * MPoint!float.origin();

    while (queueFront < queue.length) {
        Pending current = queue[queueFront];
        queueFront++;

        result ~= NearbyNode(current.id, current.transform);

        foreach (sideIdx; 0 .. 12) {
            Side side = cast(Side) sideIdx;
            NodeId n = graph.neighbor(current.id, side);
            if (n == NodeId.init || n in visited) {
                continue;
            }
            MIsometry!float neighborTransform = current.transform * sideReflection(side);
            MPoint!float neighborP = neighborTransform * MPoint!float.origin();
            if (-startP.mip(neighborP.vec) > coshThreshold) {
                continue;
            }
            visited[n] = true;
            queue ~= Pending(n, neighborTransform);
        }
    }

    return result;
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
    NearbyNode[] nodes;
    uint[] stamp;
    uint generation;
    // True when the last collection ran out of node-creation budget; the
    // caller should collect again soon to finish expanding the frontier.
    bool creationCapped;
}

NearbyNode[] ensureAndCollectNearby(
    ref NearbyScratch scratch,
    ref Graph graph,
    NodeId startNode,
    MIsometry!float startLocal,
    float distance,
    size_t maxNewNodes = 1024
) {
    float coshThreshold = cosh(distance + BOUNDING_SPHERE_RADIUS);
    size_t created = 0;
    scratch.creationCapped = false;

    scratch.nodes.length = 0;
    scratch.nodes.assumeSafeAppend();
    scratch.generation++;
    uint gen = scratch.generation;
    if (scratch.stamp.length < graph.slotCount()) {
        scratch.stamp.length = graph.slotCount();
    }

    uint startSlot = graph.slotOf(startNode);
    if (startSlot == NO_SLOT) {
        return scratch.nodes;
    }
    scratch.nodes ~= NearbyNode(startNode, MIsometry!float.identity(), startSlot);
    scratch.stamp[startSlot] = gen;
    MPoint!float startP = startLocal * MPoint!float.origin();

    size_t front = 0;
    while (front < scratch.nodes.length) {
        NearbyNode current = scratch.nodes[front];
        front++;

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
                created += graph.slotCount() - before;
                if (scratch.stamp.length < graph.slotCount()) {
                    scratch.stamp.length = graph.slotCount();
                }
                if (neighbor == NO_SLOT || scratch.stamp[neighbor] == gen) {
                    continue;
                }
            }
            scratch.stamp[neighbor] = gen;
            scratch.nodes ~= NearbyNode(graph.idAt(neighbor), neighborTransform, neighbor);
        }
    }

    return scratch.nodes;
}

NearbyNode[] ensureAndCollectNearby(ref Graph graph, NodeId startNode, MIsometry!float startLocal, float distance) {
    NearbyScratch scratch;
    return ensureAndCollectNearby(scratch, graph, startNode, startLocal, distance);
}

NearbyNode[] nearbyNodes(const ref Graph graph, NodeId startNode, MIsometry!float startLocal, float distance) {
    float maxNodeCenterDistance = distance + BOUNDING_SPHERE_RADIUS;
    float coshThreshold = cosh(maxNodeCenterDistance);

    struct Pending {
        NodeId id;
        MIsometry!float transform;
    }

    NearbyNode[] result;
    result.reserve(4096);
    Pending[] queue;
    queue.reserve(4096);
    size_t queueFront = 0;
    bool[NodeId] visited;

    queue ~= Pending(startNode, MIsometry!float.identity());
    visited[startNode] = true;
    MPoint!float startP = startLocal * MPoint!float.origin();

    while (queueFront < queue.length) {
        Pending current = queue[queueFront];
        queueFront++;

        result ~= NearbyNode(current.id, current.transform);

        foreach (sideIdx; 0 .. 12) {
            Side side = cast(Side) sideIdx;
            MIsometry!float refl = sideReflection(side);
            MIsometry!float neighborTransform = current.transform * refl;
            MPoint!float neighborP = neighborTransform * MPoint!float.origin();
            if (-startP.mip(neighborP.vec) > coshThreshold) {
                continue;
            }
            NodeId n = graph.neighbor(current.id, side);
            if (n == NodeId.init) {
                continue;
            }
            if (n in visited) {
                continue;
            }
            visited[n] = true;
            queue ~= Pending(n, neighborTransform);
        }
    }

    return result;
}
