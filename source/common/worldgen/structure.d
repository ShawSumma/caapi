module common.worldgen.structure;

import core.math : sqrt;
import core.stdc.math : atanhf, coshf, fabsf, floorf;
import common.array : Array;
import common.dodeca : SIDE_COUNT, Side, VERTEX_COUNT, Vertex, adjacentVertices, canonicalSides, chunkToNode, dualToNode, faceDistance, isAdjacentTo, reflection;
import common.graph : Graph, Node, NodeId, ParentList, ROOT_NODE;
import common.material : Material;
import common.math : MIsometry, MPoint, MVector, Matrix4;
import common.node : ChunkLayout;
import common.position : Position;
import common.traversal : NearbyNode, NearbyScratch;
import common.units : Length;
import common.worldgen.blueprint : BlueprintBuilder, CellBox, EVERY_HEIGHT, LineSpec, PaintResult, canonicalBox, floorDivision;
import common.worldgen.generation : NodeState, NodeStateKind, SplitMix, StructureWorld, Worldgen;

enum int PAINT_REACH = 6;
enum uint GROUND_RING = 11;
enum ulong HASH_MULTIPLIER = 0x9E3779B97F4A7C15;
enum ulong LEVEL_MULTIPLIER = 0xBF58476D1CE4E5B9;
enum int PLACE_SLACK = 2;
enum float TOUCHING_FACTOR = 1.5f;
enum Length SPAWN_DISTANCE = Length(1.0f);
enum uint FACE_CORNERS = 5;
enum uint EDGE_NODES = 4;
enum ubyte TEST_DIMENSION = 12;
enum float TEST_RADIUS = 3.0f;
enum Length TEST_TOLERANCE = Length(0.01f);
enum Length TEST_ON_LINE = Length(1e-3f);
enum int TEST_BEHIND_EDGES = 10;
enum int TEST_RISE_EDGES = 3;
immutable int[3][4] TEST_CELLS = [
    [0, 0, 0],
    [3, 1, 2],
    [11, 5, 0],
    [2, 11, 9],
];

enum Turn : ubyte {
    left,
    right,
    pitchUp,
    pitchDown,
    rollLeft,
    rollRight,
}

struct LineTouch {
    int level;
    uint line;
    Vertex lower;
    byte xSign;
    byte ySign;
}

struct PendingTouch {
    LineTouch touch;
    uint next;
}

struct TouchCrossing {
    LineTouch touch;
    bool isKept;
}

struct SlotTouch {
    LineTouch touch;
    uint slot;
}

struct Axis {
    Side side;
    byte sign;

    Axis opUnary(string op)() const if (op == "-") {
        return Axis(side, cast(byte) -sign);
    }
}

struct SiteFrame {
    int level;
    uint node;
    Vertex vertex;
    Side xSide;
    Side ySide;
    byte xSign;
    byte ySign;
    byte zSign;

    static SiteFrame fromAxes(int level, uint node, Vertex vertex, Axis x, Axis y, Axis z) {
        SiteFrame site = SiteFrame(level, node, vertex, x.side, y.side, x.sign, y.sign, z.sign);
        assert(site.zSide() == z.side);
        return site;
    }

    Side zSide() const {
        return vertex.canonicalSides[3 - sideAxis(vertex, xSide) - sideAxis(vertex, ySide)];
    }

    Axis x() const {
        return Axis(xSide, xSign);
    }

    Axis y() const {
        return Axis(ySide, ySign);
    }

    Axis z() const {
        return Axis(zSide(), zSign);
    }

    Vertex nextVertex() const {
        return vertex.adjacentVertices[sideAxis(vertex, zSide())];
    }
}

struct FrameCrossing {
    SiteFrame site;
    bool isKept;
}

struct LineTransform {
    int offsetLevels;
    byte xSign;
    byte ySign;
    byte zSign;
    bool isSwapped;
}

struct CanonicalSite {
    LineSpec line;
    LineTransform transform;
}

enum SitePart : ubyte {
    vertex,
    face,
    edge,
}

struct ClaimKey {
    uint slot;
    ubyte feature;
    SitePart part;

    size_t toHash() const {
        return (cast(size_t) slot * VERTEX_COUNT + feature) * (SitePart.max + 1) + part;
    }
}

