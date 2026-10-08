module common.worldgen.structure;

import core.math : sqrt;
import core.stdc.math : asinhf, atanhf, coshf, floorf, sinhf;
import common.array : Array;
import common.dodeca : SIDE_COUNT, Side, VERTEX_COUNT, Vertex, adjacentVertices, canonicalSides, chunkToNode, dualToNode, isAdjacentTo, reflection;
import common.graph : Graph, ParentList, ROOT_NODE;
import common.material : Material;
import common.math : MIsometry, MPoint, MVector, Matrix4;
import common.node : ChunkLayout;
import common.position : Position;
import common.traversal : NearbyNode, NearbyScratch;
import common.units : Length;
import common.worldgen.blueprint : Blueprint, BlueprintBuilder, CellBox, EVERY_HEIGHT, LineSpec, canonicalBox;
import common.worldgen.generation : NodeState, SplitMix, StructureWorld, Worldgen;

enum uint MAX_LINE_TOUCHES = 16;
enum uint FACE_CORNERS = 5;
enum uint QUARTER_TURNS = 4;
enum Length SPAWN_DISTANCE = Length(1.0f);
enum ubyte TEST_DIMENSION = 12;
enum float TEST_RADIUS = 3.0f;
enum Length TEST_TOLERANCE = Length(0.01f);
enum Length TEST_ON_LINE = Length(1e-3f);
immutable int[3][4] TEST_CELLS = [
    [0, 0, 0],
    [3, 1, 2],
    [11, 5, 0],
    [2, 11, 9],
];

struct LineTouch {
    int level;
    ubyte line;
    Vertex lower;
    byte acrossSign;
    byte alongSign;
}

struct LineSeed {
    LineTouch touch;
    uint slot;
}

struct TouchCrossing {
    LineTouch touch;
    bool isKept;
}

struct SiteFrame {
    int level;
    uint node;
    Vertex vertex;
    Side acrossSide;
    Side alongSide;
    byte acrossSign;
    byte alongSign;
    byte heightSign;

    Side heightSide() const {
        return vertex.canonicalSides[3 - sideAxis(vertex, acrossSide) - sideAxis(vertex, alongSide)];
    }

    Vertex nextVertex() const {
        return vertex.adjacentVertices[sideAxis(vertex, heightSide())];
    }
}

struct FrameCrossing {
    SiteFrame site;
    bool isKept;
}

struct LineTransform {
    int offsetLevels;
    byte acrossSign;
    byte alongSign;
    byte heightSign;
    bool isSwapped;
}

struct CanonicalSite {
    LineSpec line;
    LineTransform transform;
}

struct NodeStructure {
    LineTouch[MAX_LINE_TOUCHES] touches;
    uint count;
    bool isPresent;

    static NodeStructure fromParents(ref const Graph graph, uint slot) {
        NodeStructure result;
        foreach (seed; graph.seeds.slice()) {
            if (seed.slot == slot) {
                result.add(seed.touch);
            }
        }
        ParentList parents = graph.parents(slot);
        foreach (link; parents.links[0 .. parents.count]) {
            const(NodeStructure)* above = &graph.nodeAt(link.slot).structure;
            foreach (touch; above.touches[0 .. above.count]) {
                TouchCrossing crossing = crossed(touch, graph.blueprint.lines.ptr[touch.line], link.side);
                if (crossing.isKept) {
                    result.add(crossing.touch);
                }
            }
        }
        result.isPresent = result.isBuiltOn(graph.blueprint);
        return result;
    }

    void add(LineTouch touch) {
        uint index = 0;
        while (index < count && touches[index].line < touch.line) {
            index += 1;
        }
        if (index == count || touches[index].line != touch.line) {
            assert(count < MAX_LINE_TOUCHES);
            foreach_reverse (moved; index .. count) {
                touches[moved + 1] = touches[moved];
            }
            touches[index] = touch;
            count += 1;
        }
    }

