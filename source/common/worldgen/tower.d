module common.worldgen.tower;

import core.math : sqrt;
import core.stdc.math : asinhf, atanhf, coshf, fabsf, floorf, sinhf;
import common.array : Array;
import common.dodeca : SIDE_COUNT, Side, VERTEX_COUNT, Vertex, canonicalSides, dualToNode, isAdjacentTo, reflection;
import common.graph : Graph, ROOT_NODE;
import common.material : Material;
import common.math : MIsometry, MPoint, MVector, Matrix4;
import common.node : ChunkLayout;
import common.settings : CHUNK_DIMENSION;
import common.units : Length;
import common.worldgen.generation : NodeState, SplitMix, StructureKind, WorldgenKind;

enum int BOX_HALF_CELLS = 5;
enum int STORY_CELLS = 4;
enum int STAIR_STOPS = STORY_CELLS + 3;
enum int FOUNDATION_CELLS = 3;
enum int STAIR_START = 2 - BOX_HALF_CELLS;
enum int BOX_TOWER_SEGMENTS = 3;
enum int CROWN_SEGMENTS = 2;
enum int ARCH_STOP_CELLS = STORY_CELLS;
enum uint MAX_STRUCTURE_LINES = 15;
enum uint PALETTE_SHIFT = 24;
enum float MIDDLE_LANE = 0;
enum float ROUTE_LANE = 0.5f;
enum float AXIS_TOLERANCE = 0.5f;
enum Length ON_LINE_TOLERANCE = Length(1e-3f);
enum Length SPAWN_DISTANCE = Length(1.0f);

static assert(edgeCells(CHUNK_DIMENSION) % STORY_CELLS == 0);

struct TowerPalette {
    Material wall;
    Material floor;
    Material trim;
}

immutable TowerPalette[4] TOWER_PALETTES = [
    TowerPalette(Material.concrete, Material.concrete, Material.steel),
    TowerPalette(Material.whiteBrick, Material.greyBrick, Material.steel),
    TowerPalette(Material.sandstone, Material.woodPlanks, Material.steel),
    TowerPalette(Material.greyBrick, Material.concrete, Material.marble),
];

enum LineRole : ubyte {
    tower,
    bridge,
}

struct StructureLine {
    MIsometry!float placement;
    Length length;
    Side acrossSide;
    Side alongSide;
    LineRole role;

    bool hasSide(Side side) const {
        return acrossSide == side || alongSide == side;
    }

    bool isTouchedBy(MIsometry!float nodeFromBase) const {
        MIsometry!float lineFromNode = (nodeFromBase * placement).inverse();
        uint vertex = 0;
        while (vertex < VERTEX_COUNT && !isOnLine(lineFromNode * (cast(Vertex) vertex).dualToNode * MPoint!float.origin())) {
            vertex += 1;
        }
        return vertex < VERTEX_COUNT;
    }

    bool isOnLine(MPoint!float point) const {
        MVector!float q = point.vec;
        Length height = Length(asinhf(q.data[1]));
        return Length(sqrt(q.data[0] * q.data[0] + q.data[2] * q.data[2])) < ON_LINE_TOLERANCE && height > -ON_LINE_TOLERANCE && height < length + ON_LINE_TOLERANCE;
    }
}

struct StructurePlan {
    StructureLine[MAX_STRUCTURE_LINES] lines;
    uint count;
    uint towerCount;
    uint archTower;
    int top;
    Side doorSide;
    bool isArchAlongAtEnd;
    StructureKind kind;

    static StructurePlan fromKind(StructureKind kind, ref const ChunkLayout layout) {
        StructurePlan plan;
        plan.kind = kind;
        Length edge = edgeLength(layout);
        if (kind == StructureKind.crown) {
            plan.top = storiesTop(CROWN_SEGMENTS, layout.dimension);
            foreach (index; 0 .. VERTEX_COUNT) {
                if (sideAxis(cast(Vertex) index, Side.a) < 3) {
                    plan.add(towerLine(cast(Vertex) index, edge * cast(float) CROWN_SEGMENTS));
                }
            }
            plan.towerCount = plan.count;
            foreach (tower; 0 .. plan.towerCount) {
                plan.add(bridgeLine(plan.lines[tower], ALONG_BRIDGE, edge));
                plan.add(bridgeLine(plan.lines[tower], ACROSS_BRIDGE, edge));
            }
            plan.doorSide = plan.lines[0].acrossSide;
            plan.archTower = 1;
            while (plan.archTower < plan.towerCount && !plan.lines[plan.archTower].hasSide(plan.doorSide)) {
                plan.archTower += 1;
            }
            assert(plan.archTower < plan.towerCount);
            plan.isArchAlongAtEnd = plan.lines[plan.archTower].acrossSide == plan.doorSide;
        } else {
            plan.top = storiesTop(BOX_TOWER_SEGMENTS, layout.dimension);
            plan.add(towerLine(firstVertexOn(Side.a), edge * cast(float) BOX_TOWER_SEGMENTS));
            plan.towerCount = 1;
        }
        return plan;
    }