struct RootedVertex {
    ClaimKey key;
    uint depth;
}

bool isEndless(ref const LineSpec spec) {
    return spec.lowest == int.min || spec.highest == int.max;
}

bool isTouchInRange(ref const LineTouch touch, ref const LineSpec spec) {
    return isLevelInRange(spec, touch.level);
}

bool isLevelInRange(ref const LineSpec spec, int level) {
    return level >= spec.lowest && level <= spec.highest;
}

bool isOnTouch(ref const LineTouch touch, ref const LineSpec spec, Vertex vertex) {
    return (vertex == touch.lower || vertex == upperOf(touch.lower, spec)) && isTouchInRange(touch, spec);
}

TouchCrossing crossed(LineTouch touch, ref const LineSpec spec, Side side) {
    Vertex upper = upperOf(touch.lower, spec);
    if (side == spec.xSide) {
        return TouchCrossing(LineTouch(touch.level, touch.line, touch.lower, cast(byte) -touch.xSign, touch.ySign), true);
    } else if (side == spec.ySide) {
        return TouchCrossing(LineTouch(touch.level, touch.line, touch.lower, touch.xSign, cast(byte) -touch.ySign), true);
    } else if (side == crossingSide(touch.lower, spec)) {
        return TouchCrossing(LineTouch(touch.level - 1, touch.line, upper, touch.xSign, touch.ySign), true);
    } else if (side == crossingSide(upper, spec)) {
        return TouchCrossing(LineTouch(touch.level + 1, touch.line, upper, touch.xSign, touch.ySign), true);
    } else {
        return TouchCrossing(touch, false);
    }
}

Vertex upperOf(Vertex lower, ref const LineSpec spec) {
    return lower.adjacentVertices[crossingAxis(lower, spec)];
}

size_t crossingAxis(Vertex vertex, ref const LineSpec spec) {
    return 3 - sideAxis(vertex, spec.xSide) - sideAxis(vertex, spec.ySide);
}

Side crossingSide(Vertex vertex, ref const LineSpec spec) {
    return vertex.canonicalSides[crossingAxis(vertex, spec)];
}

void finalizeStructure(ref Graph graph, uint slot) {
    graph.touchScratch.clear();
    const(uint)* head = graph.pendingHeads.find(graph.idAt(slot));
    uint pending = head is null ? 0 : *head;
    while (pending != 0) {
        PendingTouch record = *graph.pendingTouches.at(pending - 1);
        graph.touchScratch.addUnique(record.touch);
        pending = record.next;
    }
    ParentList parents = graph.parents(slot);
    foreach (link; parents.links[0 .. parents.count]) {
        foreach (touch; graph.touchesAt(link.slot)) {
            LineSpec spec = graph.blueprint.lines.ptr[touch.line];
            if (spec.isEndless()) {
                TouchCrossing crossing = crossed(touch, spec, link.side);
                if (crossing.isKept) {
                    graph.touchScratch.addUnique(crossing.touch);
                }
            }
        }
    }
    uint start = graph.reserveTouches(cast(uint) graph.touchScratch.length);
    bool isInStructure = false;
    foreach (index, touch; graph.touchScratch.slice()) {
        *graph.touches.at(start + index) = touch;
        isInStructure = isInStructure || isTouchInRange(touch, graph.blueprint.lines.ptr[touch.line]);
    }
    Node* node = graph.nodeAt(slot);
    node.touchStart = start;
    node.touchLength = cast(uint) graph.touchScratch.length;
    node.isInStructure = isInStructure;
}

void addUnique(ref Array!LineTouch touches, LineTouch touch) {
    uint index = 0;
    while (index < touches.length && touches.ptr[index].line < touch.line) {
        index += 1;
    }
    if (index == touches.length || touches.ptr[index].line != touch.line) {
        touches.append(touch);
        foreach_reverse (moved; index .. touches.length - 1) {
            touches.ptr[moved + 1] = touches.ptr[moved];
        }
        touches.ptr[index] = touch;
    }
}

