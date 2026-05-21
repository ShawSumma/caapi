module common.traversal;

import std.math : cosh;
import common.dodeca : Side, sideReflection, BOUNDING_SPHERE_RADIUS;
import common.graph : Graph, NodeId;
import common.math : MIsometry, MPoint;

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
}

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
    MPoint!float startP = startLocal * MPoint!float.origin();

    while (queueFront < queue.length) {
        Pending current = queue[queueFront];
        queueFront++;

        result ~= NearbyNode(current.id, current.transform);

        foreach (sideIdx; 0 .. 12) {
            Side side = cast(Side) sideIdx;
            NodeId existing = graph.neighbor(current.id, side);
            if (existing != NodeId.init && existing in visited) {
                continue;
            }
            MIsometry!float neighborTransform = current.transform * sideReflection(side);
            MPoint!float neighborP = neighborTransform * MPoint!float.origin();
            if (-startP.mip(neighborP.vec) > coshThreshold) {
                continue;
            }
            NodeId neighbor = graph.ensureNeighbor(current.id, side);
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
