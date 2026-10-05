module common.worldgen.tower;

import common.array : Array;
import common.dodeca : SIDE_COUNT, Side, isAdjacentTo, opposite, reflection;
import common.graph : Graph, NodeId, ROOT_NODE;
import common.material : Material;
import common.math : MPoint;
import common.worldgen.building : Building, NO_CELL, NO_CLEARANCE, StairSearch;
import common.worldgen.generation : NodeState, NodeStateKind, NodeStateRoad, SplitMix, StructureKind, StructureWorld, Worldgen, WorldgenKind;

enum ulong TOWER_RARITY = 48;
enum uint RARITY_SHIFT = 40;
enum float MIN_BASE_ELEVATION = -3.0f;
enum float MAX_BASE_ELEVATION = 3.0f;
enum float MAX_TOWER_ALTITUDE = 12.0f;
enum float MIN_LEVEL_RISE = 0.1f;
enum uint MIN_TRUNK_NODES = 2;
enum uint TRUNK_NODE_CHOICES = 2;
enum uint MIN_BRANCH_NODES = 1;
enum uint BRANCH_NODE_CHOICES = 2;
enum uint MIN_FORKS = 1;
enum uint FORK_CHOICES = 2;
enum uint FORK_SHIFT = 8;
enum uint BRANCH_SHIFT = 16;
enum uint PALETTE_SHIFT = 24;
enum uint RING_CHOICE_SHIFT = 32;
enum ubyte TEST_DIMENSION = 12;

struct TowerPalette {
    Material wall;
    Material floor;
    Material spire;
}

immutable TowerPalette[4] TOWER_PALETTES = [
    TowerPalette(Material.concrete, Material.concrete, Material.steel),
    TowerPalette(Material.whiteBrick, Material.greyBrick, Material.steel),
    TowerPalette(Material.sandstone, Material.woodPlanks, Material.steel),
    TowerPalette(Material.greyBrick, Material.concrete, Material.marble),
];

enum TowerSymbol : ubyte {
    none,
    foundation,
    base,
    segment,
}

struct TowerPart {
    Side down;
    TowerSymbol symbol;
    ubyte remaining;
    ubyte forks;
    ubyte branchNodes;
    ubyte palette;

    static TowerPart fromBaseBits(ulong bits) {
        return TowerPart(
            Side.a,
            TowerSymbol.base,
            cast(ubyte)(MIN_TRUNK_NODES - 1 + bits % TRUNK_NODE_CHOICES),
            cast(ubyte)(MIN_FORKS + (bits >> FORK_SHIFT) % FORK_CHOICES),
            cast(ubyte)(MIN_BRANCH_NODES + (bits >> BRANCH_SHIFT) % BRANCH_NODE_CHOICES),
            cast(ubyte)((bits >> PALETTE_SHIFT) % TOWER_PALETTES.length),
        );
    }

    bool isPresent() const {
        return symbol != TowerSymbol.none;
    }

    bool isGrowing() const {
        return symbol == TowerSymbol.base || symbol == TowerSymbol.segment;
    }

    TowerPart foundation() const {
        return TowerPart(Side.a, TowerSymbol.foundation, 0, 0, 0, palette);
    }

    TowerPart childAcross(Side face) const {
        if (remaining > 0) {
            return TowerPart(face, TowerSymbol.segment, cast(ubyte)(remaining - 1), forks, branchNodes, palette);
        } else {
            return TowerPart(face, TowerSymbol.segment, cast(ubyte)(branchNodes - 1), cast(ubyte)(forks - 1), branchNodes, palette);
        }
    }

    ushort productionFaces(ulong bits) const {
        Side straight = down.opposite;
        if (!isGrowing()) {
            return 0;
        } else if (remaining > 0) {
            return faceBit(straight);
        } else if (forks > 0) {
            return faceBit(straight) | chosenRing(straight, bits);
        } else {
            return 0;
        }
    }
}

struct NodeStructure {
    TowerPart part;
    ushort incoming;
    ushort outgoing;

