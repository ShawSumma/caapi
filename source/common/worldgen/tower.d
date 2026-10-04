module common.worldgen.tower;

import core.stdc.math : atan2f, atanhf, coshf, cosf, fabsf, fmodf, sinhf;
import common.array : Array;
import common.dodeca : SIDE_COUNT, Side, faceDirection, faceDistance, faceReference, isAdjacentTo, opposite, reflection;
import common.graph : Graph, NodeId, ROOT_NODE;
import common.material : Material;
import common.math : MPoint;
import common.vector3 : cross, dot, magnitude, minus, scaled;
import common.worldgen.generation : NodeState, NodeStateKind, NodeStateRoad, SplitMix, WorldgenKind, WorldgenSettings;

enum ulong TOWER_RARITY = 48;
enum ulong TOWER_SEED_MULTIPLIER = 0x2545f4914f6cdd1d;
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
enum float OUTER_RADIUS = 0.3f;
enum float WALL_THICKNESS = 0.09f;
enum float FLOOR_THICKNESS = 0.09f;
enum uint FLOORS_PER_FACE_DISTANCE = 5;
enum float WINDOW_HALF_HEIGHT_PER_FLOOR = 0.22f;
enum float WINDOW_COLUMNS = 8.0f;
enum float WINDOW_COLUMN_LIMIT = 0.0f;
enum float DOOR_HEIGHT = 0.13f;
enum float DOOR_COLUMN_LIMIT = 0.97f;
enum ubyte TEST_DIMENSION = 12;

struct TowerPalette {
    Material wall;
    Material window;
    Material floor;
    Material spire;
}

