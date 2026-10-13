module common.worldgen.structure;

import core.math : sqrt;
import core.stdc.math : atanhf, coshf, fabsf, floorf;
import base.array : Array;
import base.units : Length;
import common.graph : Graph, NO_SLOT, NodeId, ParentList, ROOT_NODE;
import common.material : Material;
import common.node : ChunkLayout;
import common.position : Position;
import common.traversal : NearbyNode, NearbyScratch;
import common.view : GraphView;
import common.worldgen.blueprint : BlueprintBuilder, CellBox, EVERY_HEIGHT, LineSpec, PaintResult, canonicalBox, floorDivision;
import common.worldgen.generation : NodeState, SplitMix, StructureWorld, Worldgen;
import geometry.honeycomb : CORNER_COUNT, Corner, FACE_COUNT, FACE_DISTANCE, Face, across, cornerToNode, cubeToNode, faceBit, faces, isAdjacentTo, mirror;
import geometry.lorentz : Mat4, Motion, Point, Vec4;

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
enum uint TEST_DEEP_STEPS = 40;
enum uint TEST_SIDE_STRIDE = 5;
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
    Corner lower;
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
    Face side;
    byte sign;

    Axis opUnary(string op)() const if (op == "-") {
        return Axis(side, cast(byte) -sign);
    }
}

struct SiteFrame {
    int level;
    uint node;
    Corner corner;
    Face xSide;
    Face ySide;
    byte xSign;
    byte ySign;
    byte zSign;

    static SiteFrame fromAxes(int level, uint node, Corner corner, Axis x, Axis y, Axis z) {
        SiteFrame site = SiteFrame(level, node, corner, x.side, y.side, x.sign, y.sign, z.sign);
        assert(site.zSide() == z.side);
        return site;
    }