    bool isBuiltOn(ref const Blueprint blueprint) const {
        uint index = 0;
        while (index < count && !isTouchInRange(touches[index], blueprint.lines.ptr[touches[index].line])) {
            index += 1;
        }
        return index < count;
    }
}

bool isTouchInRange(ref const LineTouch touch, ref const LineSpec spec) {
    return isLevelInRange(spec, touch.level) || isLevelInRange(spec, touch.level + 1);
}

bool isLevelInRange(ref const LineSpec spec, int level) {
    return level >= spec.lowest && level <= spec.highest;
}

TouchCrossing crossed(LineTouch touch, ref const LineSpec spec, Side side) {
    Vertex upper = upperOf(touch.lower, spec);
    if (side == spec.acrossSide) {
        return TouchCrossing(LineTouch(touch.level, touch.line, touch.lower, cast(byte) -touch.acrossSign, touch.alongSign), true);
    } else if (side == spec.alongSide) {
        return TouchCrossing(LineTouch(touch.level, touch.line, touch.lower, touch.acrossSign, cast(byte) -touch.alongSign), true);
    } else if (side == crossingSide(touch.lower, spec)) {
        return TouchCrossing(LineTouch(touch.level - 1, touch.line, upper, touch.acrossSign, touch.alongSign), true);
    } else if (side == crossingSide(upper, spec)) {
        return TouchCrossing(LineTouch(touch.level + 1, touch.line, upper, touch.acrossSign, touch.alongSign), true);
    } else {
        return TouchCrossing(touch, false);
    }
}

Vertex upperOf(Vertex lower, ref const LineSpec spec) {
    return lower.adjacentVertices[crossingAxis(lower, spec)];
}

size_t crossingAxis(Vertex vertex, ref const LineSpec spec) {
    return 3 - sideAxis(vertex, spec.acrossSide) - sideAxis(vertex, spec.alongSide);
}

Side crossingSide(Vertex vertex, ref const LineSpec spec) {
    return vertex.canonicalSides[crossingAxis(vertex, spec)];
}

Array!LineSeed seedLines(ref const Blueprint blueprint) {
    Array!LineSeed seeds;
    foreach (line, spec; blueprint.lines.slice()) {
        seeds.append(LineSeed(LineTouch(0, cast(ubyte) line, spec.lower, 1, 1), spec.node));
    }
    return seeds;
}

SiteFrame rootSite(uint anchor) {
    Vertex vertex = firstVertexOn(Side.a);
    size_t up = sideAxis(vertex, Side.a);
    Side[3] sides = vertex.canonicalSides;
    return SiteFrame(0, anchor, vertex, sides[(up + 1) % 3], sides[(up + 2) % 3], 1, 1, 1);
}

SiteFrame turned(SiteFrame site, int quarters) {
    SiteFrame result = site;
    foreach (_; 0 .. ((quarters % QUARTER_TURNS) + QUARTER_TURNS) % QUARTER_TURNS) {
        result = SiteFrame(result.level, result.node, result.vertex, result.alongSide, result.acrossSide, result.alongSign, cast(byte) -result.acrossSign, result.heightSign);
    }
    return result;
}

SiteFrame shifted(SiteFrame site, int edges) {
    return SiteFrame(site.level - edges, site.node, site.vertex, site.acrossSide, site.alongSide, site.acrossSign, site.alongSign, site.heightSign);
}

SiteFrame atLevel(ref Graph graph, SiteFrame site, int level) {
    SiteFrame result = site;
    while (result.level != level) {
        result = graph.stepped(result, level > result.level);
    }
    return result;
}