void addPendingTouch(ref Graph graph, uint slot, LineTouch touch) {
    assert(!graph.nodeAt(slot).hasStructure);
    NodeId id = graph.idAt(slot);
    const(uint)* head = graph.pendingHeads.find(id);
    uint index = graph.pendingCount;
    graph.pendingTouches.ensure(index + 1);
    *graph.pendingTouches.at(index) = PendingTouch(touch, head is null ? 0 : *head);
    graph.pendingHeads.insert(id, index + 1);
    graph.pendingCount += 1;
}

SlotTouch seedTouch(ref const LineSpec spec, uint line) {
    return SlotTouch(LineTouch(0, line, spec.lower, 1, 1), spec.node);
}

SlotTouch walkedTouch(ref Graph graph, SlotTouch from, ref const LineSpec spec, int edge) {
    SlotTouch current = from;
    while (current.touch.level != edge) {
        Side side = crossingSide(current.touch.lower, spec);
        if (edge > current.touch.level) {
            side = crossingSide(upperOf(current.touch.lower, spec), spec);
        }
        current = SlotTouch(crossed(current.touch, spec, side).touch, graph.ensureNeighborSlot(current.slot, side));
    }
    return current;
}

SlotTouch[EDGE_NODES] aroundEdge(ref Graph graph, SlotTouch edge, ref const LineSpec spec) {
    SlotTouch x = SlotTouch(crossed(edge.touch, spec, spec.xSide).touch, graph.ensureNeighborSlot(edge.slot, spec.xSide));
    SlotTouch y = SlotTouch(crossed(edge.touch, spec, spec.ySide).touch, graph.ensureNeighborSlot(edge.slot, spec.ySide));
    SlotTouch both = SlotTouch(crossed(y.touch, spec, spec.xSide).touch, graph.ensureNeighborSlot(y.slot, spec.xSide));
    return [edge, x, y, both];
}

SiteFrame rootSite(uint anchor) {
    return faceSite(anchor, Side.a);
}

SiteFrame faceSite(uint node, Side label) {
    return groundSite(node, firstVertexOn(label), label);
}

SiteFrame groundSite(uint node, Vertex vertex, Side label) {
    size_t up = sideAxis(vertex, label);
    return SiteFrame(0, node, vertex, vertex.canonicalSides[(up + 1) % 3], label, 1, 1, 1);
}

SiteFrame forwarded(SiteFrame site, int edges) {
    return SiteFrame(site.level - edges, site.node, site.vertex, site.xSide, site.ySide, site.xSign, site.ySign, site.zSign);
}

SiteFrame atLevel(ref Graph graph, SiteFrame site, int level) {
    SiteFrame result = site;
    while (result.level != level) {
        result = graph.stepped(result, level > result.level);
    }
    return result;
}

SiteFrame stepped(ref Graph graph, SiteFrame site, bool isUp) {
    bool isInside = (site.zSign > 0) == isUp;
    if (isInside) {
        int rise = -1;
        if (isUp) {
            rise = 1;
        }
        return SiteFrame(site.level + rise, site.node, site.nextVertex(), site.xSide, site.ySide, site.xSign, site.ySign, cast(byte) -site.zSign);
    } else {
        uint across = graph.ensureNeighborSlot(site.node, site.zSide());
        return SiteFrame(site.level, across, site.vertex, site.xSide, site.ySide, site.xSign, site.ySign, cast(byte) -site.zSign);
    }
}

SiteFrame turned(ref Graph graph, SiteFrame site, Turn turn) {
    SiteFrame at = graph.atLevel(site, 0);
    Axis x = at.x();
    Axis y = at.y();
    Axis z = at.z();
    Axis[3] axes = void;
    final switch (turn) {
        case Turn.left:
            axes = [z, y, -x];
            break;
        case Turn.right:
            axes = [-z, y, x];
            break;
        case Turn.pitchUp:
            axes = [x, -z, y];
            break;
        case Turn.pitchDown:
            axes = [x, z, -y];
            break;
        case Turn.rollLeft:
            axes = [y, -x, z];
            break;
        case Turn.rollRight:
            axes = [-y, x, z];
            break;
    }
    return SiteFrame.fromAxes(0, at.node, at.vertex, axes[0], axes[1], axes[2]);
}