    Face zSide() const {
        return corner.faces[3 - sideAxis(corner, xSide) - sideAxis(corner, ySide)];
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

    Corner nextCorner() const {
        return corner.across[sideAxis(corner, zSide())];
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
        return (cast(size_t) slot * CORNER_COUNT + feature) * (SitePart.max + 1) + part;
    }
}

struct RootedCorner {
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

bool isOnTouch(ref const LineTouch touch, ref const LineSpec spec, Corner corner) {
    return (corner == touch.lower || corner == upperOf(touch.lower, spec)) && isTouchInRange(touch, spec);
}

TouchCrossing crossed(LineTouch touch, ref const LineSpec spec, Face side) {
    Corner upper = upperOf(touch.lower, spec);
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

Corner upperOf(Corner lower, ref const LineSpec spec) {
    return lower.across[crossingAxis(lower, spec)];
}

size_t crossingAxis(Corner corner, ref const LineSpec spec) {
    return 3 - sideAxis(corner, spec.xSide) - sideAxis(corner, spec.ySide);
}

Face crossingSide(Corner corner, ref const LineSpec spec) {
    return corner.faces[crossingAxis(corner, spec)];
}

void finalizeStructure(ref Graph graph, uint slot) {
    Array!LineTouch* found = &graph.structures.scratch;
    found.clear();
    const(uint)* head = graph.structures.pendingHeads.find(graph.idAt(slot));
    uint pending = head is null ? 0 : *head;
    while (pending != 0) {
        PendingTouch record = *graph.structures.pending.at(pending - 1);
        (*found).addUnique(record.touch);
        pending = record.next;
    }
    ParentList parents = graph.parents(slot);
    foreach (link; parents.links[0 .. parents.count]) {
        foreach (touch; graph.structures.touchesAt(link.slot)) {
            LineSpec spec = graph.structures.blueprint.lines.ptr[touch.line];
            if (spec.isEndless()) {
                TouchCrossing crossing = crossed(touch, spec, link.side);
                if (crossing.isKept) {
                    (*found).addUnique(crossing.touch);
                }
            }
        }
    }
    bool isInStructure = false;
    foreach (touch; found.slice()) {
        isInStructure = isInStructure || isTouchInRange(touch, graph.structures.blueprint.lines.ptr[touch.line]);
    }
    graph.structures.setTouches(slot, found.slice());
    graph.structures.at(slot).isInStructure = isInStructure;
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
    graph.addPendingTouch(graph.idAt(slot), touch);
}

void addPendingTouch(ref Graph graph, NodeId id, LineTouch touch) {
    assert(graph.slotOf(id) == NO_SLOT || !graph.isFinished(graph.slotOf(id)));
    graph.structures.addPending(id, touch);
}

SlotTouch seedTouch(ref const LineSpec spec, uint line) {
    return SlotTouch(LineTouch(0, line, spec.lower, 1, 1), spec.node);
}

SlotTouch walkedTouch(ref GraphView view, SlotTouch from, ref const LineSpec spec, int edge) {
    SlotTouch current = from;
    while (current.touch.level != edge) {
        Face side = crossingSide(current.touch.lower, spec);
        if (edge > current.touch.level) {
            side = crossingSide(upperOf(current.touch.lower, spec), spec);
        }
        current = SlotTouch(crossed(current.touch, spec, side).touch, view.ensureNeighborSlot(current.slot, side));
    }
    return current;
}

SlotTouch[EDGE_NODES] aroundEdge(ref GraphView view, SlotTouch edge, ref const LineSpec spec) {
    SlotTouch x = SlotTouch(crossed(edge.touch, spec, spec.xSide).touch, view.ensureNeighborSlot(edge.slot, spec.xSide));
    SlotTouch y = SlotTouch(crossed(edge.touch, spec, spec.ySide).touch, view.ensureNeighborSlot(edge.slot, spec.ySide));
    SlotTouch both = SlotTouch(crossed(y.touch, spec, spec.xSide).touch, view.ensureNeighborSlot(y.slot, spec.xSide));
    return [edge, x, y, both];
}

SiteFrame rootSite(uint anchor) {
    return faceSite(anchor, Face.f0);
}

SiteFrame faceSite(uint node, Face label) {
    return groundSite(node, firstCornerOn(label), label);
}

SiteFrame groundSite(uint node, Corner corner, Face label) {
    size_t up = sideAxis(corner, label);
    return SiteFrame(0, node, corner, corner.faces[(up + 1) % 3], label, 1, 1, 1);
}

SiteFrame forwarded(SiteFrame site, int edges) {
    return SiteFrame(site.level - edges, site.node, site.corner, site.xSide, site.ySide, site.xSign, site.ySign, site.zSign);
}

SiteFrame atLevel(ref GraphView view, SiteFrame site, int level) {
    SiteFrame result = site;
    while (result.level != level) {
        result = view.stepped(result, level > result.level);
    }
    return result;
}

SiteFrame stepped(ref GraphView view, SiteFrame site, bool isUp) {
    bool isInside = (site.zSign > 0) == isUp;
    if (isInside) {
        int rise = -1;
        if (isUp) {
            rise = 1;
        }
        return SiteFrame(site.level + rise, site.node, site.nextCorner(), site.xSide, site.ySide, site.xSign, site.ySign, cast(byte) -site.zSign);
    } else {
        uint across = view.ensureNeighborSlot(site.node, site.zSide());
        return SiteFrame(site.level, across, site.corner, site.xSide, site.ySide, site.xSign, site.ySign, cast(byte) -site.zSign);
    }
}

SiteFrame turned(ref GraphView view, SiteFrame site, Turn turn) {
    SiteFrame at = view.atLevel(site, 0);
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
    return SiteFrame.fromAxes(0, at.node, at.corner, axes[0], axes[1], axes[2]);
}

RootedCorner rootedCorner(ref const GraphView view, uint node, Corner corner) {
    uint slot = node;
    bool isLowest = false;
    while (!isLowest) {
        ParentList parents = view.parents(slot);
        uint index = 0;
        while (index < parents.count && sideAxis(corner, parents.links[index].side) == 3) {
            index += 1;
        }
        isLowest = index == parents.count;
        if (!isLowest) {
            slot = parents.links[index].slot;
        }
    }
    return RootedCorner(ClaimKey(slot, corner, SitePart.vertex), view.depthOf(slot));
}

RootedCorner siteOrigin(ref GraphView view, SiteFrame site) {
    SiteFrame origin = view.atLevel(site, 0);
    return view.rootedCorner(origin.node, origin.corner);
}

ClaimKey siteFace(ref GraphView view, SiteFrame site) {
    SiteFrame at = view.atLevel(site, 0);
    uint node = at.node;
    if (at.xSign < 0) {
        node = view.ensureNeighborSlot(node, at.xSide);
    }
    if (at.zSign < 0) {
        node = view.ensureNeighborSlot(node, at.zSide());
    }
    uint across = view.ensureNeighborSlot(node, at.ySide);
    if (view.depthOf(across) < view.depthOf(node)) {
        node = across;
    }
    return ClaimKey(node, at.ySide, SitePart.face);
}

ClaimKey claimKeyOf(ref GraphView view, SiteFrame site, SitePart part) {
    assert(part != SitePart.edge);
    if (part == SitePart.vertex) {
        return view.siteOrigin(site).key;
    } else {
        return view.siteFace(site);
    }
}

ulong siteHash(ref GraphView view, SiteFrame site, SitePart part) {
    ulong seed = void;
    final switch (part) {
        case SitePart.vertex:
        case SitePart.face:
            ClaimKey key = view.claimKeyOf(site, part);
            seed = mixedSeed(view.idAt(key.slot).spice(), key.feature, part);
            break;
        case SitePart.edge:
            seed = view.edgeSeed(site);
            break;
    }
    return SplitMix(seed).next();
}

ulong mixedSeed(ulong spice, uint feature, SitePart part) {
    return spice ^ ((cast(ulong) feature * (SitePart.max + 1) + part + 1) * HASH_MULTIPLIER);
}

ulong edgeSeed(ref GraphView view, SiteFrame site) {
    CanonicalSite canonical = view.canonicalOf(site);
    ubyte dimension = view.layout.dimension;
    int cells = edgeCells(dimension);
    CellBox edge = canonicalBox(CellBox.make(0, 0, 0, 0, 0, cells - 1), canonical.transform, dimension);
    ulong level = cast(uint) floorDivision(edge.low[2], cells);
    LineSpec line = canonical.line;
    uint feature = (line.lower * FACE_COUNT + line.xSide) * FACE_COUNT + line.ySide;
    return mixedSeed(view.idAt(line.node).spice() ^ (level * LEVEL_MULTIPLIER), feature, SitePart.edge);
}

uint[GROUND_RING] groundRing(ref GraphView view, uint sky, Face label) {
    uint[GROUND_RING] ring = void;
    uint count = 0;
    ring[count] = sky;
    count += 1;
    ushort faces = ringFaces(label);
    foreach (index; 0 .. FACE_COUNT) {
        Face side = cast(Face) index;
        if ((faces & faceBit(side)) != 0) {
            uint beside = view.ensureNeighborSlot(sky, side);
            ring[count] = beside;
            count += 1;
            foreach (otherIndex; index + 1 .. FACE_COUNT) {
                Face other = cast(Face) otherIndex;
                if ((faces & faceBit(other)) != 0 && side.isAdjacentTo(other)) {
                    ring[count] = view.ensureNeighborSlot(beside, other);
                    count += 1;
                }
            }
        }
    }
    assert(count == GROUND_RING);
    return ring;
}

FrameCrossing crossedFrame(SiteFrame site, Face side, uint node) {
    Corner next = site.nextCorner();
    Face far = next.faces[3 - sideAxis(next, site.xSide) - sideAxis(next, site.ySide)];
    if (side == site.xSide) {
        return FrameCrossing(SiteFrame(site.level, node, site.corner, site.xSide, site.ySide, cast(byte) -site.xSign, site.ySign, site.zSign), true);
    } else if (side == site.ySide) {
        return FrameCrossing(SiteFrame(site.level, node, site.corner, site.xSide, site.ySide, site.xSign, cast(byte) -site.ySign, site.zSign), true);
    } else if (side == site.zSide()) {
        return FrameCrossing(SiteFrame(site.level, node, site.corner, site.xSide, site.ySide, site.xSign, site.ySign, cast(byte) -site.zSign), true);
    } else if (side == far) {
        return FrameCrossing(SiteFrame(site.level + site.zSign, node, next, site.xSide, site.ySide, site.xSign, site.ySign, site.zSign), true);
    } else {
        return FrameCrossing(site, false);
    }
}

SiteFrame lowerFrame(ref const GraphView view, SiteFrame site) {
    ParentList parents = view.parents(site.node);
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

CanonicalSite canonicalOf(ref const GraphView view, SiteFrame site) {
    SiteFrame entry = site;
    bool isLowest = false;
    while (!isLowest) {
        SiteFrame lower = view.lowerFrame(entry);
        isLowest = lower.node == entry.node;
        entry = lower;
    }
    Corner next = entry.nextCorner();
    Corner lower = entry.corner;
    if (next < lower) {
        lower = next;
    }
    Face first = entry.xSide;
    Face second = entry.ySide;
    if (second < first) {
        first = entry.ySide;
        second = entry.xSide;
    }
    bool isAtLower = entry.corner == lower;
    byte zSign = entry.zSign;
    int cornerLevel = 0;
    if (!isAtLower) {
        zSign = cast(byte) -entry.zSign;
        cornerLevel = 1;
    }
    LineSpec line = LineSpec(int.max, int.min, entry.node, lower, first, second);
    return CanonicalSite(line, LineTransform(cornerLevel - zSign * entry.level, entry.xSign, entry.ySign, zSign, entry.xSide != first));
}

struct ColumnChunk {
    size_t zAxis;
    size_t xAxis;
    size_t yAxis;
    int xSign;
    int ySign;
    int bottom;
    bool isUpward;

    static ColumnChunk fromTouch(ref const LineTouch touch, ref const LineSpec spec, Corner corner, ubyte dimension) {
        size_t xAxis = sideAxis(corner, spec.xSide);
        size_t yAxis = sideAxis(corner, spec.ySide);
        bool isLower = corner == touch.lower;
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

float signedKlein(ref const ChunkLayout layout, float grid) {
    if (grid < 0) {
        return -layout.gridToKlein(-grid);
    } else {
        return layout.gridToKlein(grid);
    }
}

Length edgeLength(ref const ChunkLayout layout) {
    return Length(2.0f * atanhf(layout.gridToKlein(layout.dimension)));
}

int edgeCells(ubyte dimension) {
    return 2 * dimension;
}

Point!float columnPoint(ref const ChunkLayout layout, ColumnSpot spot) {
    float segmentCells = edgeCells(layout.dimension);
    float segment = floorf(spot.z / segmentCells);
    float local = spot.z - segment * segmentCells;
    float rise = layout.gridToKlein(local);
    float level = segment;
    if (local > layout.dimension) {
        rise = -layout.gridToKlein(segmentCells - local);
        level = segment + 1;
    }
    Point!float inCornerFrame = Vec4!float([signedKlein(layout, spot.x), signedKlein(layout, spot.y), rise, 1.0f]).toPoint();
    float[3] lift = [0, 0, level * edgeLength(layout).value];
    return Motion!float.shift(lift) * inCornerFrame;
}

Point!float spawnBefore(ref const ChunkLayout layout, ColumnSpot door) {
    float[3] away = [-SPAWN_DISTANCE.value, 0, 0];
    return Motion!float.shiftTo(columnPoint(layout, door)) * Motion!float.shift(away) * Point!float.origin();
}

Motion!float sitePlacement(ref const SiteFrame site, ref const ChunkLayout layout) {
    Mat4!float axes;
    axes.c[0][sideAxis(site.corner, site.xSide)] = site.xSign;
    axes.c[1][sideAxis(site.corner, site.ySide)] = site.ySign;
    axes.c[2][sideAxis(site.corner, site.zSide())] = site.zSign;
    axes.c[3][3] = 1;
    float[3] toOrigin = [0, 0, -site.level * edgeLength(layout).value];
    return site.corner.cornerToNode * Motion!float(axes) * Motion!float.shift(toOrigin);
}

SiteFrame lineSite(ref const LineSpec spec) {
    return SiteFrame(0, spec.node, spec.lower, spec.xSide, spec.ySide, 1, 1, 1);
}

Motion!float siteToNode(ref const GraphView view, ref const SiteFrame site, uint slot) {
    return view.nodeToNode(site.node, slot) * sitePlacement(site, view.layout);
}

Motion!float lineToNode(ref const GraphView view, uint line, uint slot) {
    SiteFrame site = lineSite(view.blueprint.lines.ptr[line]);
    return view.siteToNode(site, slot);
}

Motion!float nodeToNode(ref const GraphView view, uint from, uint to) {
    Array!Face toPath = view.sidesToRoot(to);
    Array!Face fromPath = view.sidesToRoot(from);
    Array!Face path;
    foreach (side; toPath.slice()) {
        path.appendReduced(side);
    }
    foreach_reverse (side; fromPath.slice()) {
        path.appendReduced(side);
    }
    Motion!double transform = Motion!double.identity();
    foreach (side; path.slice()) {
        transform = transform * side.mirror.as!double();
    }
    toPath.release();
    fromPath.release();
    path.release();
    return transform.as!float();
}

void appendReduced(ref Array!Face path, Face side) {
    size_t index = path.length;
    while (index > 0 && path.ptr[index - 1] != side && path.ptr[index - 1].isAdjacentTo(side)) {
        index -= 1;
    }
    if (index > 0 && path.ptr[index - 1] == side) {
        foreach (moved; index .. path.length) {
            path.ptr[moved - 1] = path.ptr[moved];
        }
        path.length -= 1;
    } else {
        path.append(side);
    }
}

size_t sideAxis(Corner corner, Face side) {
    size_t axis = 0;
    while (axis < 3 && corner.faces[axis] != side) {
        axis += 1;
    }
    return axis;
}

Corner firstCornerOn(Face side) {
    uint corner = 0;
    while (corner < CORNER_COUNT && sideAxis(cast(Corner) corner, side) == 3) {
        corner += 1;
    }
    return cast(Corner) corner;
}

ushort ringFaces(Face straight) {
    ushort ring = 0;
    foreach (index; 0 .. FACE_COUNT) {
        if ((cast(Face) index).isAdjacentTo(straight)) {
            ring |= faceBit(cast(Face) index);
        }
    }
    return ring;
}

Face firstSideAmong(ushort faces) {
    uint index = 0;
    while (index < FACE_COUNT && (faces & faceBit(cast(Face) index)) == 0) {
        index += 1;
    }
    assert(index < FACE_COUNT);
    return cast(Face) index;
}

uint anchorSlotOf(ref Graph graph) {
    uint sky = graph.ensureNeighborSlot(graph.slotOf(ROOT_NODE), Face.f0);
    return graph.ensureNeighborSlot(sky, firstSideAmong(ringFaces(Face.f0)));
}

ulong anchorBits(ref const Graph graph, uint slot) {
    return SplitMix(graph.idAt(slot).spice()).next();
}

float altitude(ref const NodeState state) {
    return state.surface.height;
}

bool isOnLineInFrame(ref const LineSpec spec, Point!float corner, Point!float center, ref const ChunkLayout layout) {
    Vec4!float q = corner.v;
    Vec4!float c = center.v;
    int level = cast(int) floorf(atanhf(c.c[2] / c.c[3]) / edgeLength(layout).value);
    return Length(sqrt(q.c[0] * q.c[0] + q.c[1] * q.c[1])) < TEST_ON_LINE && isLevelInRange(spec, level);
}

bool hasTouchAt(ref const Graph graph, uint slot, uint line, Corner corner) {
    const(LineTouch)[] touches = graph.structures.touchesAt(slot);
    uint index = 0;
    while (index < touches.length && !(touches[index].line == line && isOnTouch(touches[index], graph.structures.blueprint.lines.ptr[line], corner))) {
        index += 1;
    }
    return index < touches.length;
}

LineTouch touchOf(ref const Graph graph, uint slot, uint line) {
    const(LineTouch)[] touches = graph.structures.touchesAt(slot);
    uint index = 0;
    while (index < touches.length && touches[index].line != line) {
        index += 1;
    }
    assert(index < touches.length);
    return touches[index];
}

bool isSamePoint(Point!float a, Point!float b) {
    return -a.v.toPoint().minkowski(b.v.toPoint().v) < coshf(TEST_TOLERANCE.value);
}

Graph testGraph() {
    return Graph.make(TEST_DIMENSION, Worldgen.fromStructure(StructureWorld.fromName("test")));
}

SiteFrame[FACE_CORNERS] faceWalk(ref Graph graph, SiteFrame start) {
    SiteFrame[FACE_CORNERS] corners = void;
    corners[0] = start;
    foreach (index; 1 .. FACE_CORNERS) {
        corners[index] = graph.view.turned(forwarded(corners[index - 1], 1), Turn.right);
    }
    return corners;
}

SiteFrame[8] testSites(ref Graph graph) {
    SiteFrame ground = rootSite(graph.anchorSlot);
    SiteFrame tower = graph.view.turned(ground, Turn.pitchUp);
    SiteFrame bridge = graph.view.turned(forwarded(tower, 1), Turn.pitchDown);
    SiteFrame corner = graph.faceWalk(ground)[2];
    return [
        tower,
        bridge,
        graph.view.turned(bridge, Turn.right),
        graph.view.turned(forwarded(bridge, 1), Turn.pitchDown),
        ground,
        graph.view.turned(corner, Turn.rollLeft),
        forwarded(graph.view.turned(forwarded(corner, 2), Turn.pitchUp), -1),
        graph.view.turned(forwarded(graph.view.turned(corner, Turn.left), -2), Turn.pitchUp),
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
    NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.anchorSlot), Motion!float.identity()), TEST_RADIUS);
    uint touchedChunks = 0;
    foreach (node; nearby) {
        graph.ensureStructureAt(node.slot);
        foreach (line, spec; graph.structures.blueprint.lines.slice()) {
            Motion!float lineFromNode = graph.view.lineToNode(cast(uint) line, node.slot).inverse();
            Point!float center = lineFromNode * Point!float.origin();
            foreach (index; 0 .. CORNER_COUNT) {
                Corner corner = cast(Corner) index;
                bool isOnLine = isOnLineInFrame(spec, lineFromNode * corner.cornerToNode * Point!float.origin(), center, graph.layout);
                assert(isOnLine == graph.hasTouchAt(node.slot, cast(uint) line, corner));
                if (isOnLine) {
                    touchedChunks += 1;
                    LineTouch touch = graph.touchOf(node.slot, cast(uint) line);
                    ColumnChunk chunk = ColumnChunk.fromTouch(touch, spec, corner, TEST_DIMENSION);
                    foreach (cell; TEST_CELLS) {
                        int[3] column = chunk.columnOf(cell);
                        float[3] cellCenter = graph.layout.cellCenter(cell);
                        Point!float actual = Point!float(corner.cubeToNode * Vec4!float([cellCenter[0], cellCenter[1], cellCenter[2], 1.0f]));
                        Point!float expected = lineFromNode.inverse() * columnPoint(graph.layout, ColumnSpot(column[0] + 0.5f, column[1] + 0.5f, column[2] + 0.5f));
                        assert(isSamePoint(actual, expected));
                    }
                }
            }
        }
    }
    assert(touchedChunks >= 8 * graph.structures.blueprint.lines.length);
    builder.release();
    scratch.release();
    graph.release();
}

bool isCanonicalMatch(ref Graph graph, SiteFrame site) {
    CanonicalSite canonical = graph.view.canonicalOf(site);
    SiteFrame line = lineSite(canonical.line);
    bool isMatch = true;
    foreach (cell; TEST_CELLS) {
        int[3] local = [cell[0] - 6, cell[1] - 6, cell[2] - 20];
        CellBox moved = canonicalBox(CellBox(local, local), canonical.transform, TEST_DIMENSION);
        ColumnSpot fromSite = ColumnSpot(local[0] + 0.5f, local[1] + 0.5f, local[2] + 0.5f);
        ColumnSpot fromLine = ColumnSpot(moved.low[0] + 0.5f, moved.low[1] + 0.5f, moved.low[2] + 0.5f);
        isMatch = isMatch && isSamePoint(graph.view.siteToNode(site, site.node) * columnPoint(graph.layout, fromSite), graph.view.siteToNode(line, site.node) * columnPoint(graph.layout, fromLine));
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
    SiteFrame tower = graph.view.turned(rootSite(graph.anchorSlot), Turn.pitchUp);
    SiteFrame down = graph.view.turned(graph.view.turned(forwarded(tower, TEST_RISE_EDGES), Turn.pitchUp), Turn.pitchUp);
    SiteFrame top = graph.view.atLevel(forwarded(tower, TEST_RISE_EDGES), 0);
    SiteFrame ground = groundSite(top.node, top.corner, top.zSide());
    SiteFrame quarter = graph.view.turned(ground, Turn.right);
    SiteFrame[5] sites = [
        down,
        graph.view.turned(down, Turn.rollRight),
        graph.view.turned(graph.view.turned(ground, Turn.pitchUp), Turn.rollRight),
        graph.view.turned(graph.view.turned(quarter, Turn.pitchUp), Turn.rollRight),
        forwarded(graph.view.turned(graph.view.turned(quarter, Turn.pitchUp), Turn.rollRight), TEST_RISE_EDGES),
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
    SiteFrame closed = graph.view.turned(forwarded(corners[FACE_CORNERS - 1], 1), Turn.right);
    Point!float origin = Point!float.origin();
    assert(isSamePoint(graph.view.siteToNode(closed, start.node) * origin, graph.view.siteToNode(start, start.node) * origin));
    assert(!isSamePoint(graph.view.siteToNode(corners[2], start.node) * origin, graph.view.siteToNode(start, start.node) * origin));
    assert(graph.view.siteOrigin(closed).key == graph.view.siteOrigin(start).key);
    assert(graph.view.siteOrigin(corners[2]).key != graph.view.siteOrigin(start).key);
    ClaimKey block = graph.view.siteFace(start);
    foreach (corner; corners) {
        assert(graph.view.siteFace(corner) == block);
    }
    SiteFrame across = graph.view.turned(corners[1], Turn.right);
    assert(graph.view.siteFace(across) != block);
    assert(graph.view.siteFace(graph.faceWalk(across)[3]) == graph.view.siteFace(across));
    SiteFrame back = graph.view.turned(graph.view.turned(forwarded(start, 1), Turn.right), Turn.right);
    ulong edge = graph.view.siteHash(start, SitePart.edge);
    assert(graph.view.siteHash(back, SitePart.edge) == edge);
    assert(graph.view.siteHash(graph.view.turned(start, Turn.rollLeft), SitePart.edge) == edge);
    assert(graph.view.siteHash(corners[1], SitePart.edge) != edge);
    assert(graph.view.siteHash(closed, SitePart.vertex) == graph.view.siteHash(start, SitePart.vertex));
    assert(graph.view.siteHash(corners[3], SitePart.face) == graph.view.siteHash(start, SitePart.face));
    assert(graph.view.siteHash(start, SitePart.face) != graph.view.siteHash(start, SitePart.vertex));
    SiteFrame first = graph.view.turned(forwarded(graph.view.turned(corners[0], Turn.pitchUp), 1), Turn.pitchDown);
    SiteFrame last = graph.view.turned(graph.view.turned(forwarded(graph.view.turned(corners[1], Turn.pitchUp), 1), Turn.pitchDown), Turn.right);
    Point!float apex = columnPoint(graph.layout, ColumnSpot(-0.5f, 0.5f, edgeCells(TEST_DIMENSION) + 0.5f));
    Point!float mirroredApex = columnPoint(graph.layout, ColumnSpot(0.5f, 0.5f, edgeCells(TEST_DIMENSION) + 0.5f));
    assert(isSamePoint(graph.view.siteToNode(first, graph.anchorSlot) * apex, graph.view.siteToNode(last, graph.anchorSlot) * mirroredApex));
    foreach (turn; [Turn.left, Turn.pitchUp, Turn.rollRight]) {
        SiteFrame spun = start;
        foreach (_; 0 .. 4) {
            spun = graph.view.turned(spun, turn);
        }
        assert(spun == start);
    }
    graph.release();
}

unittest {
    Graph graph = testGraph();
    uint deep = graph.anchorSlot;
    foreach (step; 0 .. TEST_DEEP_STEPS) {
        uint index = step * TEST_SIDE_STRIDE;
        while (graph.isParentFace(deep, cast(Face)(index % FACE_COUNT))) {
            index += 1;
        }
        deep = graph.ensureNeighborSlot(deep, cast(Face)(index % FACE_COUNT));
    }
    assert(graph.depthOf(deep) > TEST_DEEP_STEPS);
    foreach (index; 0 .. FACE_COUNT) {
        Face side = cast(Face) index;
        uint beside = graph.ensureNeighborSlot(deep, side);
        assert(isSamePoint(graph.view.nodeToNode(beside, deep) * Point!float.origin(), side.mirror * Point!float.origin()));
        Face turn = cast(Face)((index + TEST_SIDE_STRIDE) % FACE_COUNT);
        uint corner = graph.ensureNeighborSlot(beside, turn);
        assert(isSamePoint(graph.view.nodeToNode(corner, deep) * Point!float.origin(), side.mirror * turn.mirror * Point!float.origin()));
        if (side.isAdjacentTo(turn)) {
            assert(graph.ensureNeighborSlot(graph.ensureNeighborSlot(deep, turn), side) == corner);
        }
    }
    graph.release();
}

unittest {
    Graph graph = testGraph();
    uint[GROUND_RING] ring = graph.view.groundRing(graph.anchorSlot, Face.f0);
    foreach (index, slot; ring) {
        assert(fabsf(altitude(*graph.ensureState(slot)) - FACE_DISTANCE) < TEST_TOLERANCE.value);
        foreach (other; ring[index + 1 .. $]) {
            assert(other != slot);
        }
    }
    graph.release();
}

unittest {
    Graph graph = testGraph();
    BlueprintBuilder builder = BlueprintBuilder.make(graph);
    SiteFrame tower = graph.view.turned(rootSite(graph.anchorSlot), Turn.pitchUp);
    SiteFrame high = forwarded(tower, TEST_BEHIND_EDGES);
    builder.growFrom(graph.view.siteOrigin(high).depth);
    assert(builder.paint(tower, CellBox.make(0, 0, 0, 0, 0, 1), EVERY_HEIGHT, Material.granite, false) == PaintResult.behind);
    assert(builder.paint(high, CellBox.make(0, 0, 0, 0, int.min, 1), EVERY_HEIGHT, Material.granite, false) == PaintResult.endless);
    assert(builder.paint(high, CellBox.make(0, 0, 0, 0, 0, 1), EVERY_HEIGHT, Material.granite, false) == PaintResult.painted);
    builder.release();
    graph.release();
}