    static NodeStructure fromNode(ref Graph graph, uint slot) {
        NodeState state = *graph.ensureNodeStateAt(slot);
        if (graph.worldgen.kind == WorldgenKind.plane) {
            return NodeStructure.init;
        } else if (state.kind == NodeStateKind.sky && graph.isTowerBase(slot)) {
            TowerPart part = TowerPart.fromBaseBits(graph.towerBits(slot));
            return NodeStructure(part, faceBit(Side.a), state.risingFaces(part.productionFaces(graph.towerBits(slot))));
        } else if (state.kind == NodeStateKind.land && graph.isTowerBase(graph.ensureNeighborSlot(slot, Side.a))) {
            TowerPart base = TowerPart.fromBaseBits(graph.towerBits(graph.ensureNeighborSlot(slot, Side.a)));
            return NodeStructure(base.foundation(), faceBit(Side.a), 0);
        } else if ((state.kind == NodeStateKind.sky || state.kind == NodeStateKind.deepSky) && state.altitude() <= MAX_TOWER_ALTITUDE) {
            return graph.claimedStructure(slot, state);
        } else {
            return NodeStructure.init;
        }
    }

    bool isPresent() const {
        return part.isPresent();
    }
}

ushort faceBit(Side side) {
    return cast(ushort)(1u << side);
}

ushort ringFaces(Side straight) {
    ushort ring = 0;
    foreach (index; 0 .. SIDE_COUNT) {
        if ((cast(Side) index).isAdjacentTo(straight)) {
            ring |= faceBit(cast(Side) index);
        }
    }
    return ring;
}

ushort chosenRing(Side straight, ulong bits) {
    ushort ring = ringFaces(straight);
    ushort chosen = ring & cast(ushort)(bits >> RING_CHOICE_SHIFT);
    if (chosen == 0) {
        return ring & cast(ushort)(-cast(int) ring);
    } else {
        return chosen;
    }
}

float altitude(ref const NodeState state) {
    return state.surface.distanceTo(MPoint!float.origin());
}

float neighborAltitude(ref const NodeState state, Side side) {
    return state.surface.distanceTo(side.reflection * MPoint!float.origin());
}

ushort risingFaces(ref const NodeState state, ushort candidates) {
    float own = state.altitude();
    ushort rising = 0;
    foreach (index; 0 .. SIDE_COUNT) {
        Side side = cast(Side) index;
        float above = state.neighborAltitude(side);
        if ((candidates & faceBit(side)) != 0 && above > own + MIN_LEVEL_RISE && above <= MAX_TOWER_ALTITUDE) {
            rising |= faceBit(side);
        }
    }
    return rising;
}

ulong towerBits(ref const Graph graph, uint slot) {
    return SplitMix(graph.idAt(slot).spice()).next();
}

bool isTowerBase(ref Graph graph, uint slot) {
    NodeState state = *graph.ensureNodeStateAt(slot);
    if (state.kind != NodeStateKind.sky) {
        return false;
    } else if (graph.worldgen.kind == WorldgenKind.structure) {
        return graph.idAt(slot) == graph.worldgen.structure.base;
    } else {
        bool isOnRoadLine = state.road == NodeStateRoad.east || state.road == NodeStateRoad.west;
        bool isLevelGround = state.enviro.maxElevation >= MIN_BASE_ELEVATION && state.enviro.maxElevation <= MAX_BASE_ELEVATION;
        return !isOnRoadLine && isLevelGround && (graph.towerBits(slot) >> RARITY_SHIFT) % TOWER_RARITY == 0;
    }
}

