module common.traversal;

import core.stdc.math : coshf;
import common.array : Array;
import common.dodeca : BOUNDING_SPHERE_RADIUS, SIDE_COUNT, Side, sideReflection;
import common.graph : Graph, NO_SLOT, NodeId;
import common.math : MIsometry, MPoint, MVector;

enum size_t DEFAULT_NODE_CREATION_BUDGET = 1024;

struct NearbyNode {
    NodeId id;
    MIsometry!float transform;
    uint slot = NO_SLOT;
}

struct NearbyScratch {
    Array!NearbyNode nodes;
    Array!uint stamp;
    uint generation;
    bool creationCapped;

    void release() {
        nodes.release();
        stamp.release();
    }
}

NearbyNode[] ensureAndCollectNearby(NearbyScratch* scratch, Graph* graph, NodeId startNode, MIsometry!float startLocal, float distance, size_t maxNewNodes) {
    float coshThreshold = coshf(distance + BOUNDING_SPHERE_RADIUS);
    size_t created = 0;
    scratch.creationCapped = false;
    scratch.nodes.clear();
    scratch.generation += 1;
    uint generation = scratch.generation;
    if (scratch.stamp.length < graph.nodeCount) {
        scratch.stamp.resize(graph.nodeCount);
    }
    uint startSlot = graph.slotOf(startNode);
    if (startSlot != NO_SLOT) {
        scratch.nodes.append(NearbyNode(startNode, MIsometry!float.identity(), startSlot));
        scratch.stamp.ptr[startSlot] = generation;
        MPoint!float startPoint = startLocal * MPoint!float.origin();
        size_t front = 0;
        while (front < scratch.nodes.length) {
            NearbyNode current = scratch.nodes.ptr[front];
            front += 1;
            foreach (sideIndex; 0 .. SIDE_COUNT) {
                Side side = cast(Side) sideIndex;
                uint neighbor = graph.neighborSlot(current.slot, side);
                if (neighbor == NO_SLOT || scratch.stamp.ptr[neighbor] != generation) {
                    MIsometry!float reflection = sideReflection(side);
                    MVector!float reflectedOrigin = MVector!float(reflection.mat.data[3][0], reflection.mat.data[3][1], reflection.mat.data[3][2], reflection.mat.data[3][3]);
                    if (!(-startPoint.mip(current.transform * reflectedOrigin) > coshThreshold)) {
                        MIsometry!float neighborTransform = current.transform * reflection;
                        if (neighbor == NO_SLOT) {
                            if (created >= maxNewNodes) {
                                scratch.creationCapped = true;
                            } else {
                                uint before = graph.nodeCount;
                                neighbor = graph.ensureNeighborSlot(current.slot, side);
                                created += graph.nodeCount - before;
                                if (scratch.stamp.length < graph.nodeCount) {
                                    scratch.stamp.resize(graph.nodeCount);
                                }
                            }
                        }
                        if (neighbor != NO_SLOT && scratch.stamp.ptr[neighbor] != generation) {
                            scratch.stamp.ptr[neighbor] = generation;
                            scratch.nodes.append(NearbyNode(graph.idAt(neighbor), neighborTransform, neighbor));
                        }
                    }
                }
            }
        }
    }
    return scratch.nodes.slice();
}