    void add(StructureLine line) {
        lines[count] = line;
        count += 1;
    }

    uint bridgeOf(uint tower, bool isAlong) const {
        if (isAlong) {
            return towerCount + 2 * tower;
        } else {
            return towerCount + 2 * tower + 1;
        }
    }

    bool isTouchedBy(MIsometry!float nodeFromBase) const {
        uint line = 0;
        while (line < count && !lines[line].isTouchedBy(nodeFromBase)) {
            line += 1;
        }
        return line < count;
    }

    ColumnSpot doorSpot(ubyte dimension) const {
        if (kind == StructureKind.crown) {
            return ColumnSpot(0, dimension, 1, true);
        } else {
            return ColumnSpot(-BOX_HALF_CELLS, 0, 1, true);
        }
    }

    MPoint!float spawnPoint(ref const ChunkLayout layout) const {
        Length beside = Length(0);
        if (kind == StructureKind.crown) {
            beside = edgeLength(layout) / 2.0f;
        }
        float away = SPAWN_DISTANCE.value;
        return MPoint!float(MVector!float([-sinhf(away), 0, coshf(away) * sinhf(beside.value), coshf(away) * coshf(beside.value)]));
    }
}

enum bool ALONG_BRIDGE = true;
enum bool ACROSS_BRIDGE = false;

StructureLine towerLine(Vertex vertex, Length length) {
    size_t up = sideAxis(vertex, Side.a);
    Matrix4!float axes;
    axes.data[0][(up + 1) % 3] = 1;
    axes.data[1][up] = 1;
    axes.data[2][(up + 2) % 3] = 1;
    axes.data[3][3] = 1;
    return StructureLine(vertex.dualToNode * MIsometry!float(axes), length, vertex.canonicalSides[(up + 1) % 3], vertex.canonicalSides[(up + 2) % 3], LineRole.tower);
}

StructureLine bridgeLine(ref const StructureLine tower, bool isAlong, Length edge) {
    Matrix4!float axes;
    if (isAlong) {
        axes.data[0][0] = 1;
        axes.data[1][2] = 1;
        axes.data[2][1] = 1;
    } else {
        axes.data[0][2] = 1;
        axes.data[1][0] = 1;
        axes.data[2][1] = 1;
    }
    axes.data[3][3] = 1;
    Side face = tower.alongSide;
    if (isAlong) {
        face = tower.acrossSide;
    }
    float[3] lift = [0, edge.value, 0];
    return StructureLine(tower.placement * MIsometry!float.fromDisplacement(lift) * MIsometry!float(axes), edge, face, face, LineRole.bridge);
}

struct NodeStructure {
    MIsometry!float frame;
    bool hasTower;
    ubyte palette;
    StructureKind kind;

    static NodeStructure fromNode(ref Graph graph, uint slot) {
        if (graph.worldgen.kind != WorldgenKind.structure) {
            return NodeStructure.init;
        } else {
            uint base = graph.slotOf(graph.worldgen.structure.base);
            StructureKind kind = graph.worldgen.structure.kind;
            MIsometry!float frame = graph.nodeToNode(base, slot);
            return NodeStructure(frame, StructurePlan.fromKind(kind, graph.layout).isTouchedBy(frame), paletteOf(graph.towerBits(base)), kind);
        }
    }

    bool isPresent() const {
        return hasTower;
    }

    MIsometry!float lineToNode(ref const StructurePlan plan, uint line) const {
        return frame * plan.lines[line].placement;
    }
}

struct ColumnChunk {
    size_t vertical;
    size_t across;
    size_t along;
    int acrossSign;
    int alongSign;
    int bottom;
    bool isUpward;
    bool isPresent;