RootedVertex rootedVertex(ref const Graph graph, uint node, Vertex vertex) {
    uint slot = node;
    bool isLowest = false;
    while (!isLowest) {
        ParentList parents = graph.parents(slot);
        uint index = 0;
        while (index < parents.count && sideAxis(vertex, parents.links[index].side) == 3) {
            index += 1;
        }
        isLowest = index == parents.count;
        if (!isLowest) {
            slot = parents.links[index].slot;
        }
    }
    return RootedVertex(ClaimKey(slot, vertex, SitePart.vertex), graph.nodeAt(slot).depth);
}

RootedVertex siteOrigin(ref Graph graph, SiteFrame site) {
    SiteFrame origin = graph.atLevel(site, 0);
    return graph.rootedVertex(origin.node, origin.vertex);
}

ClaimKey siteFace(ref Graph graph, SiteFrame site) {
    SiteFrame at = graph.atLevel(site, 0);
    uint node = at.node;
    if (at.xSign < 0) {
        node = graph.ensureNeighborSlot(node, at.xSide);
    }
    if (at.zSign < 0) {
        node = graph.ensureNeighborSlot(node, at.zSide());
    }
    uint across = graph.ensureNeighborSlot(node, at.ySide);
    if (graph.nodeAt(across).depth < graph.nodeAt(node).depth) {
        node = across;
    }
    return ClaimKey(node, at.ySide, SitePart.face);
}

ClaimKey claimKeyOf(ref Graph graph, SiteFrame site, SitePart part) {
    assert(part != SitePart.edge);
    if (part == SitePart.vertex) {
        return graph.siteOrigin(site).key;
    } else {
        return graph.siteFace(site);
    }
}

ulong siteHash(ref Graph graph, SiteFrame site, SitePart part) {
    ulong seed = void;
    final switch (part) {
        case SitePart.vertex:
        case SitePart.face:
            ClaimKey key = graph.claimKeyOf(site, part);
            seed = mixedSeed(graph.idAt(key.slot).spice(), key.feature, part);
            break;
        case SitePart.edge:
            seed = graph.edgeSeed(site);
            break;
    }
    return SplitMix(seed).next();
}

ulong mixedSeed(ulong spice, uint feature, SitePart part) {
    return spice ^ ((cast(ulong) feature * (SitePart.max + 1) + part + 1) * HASH_MULTIPLIER);
}

ulong edgeSeed(ref Graph graph, SiteFrame site) {
    CanonicalSite canonical = graph.canonicalOf(site);
    ubyte dimension = graph.layout.dimension;
    int cells = edgeCells(dimension);
    CellBox edge = canonicalBox(CellBox.make(0, 0, 0, 0, 0, cells - 1), canonical.transform, dimension);
    ulong level = cast(uint) floorDivision(edge.low[2], cells);
    LineSpec line = canonical.line;
    uint feature = (line.lower * SIDE_COUNT + line.xSide) * SIDE_COUNT + line.ySide;
    return mixedSeed(graph.idAt(line.node).spice() ^ (level * LEVEL_MULTIPLIER), feature, SitePart.edge);
}

uint[GROUND_RING] groundRing(ref Graph graph, uint sky, Side label) {
    uint[GROUND_RING] ring = void;
    uint count = 0;
    ring[count] = sky;
    count += 1;
    ushort faces = ringFaces(label);
    foreach (index; 0 .. SIDE_COUNT) {
        Side side = cast(Side) index;
        if ((faces & faceBit(side)) != 0) {
            uint beside = graph.ensureNeighborSlot(sky, side);
            ring[count] = beside;
            count += 1;
            foreach (otherIndex; index + 1 .. SIDE_COUNT) {
                Side other = cast(Side) otherIndex;
                if ((faces & faceBit(other)) != 0 && side.isAdjacentTo(other)) {
                    ring[count] = graph.ensureNeighborSlot(beside, other);
                    count += 1;
                }
            }
        }
    }
    assert(count == GROUND_RING);
    return ring;
}

