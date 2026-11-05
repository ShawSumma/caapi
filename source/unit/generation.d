module unit.generation;

import base.array : Array;
import common.graph : Graph, NodeId;
import common.view : GraphView;
import common.worldgen.generation : NodeState, Worldgen;
import common.worldgen.plane : Plane;
import geometry.honeycomb : FACE_COUNT, Face;

enum ubyte DIMENSION = 12;

bool isSamePlane(Plane a, Plane b) {
    return a.up == b.up && a.height == b.height;
}

bool isSameState(NodeState a, NodeState b) {
    return isSamePlane(a.surface, b.surface) && isSamePlane(a.reference, b.reference) && a.climate.broad == b.climate.broad && a.climate.local == b.climate.local && a.climate.heat == b.climate.heat && a.climate.wetness == b.climate.wetness && a.climate.strata == b.climate.strata && a.climate.ruggedness == b.climate.ruggedness;
}

unittest {
    Graph graph = Graph.make(DIMENSION, Worldgen.makeTerrain());
    foreach (side; 0 .. FACE_COUNT) {
        uint neighbor = graph.ensureNeighborSlot(graph.anchorSlot, cast(Face) side);
        foreach (outer; 0 .. FACE_COUNT) {
            graph.ensureNeighborSlot(neighbor, cast(Face) outer);
        }
    }
    uint region = graph.slotCount;
    GraphView view = GraphView.over(graph);
    Array!NodeState worked;
    Array!NodeId ids;
    foreach (slot; 0 .. region) {
        foreach (side; 0 .. FACE_COUNT) {
            foreach (outer; 0 .. FACE_COUNT) {
                uint far = view.ensureNeighborSlot(view.ensureNeighborSlot(slot, cast(Face) side), cast(Face) outer);
                worked.append(view.ensureState(far));
                ids.append(view.idAt(far));
            }
        }
    }
    assert(graph.slotCount == region && view.nodes.length > 0);
    size_t index = 0;
    foreach (slot; 0 .. region) {
        foreach (side; 0 .. FACE_COUNT) {
            foreach (outer; 0 .. FACE_COUNT) {
                uint far = graph.ensureNeighborSlot(graph.ensureNeighborSlot(slot, cast(Face) side), cast(Face) outer);
                const(NodeState)* state = graph.ensureState(far);
                assert(graph.idAt(far) == ids.ptr[index] && isSameState(*state, worked.ptr[index]));
                index += 1;
            }
        }
    }
    view.release();
    worked.release();
    ids.release();
    graph.release();
}