SiteFrame stepped(ref Graph graph, SiteFrame site, bool isUp) {
    bool isInside = (site.heightSign > 0) == isUp;
    if (isInside) {
        int rise = -1;
        if (isUp) {
            rise = 1;
        }
        Vertex next = site.nextVertex();
        return SiteFrame(site.level + rise, site.node, next, site.acrossSide, site.alongSide, site.acrossSign, site.alongSign, cast(byte) -site.heightSign);
    } else {
        uint across = graph.ensureNeighborSlot(site.node, site.heightSide());
        return SiteFrame(site.level, across, site.vertex, site.acrossSide, site.alongSide, site.acrossSign, site.alongSign, cast(byte) -site.heightSign);
    }
}

SiteFrame branched(ref Graph graph, SiteFrame site, int level, bool isAlong) {
    SiteFrame at = graph.atLevel(site, level);
    if (isAlong) {
        return SiteFrame(0, at.node, at.vertex, at.acrossSide, at.heightSide(), at.acrossSign, at.heightSign, at.alongSign);
    } else {
        return SiteFrame(0, at.node, at.vertex, at.alongSide, at.heightSide(), at.alongSign, at.heightSign, at.acrossSign);
    }
}

SiteFrame[FACE_CORNERS] faceCorners(ref Graph graph, SiteFrame site) {
    SiteFrame[FACE_CORNERS] corners = void;
    corners[0] = graph.atLevel(site, 0);
    foreach (index; 1 .. FACE_CORNERS) {
        corners[index] = graph.nextCorner(corners[index - 1]);
    }
    return corners;
}

SiteFrame nextCorner(ref Graph graph, SiteFrame corner) {
    SiteFrame inward = corner;
    if (corner.alongSign < 0) {
        inward = SiteFrame(0, graph.ensureNeighborSlot(corner.node, corner.alongSide), corner.vertex, corner.acrossSide, corner.alongSide, corner.acrossSign, 1, corner.heightSign);
    }
    Vertex next = inward.vertex.adjacentVertices[sideAxis(inward.vertex, inward.alongSide)];
    Side back = next.canonicalSides[3 - sideAxis(next, inward.acrossSide) - sideAxis(next, inward.heightSide())];
    return SiteFrame(0, inward.node, next, back, inward.acrossSide, 1, inward.acrossSign, inward.heightSign);
}

FrameCrossing crossedFrame(SiteFrame site, Side side, uint node) {
    Vertex next = site.nextVertex();
    Side far = next.canonicalSides[3 - sideAxis(next, site.acrossSide) - sideAxis(next, site.alongSide)];
    if (side == site.acrossSide) {
        return FrameCrossing(SiteFrame(site.level, node, site.vertex, site.acrossSide, site.alongSide, cast(byte) -site.acrossSign, site.alongSign, site.heightSign), true);
    } else if (side == site.alongSide) {
        return FrameCrossing(SiteFrame(site.level, node, site.vertex, site.acrossSide, site.alongSide, site.acrossSign, cast(byte) -site.alongSign, site.heightSign), true);
    } else if (side == site.heightSide()) {
        return FrameCrossing(SiteFrame(site.level, node, site.vertex, site.acrossSide, site.alongSide, site.acrossSign, site.alongSign, cast(byte) -site.heightSign), true);
    } else if (side == far) {
        return FrameCrossing(SiteFrame(site.level + site.heightSign, node, next, site.acrossSide, site.alongSide, site.acrossSign, site.alongSign, site.heightSign), true);
    } else {
        return FrameCrossing(site, false);
    }
}

SiteFrame lowerFrame(ref const Graph graph, SiteFrame site) {
    ParentList parents = graph.parents(site.node);
    uint index = 0;
    while (index < parents.count && !crossedFrame(site, parents.links[index].side, parents.links[index].slot).isKept) {
        index += 1;
    }
    if (index < parents.count) {
        return crossedFrame(site, parents.links[index].side, parents.links[index].slot).site;
    } else {
        return site;
    }
}