    static ColumnChunk fromVertex(ref const StructureLine line, MIsometry!float lineFromNode, Vertex vertex, ref const ChunkLayout layout) {
        MIsometry!float toLine = lineFromNode * vertex.dualToNode;
        MVector!float corner = (toLine * MPoint!float.origin()).vec;
        if (!line.isOnLine(MPoint!float(corner))) {
            return ColumnChunk.init;
        } else {
            ColumnChunk chunk;
            foreach (axis; 0 .. 3) {
                float[4] basis = [0, 0, 0, 0];
                basis[axis] = 1;
                MVector!float direction = toLine * MVector!float(basis);
                if (fabsf(direction.data[0]) > AXIS_TOLERANCE) {
                    chunk.across = axis;
                    chunk.acrossSign = signOf(direction.data[0]);
                } else if (fabsf(direction.data[2]) > AXIS_TOLERANCE) {
                    chunk.along = axis;
                    chunk.alongSign = signOf(direction.data[2]);
                } else {
                    chunk.vertical = axis;
                    chunk.isUpward = direction.data[1] > 0;
                }
            }
            int vertexLevel = cast(int) floorf(asinhf(corner.data[1]) / edgeLength(layout).value + 0.5f);
            chunk.bottom = vertexLevel * edgeCells(layout.dimension);
            chunk.isPresent = true;
            return chunk;
        }
    }

    int[3] columnOf(int[3] cell) const {
        int height = 0;
        if (isUpward) {
            height = bottom + cell[vertical];
        } else {
            height = bottom - 1 - cell[vertical];
        }
        return [signedIndex(cell[across], acrossSign), signedIndex(cell[along], alongSign), height];
    }
}

struct ColumnSpot {
    float across = 0;
    float along = 0;
    float height = 0;
    bool isFound;
}

struct RouteStop {
    ColumnSpot spot;
    uint line;
}

int signOf(float value) {
    if (value > 0) {
        return 1;
    } else {
        return -1;
    }
}

int signedIndex(int cell, int sign) {
    if (sign > 0) {
        return cell;
    } else {
        return -1 - cell;
    }
}

float signedDual(ref const ChunkLayout layout, float grid) {
    if (grid < 0) {
        return -layout.gridToDual(-grid);
    } else {
        return layout.gridToDual(grid);
    }
}

Length edgeLength(ref const ChunkLayout layout) {
    return Length(2.0f * atanhf(layout.gridToDual(layout.dimension)));
}

int storiesTop(int segments, ubyte dimension) {
    return segments * edgeCells(dimension) / STORY_CELLS * STORY_CELLS;
}

int edgeCells(ubyte dimension) {
    return 2 * dimension;
}

int stairLaneLow(int story) {
    if (story % 2 == 0) {
        return 1 - BOX_HALF_CELLS;
    } else {
        return BOX_HALF_CELLS - 3;
    }
}

bool isStairRun(int story, int across, int along) {
    return isInStairLane(story, along) && across >= STAIR_START && across <= STAIR_START + STORY_CELLS - 2;
}

bool isDoor(int across, int along, int height) {
    return height > 0 && height < STORY_CELLS && across == -BOX_HALF_CELLS && (along == -1 || along == 0);
}

bool isStairwell(int story, int across, int along) {
    return isInStairLane(story, along) && across >= STAIR_START - 1 && across <= STAIR_START + STORY_CELLS - 2;
}

bool isInStairLane(int story, int along) {
    int lane = stairLaneLow(story);
    return along >= lane && along <= lane + 1;
}

MPoint!float columnPoint(ref const ChunkLayout layout, ColumnSpot spot) {
    float segmentCells = edgeCells(layout.dimension);
    float segment = floorf(spot.height / segmentCells);
    float local = spot.height - segment * segmentCells;
    float rise = layout.gridToDual(local);
    float level = segment;
    if (local > layout.dimension) {
        rise = -layout.gridToDual(segmentCells - local);
        level = segment + 1;
    }
    MPoint!float inVertexFrame = MVector!float([signedDual(layout, spot.across), rise, signedDual(layout, spot.along), 1.0f]).normalizedPoint();
    float[3] lift = [0, level * edgeLength(layout).value, 0];
    return MIsometry!float.fromDisplacement(lift) * inVertexFrame;
}

ColumnSpot stairSpot(size_t index, int top) {
    int story = cast(int)(index / STAIR_STOPS);
    int stop = cast(int)(index % STAIR_STOPS);
    int floor = story * STORY_CELLS;
    float lane = stairLaneLow(story) + 1.0f;
    float approach = STAIR_START - 0.5f;
    float landing = STAIR_START + STORY_CELLS - 0.5f;
    ColumnSpot spot;
    if (floor >= top) {
        spot = ColumnSpot.init;
    } else if (stop == 0) {
        spot = ColumnSpot(approach, MIDDLE_LANE, floor + 1.0f, true);
    } else if (stop == 1) {
        spot = ColumnSpot(approach, lane, floor + 1.0f, true);
    } else if (stop < STORY_CELLS + 1) {
        spot = ColumnSpot(STAIR_START + stop - 1.5f, lane, floor + stop, true);
    } else if (stop == STORY_CELLS + 1) {
        spot = ColumnSpot(landing, lane, floor + STORY_CELLS + 1.0f, true);
    } else {
        spot = ColumnSpot(landing, MIDDLE_LANE, floor + STORY_CELLS + 1.0f, true);
    }
    return spot;
}