FrameCrossing crossedFrame(SiteFrame site, Side side, uint node) {
    Vertex next = site.nextVertex();
    Side far = next.canonicalSides[3 - sideAxis(next, site.xSide) - sideAxis(next, site.ySide)];
    if (side == site.xSide) {
        return FrameCrossing(SiteFrame(site.level, node, site.vertex, site.xSide, site.ySide, cast(byte) -site.xSign, site.ySign, site.zSign), true);
    } else if (side == site.ySide) {
        return FrameCrossing(SiteFrame(site.level, node, site.vertex, site.xSide, site.ySide, site.xSign, cast(byte) -site.ySign, site.zSign), true);
    } else if (side == site.zSide()) {
        return FrameCrossing(SiteFrame(site.level, node, site.vertex, site.xSide, site.ySide, site.xSign, site.ySign, cast(byte) -site.zSign), true);
    } else if (side == far) {
        return FrameCrossing(SiteFrame(site.level + site.zSign, node, next, site.xSide, site.ySide, site.xSign, site.ySign, site.zSign), true);
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
    Side first = entry.xSide;
    Side second = entry.ySide;
    if (second < first) {
        first = entry.ySide;
        second = entry.xSide;
    }
    bool isAtLower = entry.vertex == lower;
    byte zSign = entry.zSign;
    int vertexLevel = 0;
    if (!isAtLower) {
        zSign = cast(byte) -entry.zSign;
        vertexLevel = 1;
    }
    LineSpec line = LineSpec(int.max, int.min, entry.node, lower, first, second);
    return CanonicalSite(line, LineTransform(vertexLevel - zSign * entry.level, entry.xSign, entry.ySign, zSign, entry.xSide != first));
}

struct ColumnChunk {
    size_t zAxis;
    size_t xAxis;
    size_t yAxis;
    int xSign;
    int ySign;
    int bottom;
    bool isUpward;

    static ColumnChunk fromTouch(ref const LineTouch touch, ref const LineSpec spec, Vertex vertex, ubyte dimension) {
        size_t xAxis = sideAxis(vertex, spec.xSide);
        size_t yAxis = sideAxis(vertex, spec.ySide);
        bool isLower = vertex == touch.lower;
        int level = touch.level + 1;
        if (isLower) {
            level = touch.level;
        }
        return ColumnChunk(3 - xAxis - yAxis, xAxis, yAxis, touch.xSign, touch.ySign, level * edgeCells(dimension), isLower);
    }

    int[3] columnOf(int[3] cell) const {
        int z = void;
        if (isUpward) {
            z = bottom + cell[zAxis];
        } else {
            z = bottom - 1 - cell[zAxis];
        }
        return [signedIndex(cell[xAxis], xSign), signedIndex(cell[yAxis], ySign), z];
    }
}

struct ColumnSpot {
    float x = 0;
    float y = 0;
    float z = 0;
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
    float segment = floorf(spot.z / segmentCells);
    float local = spot.z - segment * segmentCells;
    float rise = layout.gridToDual(local);
    float level = segment;
    if (local > layout.dimension) {
        rise = -layout.gridToDual(segmentCells - local);
        level = segment + 1;
    }
    MPoint!float inVertexFrame = MVector!float([signedDual(layout, spot.x), signedDual(layout, spot.y), rise, 1.0f]).normalizedPoint();
    float[3] lift = [0, 0, level * edgeLength(layout).value];
    return MIsometry!float.fromDisplacement(lift) * inVertexFrame;
}

MPoint!float spawnBefore(ref const ChunkLayout layout, ColumnSpot door) {
    float[3] away = [-SPAWN_DISTANCE.value, 0, 0];
    return MIsometry!float.fromTranslation(MPoint!float.origin(), columnPoint(layout, door)) * MIsometry!float.fromDisplacement(away) * MPoint!float.origin();
}

MIsometry!float sitePlacement(ref const SiteFrame site, ref const ChunkLayout layout) {
    Matrix4!float axes;
    axes.data[0][sideAxis(site.vertex, site.xSide)] = site.xSign;
    axes.data[1][sideAxis(site.vertex, site.ySide)] = site.ySign;
    axes.data[2][sideAxis(site.vertex, site.zSide())] = site.zSign;
    axes.data[3][3] = 1;
    float[3] toOrigin = [0, 0, -site.level * edgeLength(layout).value];
    return site.vertex.dualToNode * MIsometry!float(axes) * MIsometry!float.fromDisplacement(toOrigin);
}

SiteFrame lineSite(ref const LineSpec spec) {
    return SiteFrame(0, spec.node, spec.lower, spec.xSide, spec.ySide, 1, 1, 1);
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

bool isOnLineInFrame(ref const LineSpec spec, MPoint!float vertex, MPoint!float center, ref const ChunkLayout layout) {
    MVector!float q = vertex.vec;
    MVector!float c = center.vec;
    int level = cast(int) floorf(atanhf(c.data[2] / c.data[3]) / edgeLength(layout).value);
    return Length(sqrt(q.data[0] * q.data[0] + q.data[1] * q.data[1])) < TEST_ON_LINE && isLevelInRange(spec, level);
}

bool hasTouchAt(ref const Graph graph, uint slot, uint line, Vertex vertex) {
    const(LineTouch)[] touches = graph.touchesAt(slot);
    uint index = 0;
    while (index < touches.length && !(touches[index].line == line && isOnTouch(touches[index], graph.blueprint.lines.ptr[line], vertex))) {
        index += 1;
    }
    return index < touches.length;
}

LineTouch touchOf(ref const Graph graph, uint slot, uint line) {
    const(LineTouch)[] touches = graph.touchesAt(slot);
    uint index = 0;
    while (index < touches.length && touches[index].line != line) {
        index += 1;
    }
    assert(index < touches.length);
    return touches[index];
}

bool isSamePoint(MPoint!float a, MPoint!float b) {
    return -a.vec.normalizedPoint().mip(b.vec.normalizedPoint().vec) < coshf(TEST_TOLERANCE.value);
}

Graph testGraph() {
    return Graph.make(TEST_DIMENSION, Worldgen.fromStructure(StructureWorld.fromName("test")));
}

SiteFrame[FACE_CORNERS] faceWalk(ref Graph graph, SiteFrame start) {
    SiteFrame[FACE_CORNERS] corners = void;
    corners[0] = start;
    foreach (index; 1 .. FACE_CORNERS) {
        corners[index] = graph.turned(forwarded(corners[index - 1], 1), Turn.right);
    }
    return corners;
}

SiteFrame[8] testSites(ref Graph graph) {
    SiteFrame ground = rootSite(graph.anchorSlot);
    SiteFrame tower = graph.turned(ground, Turn.pitchUp);
    SiteFrame bridge = graph.turned(forwarded(tower, 1), Turn.pitchDown);
    SiteFrame corner = graph.faceWalk(ground)[2];
    return [
        tower,
        bridge,
        graph.turned(bridge, Turn.right),
        graph.turned(forwarded(bridge, 1), Turn.pitchDown),
        ground,
        graph.turned(corner, Turn.rollLeft),
        forwarded(graph.turned(forwarded(corner, 2), Turn.pitchUp), -1),
        graph.turned(forwarded(graph.turned(corner, Turn.left), -2), Turn.pitchUp),
    ];
}

unittest {
    Graph graph = testGraph();
    BlueprintBuilder builder = BlueprintBuilder.make(graph);
    SiteFrame[8] sites = graph.testSites();
    CellBox pillar = CellBox.make(-2, 1, -3, 0, -12, 30);
    foreach (site; sites[0 .. 4]) {
        assert(builder.paint(site, pillar, EVERY_HEIGHT, Material.granite, false) == PaintResult.painted);
    }
    assert(builder.paint(sites[4], CellBox.make(-6, 5, 0, 1, int.min, int.max), EVERY_HEIGHT, Material.granite, false) == PaintResult.painted);
    foreach (site; sites[5 .. $]) {
        assert(builder.paint(site, pillar, EVERY_HEIGHT, Material.granite, false) == PaintResult.painted);
    }
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.anchorSlot), MIsometry!float.identity()), TEST_RADIUS);
    uint touchedChunks = 0;
    foreach (node; nearby) {
        graph.ensureStructureAt(node.slot);
        foreach (line, spec; graph.blueprint.lines.slice()) {
            MIsometry!float lineFromNode = graph.lineToNode(cast(uint) line, node.slot).inverse();
            MPoint!float center = lineFromNode * MPoint!float.origin();
            foreach (index; 0 .. VERTEX_COUNT) {
                Vertex vertex = cast(Vertex) index;
                bool isOnLine = isOnLineInFrame(spec, lineFromNode * vertex.dualToNode * MPoint!float.origin(), center, graph.layout);
                assert(isOnLine == graph.hasTouchAt(node.slot, cast(uint) line, vertex));
                if (isOnLine) {
                    touchedChunks += 1;
                    LineTouch touch = graph.touchOf(node.slot, cast(uint) line);
                    ColumnChunk chunk = ColumnChunk.fromTouch(touch, spec, vertex, TEST_DIMENSION);
                    foreach (cell; TEST_CELLS) {
                        int[3] column = chunk.columnOf(cell);
                        float[3] cellCenter = graph.layout.cellCenter(cell);
                        MPoint!float actual = MPoint!float(vertex.chunkToNode * MVector!float([cellCenter[0], cellCenter[1], cellCenter[2], 1.0f]));
                        MPoint!float expected = lineFromNode.inverse() * columnPoint(graph.layout, ColumnSpot(column[0] + 0.5f, column[1] + 0.5f, column[2] + 0.5f));
                        assert(isSamePoint(actual, expected));
                    }
                }
            }
        }
    }
    assert(touchedChunks >= 8 * graph.blueprint.lines.length);
    builder.release();
    scratch.release();
    graph.release();
}

