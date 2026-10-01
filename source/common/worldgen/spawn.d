module common.worldgen.spawn;

import core.stdc.math : coshf;
import common.array : Array;
import common.character_controller.controller : getRelativeUp;
import common.dodeca : BOUNDING_SPHERE_RADIUS, CHUNK_BOUNDING_SPHERE_RADIUS, SIDE_COUNT, Side, VERTEX_COUNT, Vertex, sideReflection, vertexChunkBoundingSphereCenter;
import common.graph : Graph, ROOT_NODE, createGraph;
import common.graph_collision : NodeVisit, containsSlot;
import common.math : MIsometry, MPoint, MVector;
import common.node : ChunkId;
import common.proto : Position, originPosition;
import common.vector3 : scale3;
import common.worldgen.generation : ChunkParams, chunkProvenClear, createChunkParams;

enum float TEST_BODY_REACH = 0.1f;
enum float TEST_ALTITUDE_TOLERANCE = 1e-4f;

void collectChunksNear(Graph* graph, Position position, float distance, Array!ChunkId* chunks) {
    float nodeThreshold = coshf(distance + BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS);
    float chunkThreshold = coshf(distance + CHUNK_BOUNDING_SPHERE_RADIUS);
    MVector!float point = (position.local * MPoint!float.origin()).vec;
    Array!NodeVisit visits;
    visits.append(NodeVisit(graph.slotOf(position.node), MIsometry!float.identity()));
    size_t front = 0;
    while (front < visits.length) {
        NodeVisit visit = visits.ptr[front];
        front += 1;
        MVector!float localPoint = visit.inverse * point;
        foreach (vertexIndex; 0 .. VERTEX_COUNT) {
            Vertex vertex = cast(Vertex) vertexIndex;
            if (!(-localPoint.mip(vertexChunkBoundingSphereCenter(vertex).vec) > chunkThreshold)) {
                chunks.append(ChunkId(graph.idAt(visit.slot), vertex));
            }
        }
        foreach (sideIndex; 0 .. SIDE_COUNT) {
            Side side = cast(Side) sideIndex;
            MIsometry!float neighborInverse = sideReflection(side) * visit.inverse;
            if (!((neighborInverse * point).data[3] > nodeThreshold)) {
                uint neighbor = graph.ensureNeighborSlot(visit.slot, side);
                if (!containsSlot(visits.slice(), neighbor)) {
                    visits.append(NodeVisit(neighbor, neighborInverse));
                }
            }
        }
    }
    visits.release();
}

bool regionProvenClear(Graph* graph, bool flat, Position position, float distance) {
    Array!ChunkId chunks;
    collectChunksNear(graph, position, distance, &chunks);
    bool clear = true;
    foreach (chunk; chunks.slice()) {
        ChunkParams params = createChunkParams(graph, chunk, flat);
        if (!chunkProvenClear(&params)) {
            clear = false;
        }
    }
    chunks.release();
    return clear;
}

Position clearSpawnPosition(Graph* graph, bool flat, float bodyReach) {
    graph.ensureNodeState(ROOT_NODE);
    float[3] up = getRelativeUp(graph, originPosition());
    float rootAltitude = graph.nodeState(ROOT_NODE).surface.distanceTo(MPoint!float.origin());
    float altitude = bodyReach;
    Position result = positionAtAltitude(graph, up, altitude - rootAltitude);
    while (!regionProvenClear(graph, flat, result, bodyReach)) {
        altitude += bodyReach;
        result = positionAtAltitude(graph, up, altitude - rootAltitude);
    }
    return result;
}

Position positionAtAltitude(Graph* graph, float[3] up, float rise) {
    Position result = originPosition();
    result.local = MIsometry!float.translationAlong(scale3(up, rise));
    result.node = graph.ensureNormalizedTransform(result.node, &result.local);
    graph.ensureNodeState(result.node);
    return result;
}

unittest {
    Graph graph = createGraph(12);
    Position spawn = clearSpawnPosition(&graph, true, TEST_BODY_REACH);
    float altitude = graph.nodeState(spawn.node).surface.distanceTo(spawn.local * MPoint!float.origin());
    assert(altitude > TEST_BODY_REACH - TEST_ALTITUDE_TOLERANCE);
    assert(regionProvenClear(&graph, true, spawn, TEST_BODY_REACH));
    graph.release();
}
