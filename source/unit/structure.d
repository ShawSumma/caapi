module unit.structure;

import core.math : sqrt;
import core.stdc.math : atanhf, coshf, fabsf, floorf;
import base.units : Length;
import common.graph : Graph;
import common.position : Position;
import common.traversal : NearbyNode, NearbyScratch;
import common.worldgen.blueprint : BlueprintBuilder, CellBox, Cover, EVERY_HEIGHT, LineSpec, PaintResult, canonicalBox;
import common.worldgen.generation : StructureWorld, Worldgen;
import common.worldgen.structure : CanonicalSite, ColumnChunk, ColumnSpot, GROUND_RING, LineTouch, NODE_EDGES, SiteFrame, altitude, canonicalOf, columnPoint, edgeCells, edgeLength, edgeSite, edgeSitesOf, forwarded, groundRing, groundSite, isLevelInRange, isOnTouch, lineSite, lineToNode, nodeToNode, rootSite, sideAxis, siteFace, siteHash, siteOrigin, siteToNode, atLevel, turned;
import geometry.honeycomb : CORNER_COUNT, Corner, FACE_COUNT, FACE_DISTANCE, Face, across, cornerToNode, cubeToNode, faces, isAdjacentTo, mirror;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : Material, SitePart, Turn;

enum uint FACE_CORNERS = 5;
enum ubyte DIMENSION = 12;
enum float RADIUS = 3.0f;
enum Length TOLERANCE = Length(0.01f);
enum Length ON_LINE = Length(1e-3f);
enum int BEHIND_EDGES = 10;
enum int RISE_EDGES = 3;
enum uint DEEP_STEPS = 40;
enum uint SIDE_STRIDE = 5;
immutable Face[3] EDGE_WALK = [Face.f3, Face.f7, Face.f1];
immutable int[3][4] CELLS = [
    [0, 0, 0],
    [3, 1, 2],
    [11, 5, 0],
    [2, 11, 9],
];

bool isOnLineInFrame(ref const LineSpec spec, Point!float corner, Point!float center, ref const typeof(Graph.layout) layout) {
    Vec4!float q = corner.v;
    Vec4!float c = center.v;
    int level = cast(int) floorf(atanhf(c.c[2] / c.c[3]) / edgeLength(layout).value);
    return Length(sqrt(q.c[0] * q.c[0] + q.c[1] * q.c[1])) < ON_LINE && isLevelInRange(spec, level);
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
    return -a.v.toPoint().minkowski(b.v.toPoint().v) < coshf(TOLERANCE.value);
}

