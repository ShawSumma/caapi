module unit.spawn;

import common.graph : Graph;
import common.position : Position;
import common.worldgen.generation : PlaneWorld, Worldgen;
import common.worldgen.spawn : findSpawnPosition, probeRegionClear;
import geometry.lorentz : Point;

enum float BODY_REACH = 0.1f;
enum float ALTITUDE_TOLERANCE = 1e-4f;
enum ubyte DIMENSION = 12;

unittest {
    Graph graph = Graph.make(DIMENSION, Worldgen.fromPlane(PlaneWorld(0)));
    Position spawn = graph.findSpawnPosition(BODY_REACH);
    float altitude = graph.stateAt(graph.slotOf(spawn.node).value).surface.distanceTo(spawn.local * Point!float.origin());
    assert(altitude > BODY_REACH - ALTITUDE_TOLERANCE);
    bool clear = graph.probeRegionClear(spawn, BODY_REACH);
    assert(clear);
    graph.release();
}