bool isCanonicalMatch(ref Graph graph, SiteFrame site) {
    CanonicalSite canonical = graph.canonicalOf(site);
    SiteFrame line = lineSite(canonical.line);
    bool isMatch = true;
    foreach (cell; TEST_CELLS) {
        int[3] local = [cell[0] - 6, cell[1] - 6, cell[2] - 20];
        CellBox moved = canonicalBox(CellBox(local, local), canonical.transform, TEST_DIMENSION);
        ColumnSpot fromSite = ColumnSpot(local[0] + 0.5f, local[1] + 0.5f, local[2] + 0.5f);
        ColumnSpot fromLine = ColumnSpot(moved.low[0] + 0.5f, moved.low[1] + 0.5f, moved.low[2] + 0.5f);
        isMatch = isMatch && isSamePoint(graph.siteToNode(site, site.node) * columnPoint(graph.layout, fromSite), graph.siteToNode(line, site.node) * columnPoint(graph.layout, fromLine));
    }
    return isMatch;
}

unittest {
    Graph graph = testGraph();
    SiteFrame[8] sites = graph.testSites();
    foreach (site; sites) {
        assert(graph.isCanonicalMatch(site));
    }
    graph.release();
}

unittest {
    Graph graph = testGraph();
    SiteFrame tower = graph.turned(rootSite(graph.anchorSlot), Turn.pitchUp);
    SiteFrame down = graph.turned(graph.turned(forwarded(tower, TEST_RISE_EDGES), Turn.pitchUp), Turn.pitchUp);
    SiteFrame top = graph.atLevel(forwarded(tower, TEST_RISE_EDGES), 0);
    SiteFrame ground = groundSite(top.node, top.vertex, top.zSide());
    SiteFrame quarter = graph.turned(ground, Turn.right);
    SiteFrame[5] sites = [
        down,
        graph.turned(down, Turn.rollRight),
        graph.turned(graph.turned(ground, Turn.pitchUp), Turn.rollRight),
        graph.turned(graph.turned(quarter, Turn.pitchUp), Turn.rollRight),
        forwarded(graph.turned(graph.turned(quarter, Turn.pitchUp), Turn.rollRight), TEST_RISE_EDGES),
    ];
    foreach (site; sites) {
        assert(graph.isCanonicalMatch(site));
    }
    graph.release();
}

