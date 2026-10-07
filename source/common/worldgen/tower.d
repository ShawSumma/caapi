module common.worldgen.tower;

import core.math : sqrt;
import core.stdc.math : asinhf, atanhf, coshf, fabsf, floorf, sinhf;
import common.array : Array;
import common.dodeca : SIDE_COUNT, Side, VERTEX_COUNT, Vertex, canonicalSides, dualToNode, isAdjacentTo, reflection;
import common.graph : Graph, ROOT_NODE;
import common.material : Material;
import common.math : MIsometry, MPoint, MVector, Matrix4;
import common.node : ChunkLayout;
import common.units : Length;
import common.worldgen.generation : NodeState, SplitMix, WorldgenKind;

enum int BOX_HALF_CELLS = 5;
enum int STORY_CELLS = 4;
enum int TOWER_SEGMENTS = 3;
enum int FOUNDATION_CELLS = 3;
enum int STAIR_START = 2 - BOX_HALF_CELLS;
enum float MIDDLE_LANE = 0;
enum uint PALETTE_SHIFT = 24;
enum Length ON_LINE_TOLERANCE = Length(1e-3f);
enum Length SPAWN_DISTANCE = Length(1.0f);
enum float AXIS_TOLERANCE = 0.5f;

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

struct NodeStructure {
    MIsometry!float frame;
    bool hasTower;
    ubyte palette;

    static NodeStructure fromNode(ref Graph graph, uint slot) {
        if (graph.worldgen.kind != WorldgenKind.structure) {
            return NodeStructure.init;
        } else {
            uint base = graph.slotOf(graph.worldgen.structure.base);
            MIsometry!float frame = graph.nodeToNode(base, slot) * baseFrame();
            return NodeStructure(frame, isOnTowerLine(frame, graph.layout), paletteOf(graph.towerBits(base)));
        }
    }

    bool isPresent() const {
        return hasTower;
    }

    MIsometry!float towerFromNode() const {
        return frame.inverse();
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

    static ColumnChunk fromVertex(MIsometry!float towerFromNode, Vertex vertex, ref const ChunkLayout layout) {
        MIsometry!float toTower = towerFromNode * vertex.dualToNode;
        MVector!float corner = (toTower * MPoint!float.origin()).vec;
        if (!(Length(sqrt(corner.data[0] * corner.data[0] + corner.data[2] * corner.data[2])) < ON_LINE_TOLERANCE)) {
            return ColumnChunk.init;
        } else {
            ColumnChunk chunk;
            foreach (axis; 0 .. 3) {
                float[4] basis = [0, 0, 0, 0];
                basis[axis] = 1;
                MVector!float direction = toTower * MVector!float(basis);
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
            chunk.bottom = vertexLevel * 2 * layout.dimension;
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

int towerTop(ubyte dimension) {
    return TOWER_SEGMENTS * 2 * dimension / STORY_CELLS * STORY_CELLS;
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

ColumnSpot doorSpot() {
    return ColumnSpot(-BOX_HALF_CELLS, 0, 1, true);
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
    float segmentCells = 2.0f * layout.dimension;
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

ColumnSpot stairSpot(size_t index, ubyte dimension) {
    int stops = STORY_CELLS + 3;
    int story = cast(int)(index / stops);
    int stop = cast(int)(index % stops);
    int floor = story * STORY_CELLS;
    float lane = stairLaneLow(story) + 1.0f;
    float approach = STAIR_START - 0.5f;
    float landing = STAIR_START + STORY_CELLS - 0.5f;
    ColumnSpot spot;
    if (floor >= towerTop(dimension)) {
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

MIsometry!float baseFrame() {
    Vertex vertex = firstVertexOn(Side.a);
    size_t up = sideAxis(vertex, Side.a);
    Matrix4!float axes;
    axes.data[0][(up + 1) % 3] = 1;
    axes.data[1][up] = 1;
    axes.data[2][(up + 2) % 3] = 1;
    axes.data[3][3] = 1;
    return vertex.dualToNode * MIsometry!float(axes);
}

MPoint!float doorwaySpawn() {
    return MPoint!float(MVector!float([-sinhf(SPAWN_DISTANCE.value), 0, 0, coshf(SPAWN_DISTANCE.value)]));
}

bool isOnTowerLine(MIsometry!float frame, ref const ChunkLayout layout) {
    MIsometry!float towerFromNode = frame.inverse();
    Length top = edgeLength(layout) * cast(float) TOWER_SEGMENTS + ON_LINE_TOLERANCE;
    Length bottom = -ON_LINE_TOLERANCE;
    uint vertex = 0;
    while (vertex < VERTEX_COUNT && !isOnLineBetween(towerFromNode * (cast(Vertex) vertex).dualToNode * MPoint!float.origin(), bottom, top)) {
        vertex += 1;
    }
    return vertex < VERTEX_COUNT;
}

bool isOnLineBetween(MPoint!float point, Length bottom, Length top) {
    MVector!float q = point.vec;
    Length height = Length(asinhf(q.data[1]));
    return Length(sqrt(q.data[0] * q.data[0] + q.data[2] * q.data[2])) < ON_LINE_TOLERANCE && height > bottom && height < top;
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