uint archStopCount(ubyte dimension) {
    return (edgeCells(dimension) - 1 - BOX_HALF_CELLS + ARCH_STOP_CELLS - 1) / ARCH_STOP_CELLS + 1;
}

ColumnSpot archSpot(uint stop, ubyte dimension) {
    float along = BOX_HALF_CELLS + 0.5f + stop * ARCH_STOP_CELLS;
    float apex = edgeCells(dimension) - 0.5f;
    if (along > apex) {
        along = apex;
    }
    return ColumnSpot(ROUTE_LANE, 1, along, true);
}

ColumnSpot doorwaySpot(bool isAlong, float depth, int floor) {
    if (isAlong) {
        return ColumnSpot(ROUTE_LANE, depth, floor + 1.0f, true);
    } else {
        return ColumnSpot(depth, ROUTE_LANE, floor + 1.0f, true);
    }
}

RouteStop routeStop(ref const StructurePlan plan, size_t index, ubyte dimension) {
    if (plan.kind != StructureKind.crown) {
        return RouteStop(stairSpot(index, plan.top), 0);
    } else {
        size_t stairs = cast(size_t)(edgeCells(dimension) / STORY_CELLS) * STAIR_STOPS;
        size_t arch = archStopCount(dimension);
        int floor = edgeCells(dimension);
        float inside = BOX_HALF_CELLS - 1.5f;
        float outside = BOX_HALF_CELLS + 0.5f;
        RouteStop stop;
        if (index < stairs) {
            stop = RouteStop(stairSpot(index, plan.top), 0);
        } else if (index == stairs) {
            stop = RouteStop(doorwaySpot(ALONG_BRIDGE, inside, floor), 0);
        } else if (index == stairs + 1) {
            stop = RouteStop(doorwaySpot(ALONG_BRIDGE, outside, floor), 0);
        } else if (index < stairs + 2 + arch) {
            stop = RouteStop(archSpot(cast(uint)(index - stairs - 2), dimension), plan.bridgeOf(0, ALONG_BRIDGE));
        } else if (index < stairs + 2 + 2 * arch) {
            stop = RouteStop(archSpot(cast(uint)(stairs + 1 + 2 * arch - index), dimension), plan.bridgeOf(plan.archTower, plan.isArchAlongAtEnd));
        } else if (index == stairs + 2 + 2 * arch) {
            stop = RouteStop(doorwaySpot(plan.isArchAlongAtEnd, inside, floor), plan.archTower);
        } else if (index == stairs + 3 + 2 * arch) {
            stop = RouteStop(doorwaySpot(plan.isArchAlongAtEnd, ROUTE_LANE, floor), plan.archTower);
        } else {
            stop = RouteStop(stairSpot(index - 4 - 2 * arch, plan.top), plan.archTower);
        }
        return stop;
    }
}

MIsometry!float nodeToNode(ref const Graph graph, uint from, uint to) {
    Array!Side toPath = graph.sidesToRoot(graph.idAt(to));
    Array!Side fromPath = graph.sidesToRoot(graph.idAt(from));
    const(Side)[] toSides = toPath.slice();
    const(Side)[] fromSides = fromPath.slice();
    while (toSides.length > 0 && fromSides.length > 0 && toSides[$ - 1] == fromSides[$ - 1]) {
        toSides = toSides[0 .. $ - 1];
        fromSides = fromSides[0 .. $ - 1];
    }
    MIsometry!double transform = MIsometry!double.identity();
    foreach (side; toSides) {
        transform = transform * side.reflection.toType!double();
    }
    foreach_reverse (side; fromSides) {
        transform = transform * side.reflection.toType!double();
    }
    toPath.release();
    fromPath.release();
    return transform.toType!float();
}

Vertex firstVertexOn(Side side) {
    uint vertex = 0;
    while (vertex < VERTEX_COUNT && sideAxis(cast(Vertex) vertex, side) == 3) {
        vertex += 1;
    }
    return cast(Vertex) vertex;
}

size_t sideAxis(Vertex vertex, Side side) {
    size_t axis = 0;
    while (axis < 3 && vertex.canonicalSides[axis] != side) {
        axis += 1;
    }
    return axis;
}

ubyte paletteOf(ulong bits) {
    return cast(ubyte)((bits >> PALETTE_SHIFT) % TOWER_PALETTES.length);
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

float altitude(ref const NodeState state) {
    return state.surface.distanceTo(MPoint!float.origin());
}

ulong towerBits(ref const Graph graph, uint slot) {
    return SplitMix(graph.idAt(slot).spice()).next();
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