unittest {
    Graph graph = testGraph();
    SiteFrame start = rootSite(graph.anchorSlot);
    SiteFrame[FACE_CORNERS] corners = graph.faceWalk(start);
    SiteFrame closed = graph.turned(forwarded(corners[FACE_CORNERS - 1], 1), Turn.right);
    MPoint!float origin = MPoint!float.origin();
    assert(isSamePoint(graph.siteToNode(closed, start.node) * origin, graph.siteToNode(start, start.node) * origin));
    assert(!isSamePoint(graph.siteToNode(corners[2], start.node) * origin, graph.siteToNode(start, start.node) * origin));
    assert(graph.siteOrigin(closed).key == graph.siteOrigin(start).key);
    assert(graph.siteOrigin(corners[2]).key != graph.siteOrigin(start).key);
    ClaimKey block = graph.siteFace(start);
    foreach (corner; corners) {
        assert(graph.siteFace(corner) == block);
    }
    SiteFrame across = graph.turned(corners[1], Turn.right);
    assert(graph.siteFace(across) != block);
    assert(graph.siteFace(graph.faceWalk(across)[3]) == graph.siteFace(across));
    SiteFrame back = graph.turned(graph.turned(forwarded(start, 1), Turn.right), Turn.right);
    ulong edge = graph.siteHash(start, SitePart.edge);
    assert(graph.siteHash(back, SitePart.edge) == edge);
    assert(graph.siteHash(graph.turned(start, Turn.rollLeft), SitePart.edge) == edge);
    assert(graph.siteHash(corners[1], SitePart.edge) != edge);
    assert(graph.siteHash(closed, SitePart.vertex) == graph.siteHash(start, SitePart.vertex));
    assert(graph.siteHash(corners[3], SitePart.face) == graph.siteHash(start, SitePart.face));
    assert(graph.siteHash(start, SitePart.face) != graph.siteHash(start, SitePart.vertex));
    SiteFrame first = graph.turned(forwarded(graph.turned(corners[0], Turn.pitchUp), 1), Turn.pitchDown);
    SiteFrame last = graph.turned(graph.turned(forwarded(graph.turned(corners[1], Turn.pitchUp), 1), Turn.pitchDown), Turn.right);
    MPoint!float apex = columnPoint(graph.layout, ColumnSpot(-0.5f, 0.5f, edgeCells(TEST_DIMENSION) + 0.5f));
    MPoint!float mirroredApex = columnPoint(graph.layout, ColumnSpot(0.5f, 0.5f, edgeCells(TEST_DIMENSION) + 0.5f));
    assert(isSamePoint(graph.siteToNode(first, graph.anchorSlot) * apex, graph.siteToNode(last, graph.anchorSlot) * mirroredApex));
    foreach (turn; [Turn.left, Turn.pitchUp, Turn.rollRight]) {
        SiteFrame spun = start;
        foreach (_; 0 .. 4) {
            spun = graph.turned(spun, turn);
        }
        assert(spun == start);
    }
    graph.release();
}