CanonicalSite canonicalOf(ref const Graph graph, SiteFrame site) {
    SiteFrame entry = site;
    bool isLowest = false;
    while (!isLowest) {
        SiteFrame lower = graph.lowerFrame(entry);
        isLowest = lower.node == entry.node;
        entry = lower;
    }
    Vertex next = entry.nextVertex();
    Vertex lower = entry.vertex;
    if (next < lower) {
        lower = next;
    }
    Side first = entry.acrossSide;
    Side second = entry.alongSide;
    if (second < first) {
        first = entry.alongSide;
        second = entry.acrossSide;
    }
    bool isAtLower = entry.vertex == lower;
    byte heightSign = entry.heightSign;
    int vertexLevel = 0;
    if (!isAtLower) {
        heightSign = cast(byte) -entry.heightSign;
        vertexLevel = 1;
    }
    LineSpec line = LineSpec(int.max, int.min, entry.node, lower, first, second);
    return CanonicalSite(line, LineTransform(vertexLevel - heightSign * entry.level, entry.acrossSign, entry.alongSign, heightSign, entry.acrossSide != first));
}

struct ColumnChunk {
    size_t vertical;
    size_t across;
    size_t along;
    int acrossSign;
    int alongSign;
    int bottom;
    uint line;
    bool isUpward;

    static ColumnChunk fromTouch(ref const LineTouch touch, ref const LineSpec spec, Vertex vertex, ubyte dimension) {
        size_t acrossAxis = sideAxis(vertex, spec.acrossSide);
        size_t alongAxis = sideAxis(vertex, spec.alongSide);
        bool isLower = vertex == touch.lower;
        int level = touch.level + 1;
        if (isLower) {
            level = touch.level;
        }
        return ColumnChunk(3 - acrossAxis - alongAxis, acrossAxis, alongAxis, touch.acrossSign, touch.alongSign, level * edgeCells(dimension), touch.line, isLower);
    }

    int[3] columnOf(int[3] cell) const {
        int height = void;
        if (isUpward) {
            height = bottom + cell[vertical];
        } else {
            height = bottom - 1 - cell[vertical];
        }
        return [signedIndex(cell[across], acrossSign), signedIndex(cell[along], alongSign), height];
    }
}

bool isOnTouch(ref const LineTouch touch, ref const LineSpec spec, Vertex vertex) {
    bool isLowerInRange = vertex == touch.lower && isLevelInRange(spec, touch.level);
    bool isUpperInRange = vertex == upperOf(touch.lower, spec) && isLevelInRange(spec, touch.level + 1);
    return isLowerInRange || isUpperInRange;
}

