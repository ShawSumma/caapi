module common.worldgen.spawn;

import core.stdc.math : coshf;
import base.array : Array;
import base.vector3 : Vec3, scaled;
import common.graph : Graph, ROOT_NODE;
import common.node : ChunkSlot;
import common.position : Position;
import common.traversal : NodeVisit, isVisited;
import common.worldgen.generation : ChunkParams;
import common.worldgen.horospheres : ensureGravityAt;
import geometry.honeycomb : CORNER_COUNT, CUBE_RADIUS, Corner, FACE_COUNT, Face, NODE_RADIUS, cubeCenter, mirror;
import geometry.lorentz : Motion, Point, Vec4;

Array!ChunkSlot collectChunksNear(ref Graph graph, Position position, float distance) {
    float nodeThreshold = coshf(distance + NODE_RADIUS + CUBE_RADIUS);
    float chunkThreshold = coshf(distance + CUBE_RADIUS);
    Vec4!float point = (position.local * Point!float.origin()).v;
    Array!ChunkSlot chunks;
    Array!NodeVisit visits;
    visits.append(NodeVisit(graph.slotOf(position.node).value, Motion!float.identity()));
    size_t front = 0;
    while (front < visits.length) {
        NodeVisit visit = visits.ptr[front];
        front += 1;
        Vec4!float localPoint = visit.inverse * point;
        foreach (index; 0 .. CORNER_COUNT) {
            Corner corner = cast(Corner) index;
            if (!(-localPoint.minkowski(corner.cubeCenter.v) > chunkThreshold)) {
                chunks.append(ChunkSlot(visit.slot, corner));
            }
        }
        foreach (index; 0 .. FACE_COUNT) {
            Face side = cast(Face) index;
            Motion!float neighborInverse = side.mirror * visit.inverse;
            if (!((neighborInverse * point).c[3] > nodeThreshold)) {
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

bool probeEveryChunkClear(ref Graph graph, const(ChunkSlot)[] chunks) {
    uint unproven = 0;
    foreach (chunk; chunks) {
        ChunkParams params = ChunkParams.make(graph.view, chunk.slot, chunk.corner);
        if (!params.isProvenClear()) {
            unproven += 1;
        }
    }
    return unproven == 0;
}

bool probeRegionClear(ref Graph graph, Position position, float distance) {
    Array!ChunkSlot chunks = graph.collectChunksNear(position, distance);
    bool clear = graph.probeEveryChunkClear(chunks.slice());
    chunks.release();
    return clear;
}

Position findSpawnPosition(ref Graph graph, float bodyReach) {
    float rootAltitude = graph.horospheres.gravitySign() * graph.ensureState(graph.slotOf(ROOT_NODE).value).surface.distanceTo(Point!float.origin());
    Vec3!float up = graph.ensureGravityAt(Position.origin()).up;
    float altitude = bodyReach;
    Position candidate = graph.ensurePositionAtRise(up, altitude - rootAltitude);
    bool clear = graph.probeRegionClear(candidate, bodyReach);
    while (!clear) {
        altitude += bodyReach;
        candidate = graph.ensurePositionAtRise(up, altitude - rootAltitude);
        clear = graph.probeRegionClear(candidate, bodyReach);
    }
    return candidate;
}

Position ensurePositionAtRise(ref Graph graph, Vec3!float up, float rise) {
    Position result = graph.ensureNormalized(Position(ROOT_NODE, Motion!float.shift(up.scaled(rise))));
    graph.ensureState(graph.slotOf(result.node).value);
    return result;
}
