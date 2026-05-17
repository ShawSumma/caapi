module common.traversal;

import common.dodeca;
import common.graph;
import common.math;
import common.node;
import std.math : cosh;

/// Ensure all nodes exist whose bounding spheres are within distance of start
void ensureNearby(ref Graph graph, NodeId startNode, MIsometry!float startLocal, float distance) {
    float maxNodeCenterDistance = distance + BOUNDING_SPHERE_RADIUS;

    // BFS
    struct Pending {
        NodeId node;
        MIsometry!float transform;
    }

    Pending[] queue;
    bool[NodeId] visited;

    queue ~= Pending(startNode, MIsometry!float.identity());
    visited[startNode] = true;
    auto startP = startLocal * MPoint!float.origin();

    while (queue.length > 0) {
        auto current = queue[0];
        queue = queue[1 .. $];

        foreach (sideIdx; 0 .. SIDE_COUNT) {
            auto side = cast(Side) sideIdx;
            auto refl = sideReflection(side);
            auto neighborTransform = current.transform * refl;
            auto neighborP = neighborTransform * MPoint!float.origin();
            if (-startP.mip(neighborP.vec) > cosh(maxNodeCenterDistance)) {
                continue;
            }
            auto neighbor = graph.ensureNeighbor(current.node, side);
            if (neighbor == NodeId.init) continue;
            if (neighbor in visited) continue;
            visited[neighbor] = true;
            queue ~= Pending(neighbor, neighborTransform);
        }
    }
}

/// A node and its transform relative to a reference
struct NearbyNode {
    NodeId id;
    MIsometry!float transform;
}

/// Compute transforms of all nodes whose bounding spheres lie within distance of start
NearbyNode[] nearbyNodes(const ref Graph graph, NodeId startNode, MIsometry!float startLocal, float distance) {
    float maxNodeCenterDistance = distance + BOUNDING_SPHERE_RADIUS;

    struct Pending {
        NodeId id;
        MIsometry!float transform;
    }

    NearbyNode[] result;
    Pending[] queue;
    bool[NodeId] visited;

    queue ~= Pending(startNode, MIsometry!float.identity());
    visited[startNode] = true;
    auto startP = startLocal * MPoint!float.origin();

    while (queue.length > 0) {
        auto current = queue[0];
        queue = queue[1 .. $];

        result ~= NearbyNode(current.id, current.transform);

        foreach (sideIdx; 0 .. SIDE_COUNT) {
            auto side = cast(Side) sideIdx;
            auto refl = sideReflection(side);
            auto neighborTransform = current.transform * refl;
            auto neighborP = neighborTransform * MPoint!float.origin();
            if (-startP.mip(neighborP.vec) > cosh(maxNodeCenterDistance)) {
                continue;
            }
            auto n = graph.neighbor(current.id, side);
            if (n == NodeId.init) continue;
            if (n in visited) continue;
            visited[n] = true;
            queue ~= Pending(n, neighborTransform);
        }
    }

    return result;
}