unittest {
    Graph graph = testGraph();
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.anchorSlot), MIsometry!float.identity()), TEST_RADIUS);
    foreach (node; nearby) {
        NodeState state = *graph.ensureNodeStateAt(node.slot);
        bool isDeep = state.kind == NodeStateKind.deepSky || state.kind == NodeStateKind.deepLand;
        assert(isDeep == (fabsf(altitude(state)) >= TOUCHING_FACTOR * faceDistance()));
    }
    scratch.release();
    graph.release();
}

unittest {
    Graph graph = testGraph();
    uint[GROUND_RING] ring = graph.groundRing(graph.anchorSlot, Side.a);
    foreach (index, slot; ring) {
        assert(graph.ensureNodeStateAt(slot).kind == NodeStateKind.sky);
        foreach (other; ring[index + 1 .. $]) {
            assert(other != slot);
        }
    }
    graph.release();
}

unittest {
    Graph graph = testGraph();
    BlueprintBuilder builder = BlueprintBuilder.make(graph);
    SiteFrame tower = graph.turned(rootSite(graph.anchorSlot), Turn.pitchUp);
    SiteFrame high = forwarded(tower, TEST_BEHIND_EDGES);
    builder.growFrom(graph.siteOrigin(high).depth);
    assert(builder.paint(tower, CellBox.make(0, 0, 0, 0, 0, 1), EVERY_HEIGHT, Material.granite, false) == PaintResult.behind);
    assert(builder.paint(high, CellBox.make(0, 0, 0, 0, int.min, 1), EVERY_HEIGHT, Material.granite, false) == PaintResult.endless);
    assert(builder.paint(high, CellBox.make(0, 0, 0, 0, 0, 1), EVERY_HEIGHT, Material.granite, false) == PaintResult.painted);
    builder.release();
    graph.release();
}