NodeStructure claimedStructure(ref Graph graph, uint slot, NodeState state) {
    float own = state.altitude();
    TowerPart part;
    ushort incoming = 0;
    foreach (index; 0 .. SIDE_COUNT) {
        Side side = cast(Side) index;
        if (state.neighborAltitude(side) < own - MIN_LEVEL_RISE) {
            NodeStructure below = graph.ensureStructureAt(graph.ensureNeighborSlot(slot, side));
            if ((below.outgoing & faceBit(side)) != 0) {
                incoming |= faceBit(side);
                if (!part.isPresent()) {
                    part = below.part.childAcross(side);
                }
            }
        }
    }
    return NodeStructure(part, incoming, state.risingFaces(part.productionFaces(graph.towerBits(slot))));
}

uint structureBaseSlot(ref Graph graph) {
    uint sky = graph.ensureNeighborSlot(graph.slotOf(ROOT_NODE), Side.a);
    return graph.ensureNeighborSlot(sky, firstSideAmong(ringFaces(Side.a)));
}

Side firstSideAmong(ushort faces) {
    uint index = 0;
    while (index < SIDE_COUNT && (faces & faceBit(cast(Side) index)) == 0) {
        index += 1;
    }
    assert(index < SIDE_COUNT);
    return cast(Side) index;
}

uint popCount(ushort bits) {
    uint count = 0;
    foreach (index; 0 .. SIDE_COUNT) {
        if ((bits & (1u << index)) != 0) {
            count += 1;
        }
    }
    return count;
}

Array!uint towerNodes(ref Graph graph) {
    Array!uint nodes;
    nodes.append(graph.slotOf(graph.worldgen.structure.base));
    size_t front = 0;
    while (front < nodes.length) {
        uint slot = nodes.ptr[front];
        NodeStructure structure = graph.ensureStructureAt(slot);
        foreach (index; 0 .. SIDE_COUNT) {
            if ((structure.outgoing & faceBit(cast(Side) index)) != 0) {
                nodes.append(graph.ensureNeighborSlot(slot, cast(Side) index));
            }
        }
        front += 1;
    }
    return nodes;
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.fromStructure(StructureWorld(NodeId.init, StructureKind.tower)));
    Array!uint nodes = graph.towerNodes();
    uint forks = 0;
    foreach (slot; nodes.slice()) {
        NodeStructure structure = graph.ensureStructureAt(slot);
        assert(structure.isPresent());
        if (popCount(structure.outgoing) > 1) {
            forks += 1;
        }
    }
    assert(nodes.length >= MIN_TRUNK_NODES + 2);
    assert(forks >= MIN_FORKS);
    nodes.release();
    graph.release();
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.fromStructure(StructureWorld(NodeId.init, StructureKind.tower)));
    Array!uint nodes = graph.towerNodes();
    foreach (slot; nodes.slice()) {
        NodeStructure structure = graph.ensureStructureAt(slot);
        Building building = Building.make(structure, graph.nodeAt(slot).state.surface, graph.layout);
        assert(building.connected == structure.outgoing);
        StairSearch search = StairSearch.make(building.shape, building.stamps.ptr);
        foreach (step; building.route.slice()) {
            int support = search.below(step);
            assert(support == NO_CELL || building.materialAt(building.shape.vertexOf(support), building.shape.cellOf(support), Material.none) != Material.none);
        }
        foreach (index; 1 .. building.route.length) {
            int top = search.clearance(building.route.ptr[index - 1]);
            assert(top != NO_CLEARANCE);
            foreach (height; 0 .. top + 1) {
                int cell = search.raised(building.route.ptr[index - 1], height);
                assert(cell == NO_CELL || building.materialAt(building.shape.vertexOf(cell), building.shape.cellOf(cell), Material.none) == Material.none);
            }
        }
        search.release();
        building.release();
    }
    nodes.release();
    graph.release();
}

unittest {
    foreach (index; 0 .. SIDE_COUNT) {
        TowerPart part = TowerPart(cast(Side) index, TowerSymbol.segment, 0, 1, 2, 0);
        ushort faces = part.productionFaces(0);
        assert((faces & faceBit(part.down.opposite)) != 0);
        assert((faces & ~(faceBit(part.down.opposite) | ringFaces(part.down.opposite))) == 0);
        assert(faces != faceBit(part.down.opposite));
    }
}