immutable TowerPalette[4] TOWER_PALETTES = [
    TowerPalette(Material.concrete, Material.glass, Material.concrete, Material.steel),
    TowerPalette(Material.whiteBrick, Material.glass, Material.greyBrick, Material.steel),
    TowerPalette(Material.sandstone, Material.glass, Material.woodPlanks, Material.steel),
    TowerPalette(Material.greyBrick, Material.glass, Material.concrete, Material.marble),
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
        if (graph.worldgen.kind == WorldgenKind.flat) {
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
    return SplitMix(graph.idAt(slot).spice() ^ (graph.worldgen.seed * TOWER_SEED_MULTIPLIER)).next();
}

bool isTowerBase(ref Graph graph, uint slot) {
    NodeState state = *graph.ensureNodeStateAt(slot);
    if (state.kind != NodeStateKind.sky) {
        return false;
    } else if (graph.worldgen.kind == WorldgenKind.structure) {
        return graph.idAt(slot) == graph.worldgen.showcaseBase;
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

uint showcaseBaseSlot(ref Graph graph) {
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

struct TowerShape {
    float[3][SIDE_COUNT] directions;
    float[3][SIDE_COUNT] references;
    float[3][SIDE_COUNT] binormals;
    float[3] spireDirection;
    float faceLength;
    float floorSpacing;
    float sinhOuter;
    float sinhInner;
    float coshOuter;
    float coshInner;
    uint tubeCount;
    uint doorTube;
    TowerPalette palette;
    bool hasSpire;
    bool isFoundation;

    static TowerShape fromStructure(NodeStructure structure) {
        TowerShape shape;
        ushort tubes = structure.incoming | structure.outgoing;
        Side straight = structure.part.down.opposite;
        foreach (index; 0 .. SIDE_COUNT) {
            Side side = cast(Side) index;
            if ((tubes & faceBit(side)) != 0) {
                if (structure.part.symbol == TowerSymbol.base && side == structure.part.down) {
                    shape.doorTube = shape.tubeCount;
                }
                shape.directions[shape.tubeCount] = side.faceDirection;
                shape.references[shape.tubeCount] = side.faceReference;
                shape.binormals[shape.tubeCount] = side.faceDirection.cross(side.faceReference);
                shape.tubeCount += 1;
            }
        }
        if (structure.part.symbol != TowerSymbol.base) {
            shape.doorTube = shape.tubeCount;
        }
        shape.spireDirection = straight.faceDirection;
        shape.faceLength = faceDistance();
        shape.floorSpacing = shape.faceLength / FLOORS_PER_FACE_DISTANCE;
        shape.sinhOuter = sinhf(OUTER_RADIUS);
        shape.sinhInner = sinhf(OUTER_RADIUS - WALL_THICKNESS);
        shape.coshOuter = coshf(OUTER_RADIUS);
        shape.coshInner = coshf(OUTER_RADIUS - WALL_THICKNESS);
        shape.palette = TOWER_PALETTES[structure.part.palette];
        shape.hasSpire = structure.part.isGrowing() && structure.outgoing == 0;
        shape.isFoundation = structure.part.symbol == TowerSymbol.foundation;
        return shape;
    }

    bool isInTube(uint tube, float[3] spatial, float sinhRadius) const {
        float along = spatial.dot(directions[tube]);
        return along >= 0 && spatial.minus(directions[tube].scaled(along)).magnitude <= sinhRadius;
    }

    uint tubeAt(float[3] spatial, float sinhRadius) const {
        uint tube = 0;
        while (tube < tubeCount && !isInTube(tube, spatial, sinhRadius)) {
            tube += 1;
        }
        return tube;
    }

    bool isInSpire(float[3] spatial, float w) const {
        float along = spatial.dot(spireDirection);
        float axial = atanhf(along / w);
        return along > 0 && axial < faceLength && spatial.minus(spireDirection.scaled(along)).magnitude <= sinhf(OUTER_RADIUS * (1.0f - axial / faceLength));
    }

    Material materialAt(MPoint!float point, Material existing) const {
        float[3] spatial = point.vec.xyz();
        float w = point.vec.data[3];
        bool isInOuter = w <= coshOuter || tubeAt(spatial, sinhOuter) < tubeCount;
        bool isInInner = w <= coshInner || tubeAt(spatial, sinhInner) < tubeCount;
        if (hasSpire && isInSpire(spatial, w)) {
            return palette.spire;
        } else if (!isInOuter) {
            return existing;
        } else if (isFoundation) {
            return palette.wall;
        } else if (!isInInner) {
            return wallMaterial(spatial, w, tubeAt(spatial, sinhOuter));
        } else {
            return interiorMaterial(spatial, w, tubeAt(spatial, sinhInner));
        }
    }

    Material wallMaterial(float[3] spatial, float w, uint tube) const {
        if (tube == tubeCount) {
            return palette.wall;
        } else {
            float along = spatial.dot(directions[tube]);
            float axial = atanhf(along / w);
            float[3] radial = spatial.minus(directions[tube].scaled(along));
            float angle = atan2f(radial.dot(binormals[tube]), radial.dot(references[tube]));
            float phase = fmodf(axial, floorSpacing);
            bool isDoorway = tube == doorTube && axial > faceLength - FLOOR_THICKNESS / 2 - DOOR_HEIGHT && cosf(angle) > DOOR_COLUMN_LIMIT;
            bool isWindow = fabsf(phase - floorSpacing / 2) < floorSpacing * WINDOW_HALF_HEIGHT_PER_FLOOR && cosf(WINDOW_COLUMNS * angle) > WINDOW_COLUMN_LIMIT;
            if (isDoorway) {
                return Material.none;
            } else if (isWindow) {
                return palette.window;
            } else {
                return palette.wall;
            }
        }
    }

    Material interiorMaterial(float[3] spatial, float w, uint tube) const {
        if (tube == tubeCount) {
            return Material.none;
        } else if (fmodf(atanhf(spatial.dot(directions[tube]) / w) + FLOOR_THICKNESS / 2, floorSpacing) < FLOOR_THICKNESS) {
            return palette.floor;
        } else {
            return Material.none;
        }
    }
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

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, WorldgenSettings(NodeId.init, 0, WorldgenKind.structure));
    Array!uint nodes;
    nodes.append(graph.slotOf(graph.worldgen.showcaseBase));
    size_t front = 0;
    uint forks = 0;
    while (front < nodes.length) {
        uint slot = nodes.ptr[front];
        NodeStructure structure = graph.ensureStructureAt(slot);
        assert(structure.isPresent());
        if (popCount(structure.outgoing) > 1) {
            forks += 1;
        }
        foreach (index; 0 .. SIDE_COUNT) {
            if ((structure.outgoing & faceBit(cast(Side) index)) != 0) {
                nodes.append(graph.ensureNeighborSlot(slot, cast(Side) index));
            }
        }
        front += 1;
    }
    assert(nodes.length >= MIN_TRUNK_NODES + 2);
    assert(forks >= MIN_FORKS);
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
