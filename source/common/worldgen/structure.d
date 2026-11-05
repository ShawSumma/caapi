module common.worldgen.structure;

import core.stdc.math : atanhf, floorf;
import base.array : Array;
import base.hashmap : FIBONACCI_MULTIPLIER;
import base.maybe : Maybe;
import base.numbers : clamped, higherOf, lowerOf;
import base.splitmix : SplitMix;
import base.units : Length;
import common.graph : Graph, NO_SLOT, NodeId, ParentEntry, ParentList, ROOT_NODE;
import common.node : ChunkLayout;
import common.view : GraphView;
import common.worldgen.blueprint : CellBox, LineSpec, canonicalBox, floorDivision;
import common.worldgen.generation : NodeState;
import common.worldgen.store : NodeMark, pin;
import geometry.honeycomb : CORNER_COUNT, Corner, FACE_COUNT, Face, across, cornerToNode, faceBit, faces, isAdjacentTo, mirror;
import geometry.lorentz : Mat4, Motion, Point, Vec4;
import plugins.api.api : Site, SitePart, Turn;

enum int PAINT_REACH = 6;
enum uint GROUND_RING = 11;
enum ulong LEVEL_MULTIPLIER = 0xBF58476D1CE4E5B9;
enum int PLACE_SLACK = 2;
enum float TOUCHING_FACTOR = 1.5f;
enum Length SPAWN_DISTANCE = Length(1.0f);
enum uint EDGE_NODES = 4;
enum uint NODE_EDGES = 30;
enum float FLAT_RADIUS = 1.8f;
enum float FLAT_BLEND = 1.4f;
enum uint FLAT_DEPTH_SPAN = 8;

