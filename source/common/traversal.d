module common.traversal;

import common.dodeca;
import common.graph;
import common.math;
import common.node;
import std.math : cosh;

/// Ensure nodes exist within distance, with a per-call budget on new node creation.
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
    auto startP = startLocal * MPoint!float.origin();

    while (queueFront < queue.length) {
        auto current = queue[queueFront];
        queueFront++;

        foreach (sideIdx; 0 .. SIDE_COUNT) {
            auto side = cast(Side) sideIdx;
            auto existing = graph.neighbor(current.node, side);
            if (existing != NodeId.init) {
                if (existing in visited) {
                    continue;
                }
                auto neighborTransform = current.transform * sideReflection(side);
                auto neighborP = neighborTransform * MPoint!float.origin();
                if (-startP.mip(neighborP.vec) > coshThreshold) {
                    continue;
                }
                visited[existing] = true;
                queue ~= Pending(existing, neighborTransform);
            } else if (created < maxNewNodes) {
                auto neighborTransform = current.transform * sideReflection(side);
                auto neighborP = neighborTransform * MPoint!float.origin();
                if (-startP.mip(neighborP.vec) > coshThreshold) {
                    continue;
                }
                auto neighbor = graph.ensureNeighbor(current.node, side);
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

/// Collect already-existing nodes within distance (no node creation)
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
    auto startP = startLocal * MPoint!float.origin();

    while (queueFront < queue.length) {
        auto current = queue[queueFront];
        queueFront++;

        result ~= NearbyNode(current.id, current.transform);

        foreach (sideIdx; 0 .. SIDE_COUNT) {
            auto side = cast(Side) sideIdx;
            auto n = graph.neighbor(current.id, side);
            if (n == NodeId.init || n in visited) {
                continue;
            }
            auto neighborTransform = current.transform * sideReflection(side);
            auto neighborP = neighborTransform * MPoint!float.origin();
            if (-startP.mip(neighborP.vec) > coshThreshold) {
                continue;
            }
            visited[n] = true;
            queue ~= Pending(n, neighborTransform);
        }
    }

    return result;
}

/// A node and its transform relative to a reference
struct NearbyNode {
    NodeId id;
    MIsometry!float transform;
}

/// Combined: ensure neighbors + collect nearby nodes in one BFS pass
NearbyNode[] ensureAndCollectNearby(ref Graph graph, NodeId startNode, MIsometry!float startLocal, float distance) {
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
    auto startP = startLocal * MPoint!float.origin();

    while (queueFront < queue.length) {
        auto current = queue[queueFront];
        queueFront++;

        result ~= NearbyNode(current.id, current.transform);

        foreach (sideIdx; 0 .. SIDE_COUNT) {
            auto side = cast(Side) sideIdx;
            auto existing = graph.neighbor(current.id, side);
            if (existing != NodeId.init && existing in visited) {
                continue;
            }
            auto neighborTransform = current.transform * sideReflection(side);
            auto neighborP = neighborTransform * MPoint!float.origin();
            if (-startP.mip(neighborP.vec) > coshThreshold) {
                continue;
            }
            auto neighbor = graph.ensureNeighbor(current.id, side);
            if (neighbor == NodeId.init) {
                continue;
            }
            if (neighbor in visited) {
                continue;
            }
            visited[neighbor] = true;
            queue ~= Pending(neighbor, neighborTransform);
        }
    }

    return result;
}

/// Compute transforms of all nodes whose bounding spheres lie within distance of start
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
    auto startP = startLocal * MPoint!float.origin();

    while (queueFront < queue.length) {
        auto current = queue[queueFront];
        queueFront++;

        result ~= NearbyNode(current.id, current.transform);

        foreach (sideIdx; 0 .. SIDE_COUNT) {
            auto side = cast(Side) sideIdx;
            auto refl = sideReflection(side);
            auto neighborTransform = current.transform * refl;
            auto neighborP = neighborTransform * MPoint!float.origin();
            if (-startP.mip(neighborP.vec) > coshThreshold) {
                continue;
            }
            auto n = graph.neighbor(current.id, side);
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
