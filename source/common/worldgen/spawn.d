module common.worldgen.spawn;

import core.stdc.math : coshf;
import common.array : Array;
import common.character.controller : relativeUp;
import common.collision.graph : NodeVisit, isVisited;
import common.dodeca : BOUNDING_SPHERE_RADIUS, CHUNK_BOUNDING_SPHERE_RADIUS, SIDE_COUNT, Side, VERTEX_COUNT, Vertex, chunkBoundingSphereCenter, reflection;
import common.graph : Graph, ROOT_NODE;
import common.math : MIsometry, MPoint, MVector;
import common.node : ChunkSlot;
import common.proto : Position;
import common.vector3 : scaled;
import common.worldgen.generation : ChunkParams;

enum float TEST_BODY_REACH = 0.1f;
enum float TEST_ALTITUDE_TOLERANCE = 1e-4f;
enum ubyte TEST_DIMENSION = 12;

Array!ChunkSlot collectChunksNear(ref Graph graph, Position position, float distance) {
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

bool isEveryChunkProvenClear(ref Graph graph, const(ChunkSlot)[] chunks, bool isFlat) {
    size_t index = 0;
    while (index < chunks.length && ChunkParams.make(graph, chunks[index].slot, chunks[index].vertex, isFlat).isProvenClear()) {
        index += 1;
    }
    return index == chunks.length;
}

bool isRegionProvenClear(ref Graph graph, bool isFlat, Position position, float distance) {
    Array!ChunkSlot chunks = graph.collectChunksNear(position, distance);
    bool isClear = graph.isEveryChunkProvenClear(chunks.slice(), isFlat);
    chunks.release();
    return isClear;
}

Position clearSpawnPosition(ref Graph graph, bool isFlat, float bodyReach) {
    graph.ensureNodeState(ROOT_NODE);
    float[3] up = graph.relativeUp(Position.origin());
    float rootAltitude = graph.nodeState(ROOT_NODE).surface.distanceTo(MPoint!float.origin());
    return graph.clearPositionFrom(isFlat, up, rootAltitude, bodyReach, bodyReach);
}

Position clearPositionFrom(ref Graph graph, bool isFlat, float[3] up, float rootAltitude, float altitude, float bodyReach) {
    Position candidate = graph.positionAtRise(up, altitude - rootAltitude);
    immutable bool isClear = graph.isRegionProvenClear(isFlat, candidate, bodyReach);
    if (isClear) {
        return candidate;
    } else {
        return graph.clearPositionFrom(isFlat, up, rootAltitude, altitude + bodyReach, bodyReach);
    }
}

Position positionAtRise(ref Graph graph, float[3] up, float rise) {
    Position result = graph.ensureNormalized(Position(ROOT_NODE, MIsometry!float.fromDisplacement(up.scaled(rise))));
    graph.ensureNodeState(result.node);
    return result;
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION);
    Position spawn = graph.clearSpawnPosition(true, TEST_BODY_REACH);
    float altitude = graph.nodeState(spawn.node).surface.distanceTo(spawn.local * MPoint!float.origin());
    assert(altitude > TEST_BODY_REACH - TEST_ALTITUDE_TOLERANCE);
    assert(graph.isRegionProvenClear(true, spawn, TEST_BODY_REACH));
    graph.release();
}