struct LineTouch {
    int level;
    uint line;
    Corner lower;
    byte xSign;
    byte ySign;
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

Site siteOf(SiteFrame frame) {
    return Site(frame.level, frame.node, frame.corner, frame.xSide, frame.ySide, frame.xSign, frame.ySign, frame.zSign);
}

SiteFrame frameOf(Site site) {
    return SiteFrame(site.level, site.node, cast(Corner) site.corner, cast(Face) site.xSide, cast(Face) site.ySide, site.xSign, site.ySign, site.zSign);
}

enum AxisOrder : ubyte {
    straight,
    swapped,
}

struct LineTransform {
    int offsetLevels;
    byte xSign;
    byte ySign;
    byte zSign;
    AxisOrder order;
}

struct CanonicalSite {
    LineSpec line;
    LineTransform transform;
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

Maybe!LineTouch crossed(LineTouch touch, ref const LineSpec spec, Face side) {
    Corner upper = upperOf(touch.lower, spec);
    if (side == spec.xSide) {
        return Maybe!LineTouch.of(LineTouch(touch.level, touch.line, touch.lower, cast(byte) -touch.xSign, touch.ySign));
    } else if (side == spec.ySide) {
        return Maybe!LineTouch.of(LineTouch(touch.level, touch.line, touch.lower, touch.xSign, cast(byte) -touch.ySign));
    } else if (side == crossingSide(touch.lower, spec)) {
        return Maybe!LineTouch.of(LineTouch(touch.level - 1, touch.line, upper, touch.xSign, touch.ySign));
    } else if (side == crossingSide(upper, spec)) {
        return Maybe!LineTouch.of(LineTouch(touch.level + 1, touch.line, upper, touch.xSign, touch.ySign));
    } else {
        return Maybe!LineTouch.init;
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
    foreach_reverse (touch; graph.structures.pendingAt(graph.idAt(slot))) {
        (*found).addUnique(touch);
    }
    ParentList parents = graph.parents(slot);
    foreach (link; parents.links[0 .. parents.count]) {
        foreach (touch; graph.structures.touchesAt(link.slot)) {
            LineSpec spec = graph.structures.blueprint.lines.ptr[touch.line];
            if (spec.isEndless()) {
                Maybe!LineTouch crossing = crossed(touch, spec, link.side);
                if (crossing.exists) {
                    (*found).addUnique(crossing.value);
                }
            }
        }
    }
    graph.structures.setTouches(slot, found.slice());
    graph.structures.at(slot).marks.put(NodeMark.inStructure, graph.hasTouchInRange(found.slice()));
    graph.structures.at(slot).marks.put(NodeMark.strokes, graph.structures.strokes.reachesAt(graph.idAt(slot)).length > 0);
    if (graph.structures.at(slot).needsBuilding()) {
        graph.pin(slot);
    }
}

bool hasTouchInRange(ref const Graph graph, const(LineTouch)[] touches) {
    foreach (touch; touches) {
        if (isTouchInRange(touch, graph.structures.blueprint.lines.ptr[touch.line])) {
            return true;
        }
    }
    return false;
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
        current = SlotTouch(crossed(current.touch, spec, side).value, view.ensureNeighborSlot(current.slot, side));
    }
    return current;
}

SlotTouch[EDGE_NODES] aroundEdge(ref GraphView view, SlotTouch edge, ref const LineSpec spec) {
    SlotTouch x = SlotTouch(crossed(edge.touch, spec, spec.xSide).value, view.ensureNeighborSlot(edge.slot, spec.xSide));
    SlotTouch y = SlotTouch(crossed(edge.touch, spec, spec.ySide).value, view.ensureNeighborSlot(edge.slot, spec.ySide));
    SlotTouch both = SlotTouch(crossed(y.touch, spec, spec.xSide).value, view.ensureNeighborSlot(y.slot, spec.xSide));
    return [edge, x, y, both];
}

SiteFrame rootSite(uint anchor) {
    return faceSite(anchor, Face.first);
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
    int rise = 1;
    if (level < site.level) {
        rise = -1;
    }
    SiteFrame result = site;
    while (result.level != level) {
        result = view.stepped(result, rise);
    }
    return result;
}

SiteFrame stepped(ref GraphView view, SiteFrame site, int rise) {
    if (site.zSign * rise > 0) {
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

Maybe!ParentEntry parentOnCorner(ParentList parents, Corner corner) {
    foreach (link; parents.links[0 .. parents.count]) {
        if (sideAxis(corner, link.side) != 3) {
            return Maybe!ParentEntry.of(link);
        }
    }
    return Maybe!ParentEntry.init;
}

Maybe!ParentEntry parentThrough(ParentList parents, Face first, Face second) {
    foreach (link; parents.links[0 .. parents.count]) {
        if (link.side == first || link.side == second) {
            return Maybe!ParentEntry.of(link);
        }
    }
    return Maybe!ParentEntry.init;
}

RootedCorner rootedCorner(ref const GraphView view, uint node, Corner corner) {
    uint slot = node;
    Maybe!ParentEntry lower = parentOnCorner(view.parents(slot), corner);
    while (lower.exists) {
        slot = lower.value.slot;
        lower = parentOnCorner(view.parents(slot), corner);
    }
    return RootedCorner(ClaimKey(slot, corner, SitePart.vertex), view.depthOf(slot));
}

SiteFrame edgeSite(ref const GraphView view, uint node, Corner corner, size_t axis) {
    Face first = corner.faces[(axis + 1) % 3];
    Face second = corner.faces[(axis + 2) % 3];
    uint slot = node;
    Maybe!ParentEntry lower = parentThrough(view.parents(slot), first, second);
    while (lower.exists) {
        slot = lower.value.slot;
        lower = parentThrough(view.parents(slot), first, second);
    }
    return SiteFrame(0, slot, lowerOf(corner, corner.across[axis]), lowerOf(first, second), higherOf(first, second), 1, 1, 1);
}

SiteFrame[NODE_EDGES] edgeSitesOf(ref const GraphView view, uint node) {
    SiteFrame[NODE_EDGES] sites = void;
    uint count = 0;
    foreach (index; 0 .. CORNER_COUNT) {
        Corner corner = cast(Corner) index;
        foreach (axis; 0 .. 3) {
            if (corner < corner.across[axis]) {
                sites[count] = view.edgeSite(node, corner, axis);
                count += 1;
            }
        }
    }
    assert(count == NODE_EDGES);
    return sites;
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
    return spice ^ ((cast(ulong) feature * (SitePart.max + 1) + part + 1) * FIBONACCI_MULTIPLIER);
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

Maybe!SiteFrame crossedFrame(SiteFrame site, Face side, uint node) {
    Corner next = site.nextCorner();
    Face far = next.faces[3 - sideAxis(next, site.xSide) - sideAxis(next, site.ySide)];
    if (side == site.xSide) {
        return Maybe!SiteFrame.of(SiteFrame(site.level, node, site.corner, site.xSide, site.ySide, cast(byte) -site.xSign, site.ySign, site.zSign));
    } else if (side == site.ySide) {
        return Maybe!SiteFrame.of(SiteFrame(site.level, node, site.corner, site.xSide, site.ySide, site.xSign, cast(byte) -site.ySign, site.zSign));
    } else if (side == site.zSide()) {
        return Maybe!SiteFrame.of(SiteFrame(site.level, node, site.corner, site.xSide, site.ySide, site.xSign, site.ySign, cast(byte) -site.zSign));
    } else if (side == far) {
        return Maybe!SiteFrame.of(SiteFrame(site.level + site.zSign, node, next, site.xSide, site.ySide, site.xSign, site.ySign, site.zSign));
    } else {
        return Maybe!SiteFrame.init;
    }
}

SiteFrame lowerFrame(ref const GraphView view, SiteFrame site) {
    ParentList parents = view.parents(site.node);
    foreach (link; parents.links[0 .. parents.count]) {
        Maybe!SiteFrame crossing = crossedFrame(site, link.side, link.slot);
        if (crossing.exists) {
            return crossing.value;
        }
    }
    return site;
}

CanonicalSite canonicalOf(ref const GraphView view, SiteFrame site) {
    SiteFrame entry = site;
    SiteFrame below = view.lowerFrame(entry);
    while (below.node != entry.node) {
        entry = below;
        below = view.lowerFrame(entry);
    }
    Corner lower = lowerOf(entry.nextCorner(), entry.corner);
    Face first = entry.xSide;
    Face second = entry.ySide;
    AxisOrder order = AxisOrder.straight;
    if (second < first) {
        first = entry.ySide;
        second = entry.xSide;
        order = AxisOrder.swapped;
    }
    byte zSign = entry.zSign;
    int cornerLevel = 0;
    if (entry.corner != lower) {
        zSign = cast(byte) -entry.zSign;
        cornerLevel = 1;
    }
    LineSpec line = LineSpec(int.max, int.min, entry.node, lower, first, second);
    return CanonicalSite(line, LineTransform(cornerLevel - zSign * entry.level, entry.xSign, entry.ySign, zSign, order));
}

struct ColumnChunk {
    size_t zAxis;
    size_t xAxis;
    size_t yAxis;
    int xSign;
    int ySign;
    int zSign;
    int bottom;

    static ColumnChunk fromTouch(ref const LineTouch touch, ref const LineSpec spec, Corner corner, ubyte dimension) {
        size_t xAxis = sideAxis(corner, spec.xSide);
        size_t yAxis = sideAxis(corner, spec.ySide);
        if (corner == touch.lower) {
            return ColumnChunk(3 - xAxis - yAxis, xAxis, yAxis, touch.xSign, touch.ySign, 1, touch.level * edgeCells(dimension));
        } else {
            return ColumnChunk(3 - xAxis - yAxis, xAxis, yAxis, touch.xSign, touch.ySign, -1, (touch.level + 1) * edgeCells(dimension));
        }
    }

    int[3] columnOf(int[3] cell) const {
        return [signedIndex(cell[xAxis], xSign), signedIndex(cell[yAxis], ySign), bottom + signedIndex(cell[zAxis], zSign)];
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
    Array!Face path = view.pathBetween(from, to);
    Motion!double transform = Motion!double.identity();
    foreach (side; path.slice()) {
        transform = transform * side.mirror.as!double();
    }
    path.release();
    return transform.as!float();
}

Array!Face pathBetween(ref const GraphView view, uint from, uint to) {
    Array!Face toPath;
    Array!Face fromPath;
    uint toward = to;
    uint away = from;
    while (toward != away) {
        if (view.depthOf(toward) >= view.depthOf(away)) {
            ParentEntry parent = view.parents(toward).links[0];
            toPath.append(parent.side);
            toward = parent.slot;
        } else {
            ParentEntry parent = view.parents(away).links[0];
            fromPath.append(parent.side);
            away = parent.slot;
        }
    }
    Array!Face path;
    foreach (side; toPath.slice()) {
        path.appendReduced(side);
    }
    foreach_reverse (side; fromPath.slice()) {
        path.appendReduced(side);
    }
    toPath.release();
    fromPath.release();
    return path;
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
    uint sky = graph.ensureNeighborSlot(graph.slotOf(ROOT_NODE), Face.first);
    return graph.ensureNeighborSlot(sky, firstSideAmong(ringFaces(Face.first)));
}

ulong anchorBits(ref const Graph graph, uint slot) {
    return SplitMix(graph.idAt(slot).spice()).next();
}

float calmAt(ref const GraphView view, uint node) {
    float calm = 1;
    foreach (ref flat; view.blueprint.flats.slice()) {
        uint here = view.depthOf(node);
        uint there = view.depthOf(flat.node);
        if (here <= there + FLAT_DEPTH_SPAN && there <= here + FLAT_DEPTH_SPAN) {
            float away = (view.siteToNode(flat, node) * Point!float.origin()).distance(Point!float.origin());
            float share = clamped((away - FLAT_RADIUS) / FLAT_BLEND, 0.0f, 1.0f);
            calm = lowerOf(calm, share * share * (3 - 2 * share));
        }
    }
    return calm;
}

float altitude(ref const NodeState state) {
    return state.surface.height;
}