Graph testGraph() {
    return Graph.make(DIMENSION, Worldgen.fromStructure(StructureWorld.fromName("test")));
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
        assert(builder.paint(site, pillar, EVERY_HEIGHT, Material.granite, Cover.over) == PaintResult.painted);
    }
    assert(builder.paint(sites[4], CellBox.make(-6, 5, 0, 1, int.min, int.max), EVERY_HEIGHT, Material.granite, Cover.over) == PaintResult.painted);
    foreach (site; sites[5 .. $]) {
        assert(builder.paint(site, pillar, EVERY_HEIGHT, Material.granite, Cover.over) == PaintResult.painted);
    }
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.anchorSlot), Motion!float.identity()), RADIUS);
    uint touchedChunks = 0;
    foreach (node; nearby) {
        graph.ensureStructureAt(node.slot);
        foreach (line, spec; graph.structures.blueprint.lines.slice()) {
            Motion!float lineFromNode = graph.view.lineToNode(cast(uint) line, node.slot).inverse();
            Point!float center = lineFromNode * Point!float.origin();
            foreach (index; 0 .. CORNER_COUNT) {
                Corner corner = cast(Corner) index;
                Point!float cornerInLine = lineFromNode * corner.cornerToNode * Point!float.origin();
                assert(isOnLineInFrame(spec, cornerInLine, center, graph.layout) == graph.hasTouchAt(node.slot, cast(uint) line, corner));
                if (isOnLineInFrame(spec, cornerInLine, center, graph.layout)) {
                    touchedChunks += 1;
                    LineTouch touch = graph.touchOf(node.slot, cast(uint) line);
                    ColumnChunk chunk = ColumnChunk.fromTouch(touch, spec, corner, DIMENSION);
                    foreach (cell; CELLS) {
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
    foreach (cell; CELLS) {
        int[3] local = [cell[0] - 6, cell[1] - 6, cell[2] - 20];
        CellBox moved = canonicalBox(CellBox(local, local), canonical.transform, DIMENSION);
        ColumnSpot fromSite = ColumnSpot(local[0] + 0.5f, local[1] + 0.5f, local[2] + 0.5f);
        ColumnSpot fromLine = ColumnSpot(moved.low[0] + 0.5f, moved.low[1] + 0.5f, moved.low[2] + 0.5f);
        if (!isSamePoint(graph.view.siteToNode(site, site.node) * columnPoint(graph.layout, fromSite), graph.view.siteToNode(line, site.node) * columnPoint(graph.layout, fromLine))) {
            return false;
        }
    }
    return true;
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
    SiteFrame down = graph.view.turned(graph.view.turned(forwarded(tower, RISE_EDGES), Turn.pitchUp), Turn.pitchUp);
    SiteFrame top = graph.view.atLevel(forwarded(tower, RISE_EDGES), 0);
    SiteFrame ground = groundSite(top.node, top.corner, top.zSide());
    SiteFrame quarter = graph.view.turned(ground, Turn.right);
    SiteFrame[5] sites = [
        down,
        graph.view.turned(down, Turn.rollRight),
        graph.view.turned(graph.view.turned(ground, Turn.pitchUp), Turn.rollRight),
        graph.view.turned(graph.view.turned(quarter, Turn.pitchUp), Turn.rollRight),
        forwarded(graph.view.turned(graph.view.turned(quarter, Turn.pitchUp), Turn.rollRight), RISE_EDGES),
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
    auto block = graph.view.siteFace(start);
    foreach (corner; corners) {
        assert(graph.view.siteFace(corner) == block);
    }
    SiteFrame beyond = graph.view.turned(corners[1], Turn.right);
    assert(graph.view.siteFace(beyond) != block);
    assert(graph.view.siteFace(graph.faceWalk(beyond)[3]) == graph.view.siteFace(beyond));
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
    Point!float apex = columnPoint(graph.layout, ColumnSpot(-0.5f, 0.5f, edgeCells(DIMENSION) + 0.5f));
    Point!float mirroredApex = columnPoint(graph.layout, ColumnSpot(0.5f, 0.5f, edgeCells(DIMENSION) + 0.5f));
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
    foreach (step; 0 .. DEEP_STEPS) {
        uint index = step * SIDE_STRIDE;
        while (graph.isParentFace(deep, cast(Face)(index % FACE_COUNT))) {
            index += 1;
        }
        deep = graph.ensureNeighborSlot(deep, cast(Face)(index % FACE_COUNT));
    }
    assert(graph.depthOf(deep) > DEEP_STEPS);
    foreach (index; 0 .. FACE_COUNT) {
        Face side = cast(Face) index;
        uint beside = graph.ensureNeighborSlot(deep, side);
        assert(isSamePoint(graph.view.nodeToNode(beside, deep) * Point!float.origin(), side.mirror * Point!float.origin()));
        Face turn = cast(Face)((index + SIDE_STRIDE) % FACE_COUNT);
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
    uint far = graph.anchorSlot;
    foreach (side; EDGE_WALK) {
        far = graph.ensureNeighborSlot(far, side);
    }
    uint[2] starts = [graph.anchorSlot, far];
    foreach (start; starts) {
        SiteFrame[NODE_EDGES] sites = graph.view.edgeSitesOf(start);
        foreach (index, site; sites) {
            foreach (other; sites[index + 1 .. $]) {
                assert(other != site);
            }
        }
        foreach (index; 0 .. CORNER_COUNT) {
            Corner corner = cast(Corner) index;
            foreach (axis; 0 .. 3) {
                SiteFrame expected = graph.view.edgeSite(start, corner, axis);
                uint first = graph.ensureNeighborSlot(start, corner.faces[(axis + 1) % 3]);
                uint second = graph.ensureNeighborSlot(start, corner.faces[(axis + 2) % 3]);
                uint both = graph.ensureNeighborSlot(first, corner.faces[(axis + 2) % 3]);
                uint[3] around = [first, second, both];
                foreach (node; around) {
                    assert(graph.view.edgeSite(node, corner, axis) == expected);
                }
                Corner end = corner.across[axis];
                size_t endAxis = 3 - sideAxis(end, corner.faces[(axis + 1) % 3]) - sideAxis(end, corner.faces[(axis + 2) % 3]);
                assert(graph.view.edgeSite(start, end, endAxis) == expected);
            }
        }
    }
    graph.release();
}

unittest {
    Graph graph = testGraph();
    uint[GROUND_RING] ring = graph.view.groundRing(graph.anchorSlot, Face.f0);
    foreach (index, slot; ring) {
        assert(fabsf(altitude(*graph.ensureState(slot)) - FACE_DISTANCE) < TOLERANCE.value);
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
    SiteFrame high = forwarded(tower, BEHIND_EDGES);
    builder.growFrom(graph.view.siteOrigin(high).depth);
    assert(builder.paint(tower, CellBox.make(0, 0, 0, 0, 0, 1), EVERY_HEIGHT, Material.granite, Cover.over) == PaintResult.behind);
    assert(builder.paint(high, CellBox.make(0, 0, 0, 0, int.min, 1), EVERY_HEIGHT, Material.granite, Cover.over) == PaintResult.endless);
    assert(builder.paint(high, CellBox.make(0, 0, 0, 0, 0, 1), EVERY_HEIGHT, Material.granite, Cover.over) == PaintResult.painted);
    builder.release();
    graph.release();
}
