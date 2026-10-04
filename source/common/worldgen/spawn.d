module common.worldgen.spawn;

import core.stdc.math : coshf;
import common.array : Array;
import common.character_controller.controller : relativeUp;
import common.dodeca : BOUNDING_SPHERE_RADIUS, CHUNK_BOUNDING_SPHERE_RADIUS, SIDE_COUNT, Side, VERTEX_COUNT, Vertex, chunkBoundingSphereCenter, reflection;
import common.graph : Graph, ROOT_NODE;
import common.graph_collision : NodeVisit, isVisited;
import common.math : MIsometry, MPoint, MVector;
import common.node : ChunkSlot;
import common.proto : Position;
import common.vector3 : scale3;
import common.worldgen.generation : ChunkParams;

enum float TEST_BODY_REACH = 0.1f;
enum float TEST_ALTITUDE_TOLERANCE = 1e-4f;

Array!ChunkSlot collectChunksNear(Graph* graph, Position position, float distance) {
    float nodeThreshold = coshf(distance + BOUNDING_SPHERE_RADIUS + CHUNK_BOUNDING_SPHERE_RADIUS);
    float chunkThreshold = coshf(distance + CHUNK_BOUNDING_SPHERE_RADIUS);
    MVector!float point = (position.local * MPoint!float.origin()).vec;
    Array!ChunkSlot chunks;
    Array!NodeVisit visits;
    visits.append(NodeVisit(graph.slotOf(position.node), MIsometry!float.identity()));
    size_t front = 0;
    while (front < visits.length) {
        NodeVisit visit = visits.ptr[front];
        front += 1;
        MVector!float localPoint = visit.inverse * point;
        foreach (vertexIndex; 0 .. VERTEX_COUNT) {
            Vertex vertex = cast(Vertex) vertexIndex;
            if (!(-localPoint.mip(vertex.chunkBoundingSphereCenter.vec) > chunkThreshold)) {
                chunks.append(ChunkSlot(visit.slot, vertex));
            }
        }
        foreach (sideIndex; 0 .. SIDE_COUNT) {
            Side side = cast(Side) sideIndex;
            MIsometry!float neighborInverse = side.reflection * visit.inverse;
            if (!((neighborInverse * point).data[3] > nodeThreshold)) {
                uint neighbor = graph.ensureNeighborSlot(visit.slot, side);
                if (!isVisited(visits.slice(), neighbor)) {
                    visits.append(NodeVisit(neighbor, neighborInverse));
                }
            }
        }
    }
    visits.release();
    return chunks;
}

bool isEveryChunkProvenClear(Graph* graph, const(ChunkSlot)[] chunks, bool isFlat) {
    foreach (chunk; chunks) {
        ChunkParams params = ChunkParams.make(graph, chunk.slot, chunk.vertex, isFlat);
        if (!params.isProvenClear()) {
            return false;
        }
    }
    return true;
}

bool isRegionProvenClear(Graph* graph, bool isFlat, Position position, float distance) {
    Array!ChunkSlot chunks = collectChunksNear(graph, position, distance);
    immutable bool isClear = isEveryChunkProvenClear(graph, chunks.slice(), isFlat);
    chunks.release();
    return isClear;
}

Position clearSpawnPosition(Graph* graph, bool isFlat, float bodyReach) {
    graph.ensureNodeState(ROOT_NODE);
    float[3] up = graph.relativeUp(Position.origin());
    float rootAltitude = graph.nodeState(ROOT_NODE).surface.distanceTo(MPoint!float.origin());
    return clearPositionFrom(graph, isFlat, up, rootAltitude, bodyReach, bodyReach);
}

Position clearPositionFrom(Graph* graph, bool isFlat, float[3] up, float rootAltitude, float altitude, float bodyReach) {
    Position candidate = positionAtRise(graph, up, altitude - rootAltitude);
    immutable bool isClear = isRegionProvenClear(graph, isFlat, candidate, bodyReach);
    if (isClear) {
        return candidate;
    } else {
        return clearPositionFrom(graph, isFlat, up, rootAltitude, altitude + bodyReach, bodyReach);
    }
}

Position positionAtRise(Graph* graph, float[3] up, float rise) {
    Position result = graph.ensureNormalized(Position(ROOT_NODE, MIsometry!float.translationAlong(up.scale3(rise))));
    graph.ensureNodeState(result.node);
    return result;
}

unittest {
    Graph graph = Graph.make(12);
    Position spawn = clearSpawnPosition(&graph, true, TEST_BODY_REACH);
    float altitude = graph.nodeState(spawn.node).surface.distanceTo(spawn.local * MPoint!float.origin());
    assert(altitude > TEST_BODY_REACH - TEST_ALTITUDE_TOLERANCE);
    assert(isRegionProvenClear(&graph, true, spawn, TEST_BODY_REACH));
    graph.release();
}