struct ColumnSpot {
    float across = 0;
    float along = 0;
    float height = 0;
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

int edgeCells(ubyte dimension) {
    return 2 * dimension;
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

MPoint!float spawnBefore(ref const ChunkLayout layout, ColumnSpot door) {
    float beside = atanhf(signedDual(layout, door.along));
    float away = SPAWN_DISTANCE.value;
    return MPoint!float(MVector!float([-sinhf(away), 0, coshf(away) * sinhf(beside), coshf(away) * coshf(beside)]));
}

MIsometry!float sitePlacement(ref const SiteFrame site, ref const ChunkLayout layout) {
    Matrix4!float axes;
    axes.data[0][sideAxis(site.vertex, site.acrossSide)] = site.acrossSign;
    axes.data[1][sideAxis(site.vertex, site.heightSide())] = site.heightSign;
    axes.data[2][sideAxis(site.vertex, site.alongSide)] = site.alongSign;
    axes.data[3][3] = 1;
    float[3] toOrigin = [0, -site.level * edgeLength(layout).value, 0];
    return site.vertex.dualToNode * MIsometry!float(axes) * MIsometry!float.fromDisplacement(toOrigin);
}

SiteFrame lineSite(ref const LineSpec spec) {
    return SiteFrame(0, spec.node, spec.lower, spec.acrossSide, spec.alongSide, 1, 1, 1);
}

MIsometry!float siteToNode(ref const Graph graph, ref const SiteFrame site, uint slot) {
    return graph.nodeToNode(site.node, slot) * sitePlacement(site, graph.layout);
}

MIsometry!float lineToNode(ref const Graph graph, uint line, uint slot) {
    SiteFrame site = lineSite(graph.blueprint.lines.ptr[line]);
    return graph.siteToNode(site, slot);
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

size_t sideAxis(Vertex vertex, Side side) {
    size_t axis = 0;
    while (axis < 3 && vertex.canonicalSides[axis] != side) {
        axis += 1;
    }
    return axis;
}

Vertex firstVertexOn(Side side) {
    uint vertex = 0;
    while (vertex < VERTEX_COUNT && sideAxis(cast(Vertex) vertex, side) == 3) {
        vertex += 1;
    }
    return cast(Vertex) vertex;
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

Side firstSideAmong(ushort faces) {
    uint index = 0;
    while (index < SIDE_COUNT && (faces & faceBit(cast(Side) index)) == 0) {
        index += 1;
    }
    assert(index < SIDE_COUNT);
    return cast(Side) index;
}

uint anchorSlotOf(ref Graph graph) {
    uint sky = graph.ensureNeighborSlot(graph.slotOf(ROOT_NODE), Side.a);
    return graph.ensureNeighborSlot(sky, firstSideAmong(ringFaces(Side.a)));
}

ulong anchorBits(ref const Graph graph, uint slot) {
    return SplitMix(graph.idAt(slot).spice()).next();
}

float altitude(ref const NodeState state) {
    return state.surface.distanceTo(MPoint!float.origin());
}

bool isOnLineInFrame(ref const LineSpec spec, MPoint!float point, ref const ChunkLayout layout) {
    MVector!float q = point.vec;
    int level = cast(int) floorf(asinhf(q.data[1]) / edgeLength(layout).value + 0.5f);
    return Length(sqrt(q.data[0] * q.data[0] + q.data[2] * q.data[2])) < TEST_ON_LINE && isLevelInRange(spec, level);
}

bool hasTouchAt(ref const NodeStructure structure, ref const LineSpec spec, uint line, Vertex vertex) {
    uint index = 0;
    while (index < structure.count && !(structure.touches[index].line == line && isOnTouch(structure.touches[index], spec, vertex))) {
        index += 1;
    }
    return index < structure.count;
}

LineTouch touchOf(ref const NodeStructure structure, uint line) {
    uint index = 0;
    while (index < structure.count && structure.touches[index].line != line) {
        index += 1;
    }
    assert(index < structure.count);
    return structure.touches[index];
}

bool isSamePoint(MPoint!float a, MPoint!float b) {
    return -a.vec.normalizedPoint().mip(b.vec.normalizedPoint().vec) < coshf(TEST_TOLERANCE.value);
}

Graph testGraph() {
    return Graph.make(TEST_DIMENSION, Worldgen.fromStructure(StructureWorld.fromName("test")));
}

SiteFrame[8] testSites(ref Graph graph) {
    SiteFrame root = rootSite(graph.anchorSlot);
    SiteFrame[FACE_CORNERS] corners = graph.faceCorners(root);
    SiteFrame bridge = graph.branched(root, 1, true);
    return [
        root,
        bridge,
        graph.branched(root, 1, false),
        graph.branched(bridge, 1, true),
        graph.branched(root, 0, true),
        turned(corners[2], 1),
        shifted(graph.branched(corners[3], 2, false), -1),
        graph.branched(turned(corners[4], 3), -2, true),
    ];
}

unittest {
    Graph graph = testGraph();
    BlueprintBuilder builder = BlueprintBuilder.make(graph);
    SiteFrame[8] sites = graph.testSites();
    CellBox pillar = CellBox.make(-2, 1, -3, 0, -12, 30);
    foreach (site; sites[0 .. 4]) {
        builder.paint(site, pillar, EVERY_HEIGHT, Material.granite, false);
    }
    builder.paint(sites[4], CellBox.make(-6, 5, 0, 1, int.min, int.max), EVERY_HEIGHT, Material.granite, false);
    foreach (site; sites[5 .. $]) {
        builder.paint(site, pillar, EVERY_HEIGHT, Material.granite, false);
    }
    graph.place(builder.finish());
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.anchorSlot), MIsometry!float.identity()), TEST_RADIUS);
    uint touchedChunks = 0;
    foreach (node; nearby) {
        NodeStructure structure = graph.ensureStructureAt(node.slot);
        foreach (line, spec; graph.blueprint.lines.slice()) {
            MIsometry!float lineFromNode = graph.lineToNode(cast(uint) line, node.slot).inverse();
            foreach (index; 0 .. VERTEX_COUNT) {
                Vertex vertex = cast(Vertex) index;
                bool isOnLine = isOnLineInFrame(spec, lineFromNode * vertex.dualToNode * MPoint!float.origin(), graph.layout);
                assert(isOnLine == hasTouchAt(structure, spec, cast(uint) line, vertex));
                if (isOnLine) {
                    touchedChunks += 1;
                    LineTouch touch = touchOf(structure, cast(uint) line);
                    ColumnChunk chunk = ColumnChunk.fromTouch(touch, spec, vertex, TEST_DIMENSION);
                    foreach (cell; TEST_CELLS) {
                        int[3] column = chunk.columnOf(cell);
                        float[3] center = graph.layout.cellCenter(cell);
                        MPoint!float actual = MPoint!float(vertex.chunkToNode * MVector!float([center[0], center[1], center[2], 1.0f]));
                        MPoint!float expected = lineFromNode.inverse() * columnPoint(graph.layout, ColumnSpot(column[0] + 0.5f, column[1] + 0.5f, column[2] + 0.5f));
                        assert(isSamePoint(actual, expected));
                    }
                }
            }
        }
    }
    assert(touchedChunks >= 8 * graph.blueprint.lines.length);
    scratch.release();
    graph.release();
}

unittest {
    Graph graph = testGraph();
    SiteFrame[8] sites = graph.testSites();
    foreach (site; sites) {
        CanonicalSite canonical = graph.canonicalOf(site);
        SiteFrame line = lineSite(canonical.line);
        foreach (cell; TEST_CELLS) {
            int[3] local = [cell[0] - 6, cell[1] - 6, cell[2] - 20];
            CellBox moved = canonicalBox(CellBox(local, local), canonical.transform, TEST_DIMENSION);
            ColumnSpot fromSite = ColumnSpot(local[0] + 0.5f, local[1] + 0.5f, local[2] + 0.5f);
            ColumnSpot fromLine = ColumnSpot(moved.low[0] + 0.5f, moved.low[1] + 0.5f, moved.low[2] + 0.5f);
            assert(isSamePoint(graph.siteToNode(site, site.node) * columnPoint(graph.layout, fromSite), graph.siteToNode(line, site.node) * columnPoint(graph.layout, fromLine)));
        }
    }
    graph.release();
}

unittest {
    Graph graph = testGraph();
    SiteFrame[FACE_CORNERS] corners = graph.faceCorners(rootSite(graph.anchorSlot));
    SiteFrame closing = graph.nextCorner(corners[FACE_CORNERS - 1]);
    assert(isSamePoint(graph.siteToNode(closing, corners[0].node) * MPoint!float.origin(), graph.siteToNode(corners[0], corners[0].node) * MPoint!float.origin()));
    SiteFrame first = graph.branched(corners[0], 1, true);
    SiteFrame last = graph.branched(corners[1], 1, false);
    MPoint!float apex = columnPoint(graph.layout, ColumnSpot(-0.5f, 0.5f, edgeCells(TEST_DIMENSION) + 0.5f));
    assert(isSamePoint(graph.siteToNode(first, graph.anchorSlot) * apex, graph.siteToNode(last, graph.anchorSlot) * apex));
    graph.release();
}
