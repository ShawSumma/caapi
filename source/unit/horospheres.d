module unit.horospheres;

import core.stdc.math : fabsf, floorf;
import base.numbers : higherOf;
import base.vector3 : magnitude, minus, scaled;
import common.graph : Graph;
import common.position : Position;
import common.traversal : NearbyNode, NearbyScratch;
import common.view : GraphView;
import common.worldgen.blueprint : BlueprintBuilder, CellBox, Cover, EVERY_HEIGHT, PaintResult;
import common.worldgen.generation : ChunkParams, GeneratedVoxels, StructureWorld, Worldgen;
import common.worldgen.horospheres : ChunkPoint, CLEARANCE_EDGES, FLAT_EDGE, GROUND_EDGES, Gravity, loadedClimateAt, refIn, Grounds, Horosphere, HorosphereKind, HorosphereRef, Horospheres, LOWEST_RISE_EDGES, MAX_GROUNDS, ROOT, Rise, RiseMeasure, blendedGravity, chunkPointOf, climateAt, columnDistanceOf, edgeOf, ensureGravityAt, ensureHorospheresAt, groundNodeOf, groundsOf, horosphereOver, isApart, isClearOfAncestors, isOnFootLine, isRayApart, measureOf, openHorosphere, planeOfHorosphereIn, riseLineOver, risenPlaneOver, risingFrom, segmentSite, segmentsNear;
import common.worldgen.plane : Plane;
import common.worldgen.structure : ColumnSpot, GROUND_RING, SiteFrame, atLevel, columnPoint, edgeCells, forwarded, groundRing, rootSite, sitePlacement, siteToNode, turned;
import geometry.honeycomb : CORNER_COUNT, Corner, FACE_DISTANCE, Face, NODE_RADIUS, opposite;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : HorosphereForm, Material, Turn;
import unit.structure : isCanonicalMatch, isSamePoint;

enum ubyte DIMENSION = 12;
enum float RADIUS = 3.0f;
enum float PLANE_TOLERANCE = 1e-2f;
enum int FAR_EDGES = 3;
enum int RISE_EDGES = 3;
enum int ALONG_EDGES = 4;
enum int FARTHEST_EDGES = 8;
enum float FARTHEST_GROUND = 2.0f;
enum uint DEEP_STEPS = 6;
enum ubyte FAR_RISE_EDGES = 4;
enum float PULL_STEP = 0.02f;
enum uint PULL_STEPS = 150;
enum int PULL_CELL_STRIDE = 12;
enum float MOST_PULL_CHANGE = 0.2f;
enum double RISING_SKY_ODDS = 0.05;
enum int CLEARING_CELLS = 8;
enum float NESTING_RADIUS = 5.0f;
immutable float[3][6] PULL_HEADINGS = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]];
immutable float[5] GROUND_HEIGHTS = [-2.5f, 1.0f, -0.5f, 2.0f, 1.5f];
immutable int[3][3] PAINTED_CELLS = [
    [5, 6, 19],
    [8, 5, 3],
    [6, 9, 40],
];

Graph structureGraph() {
    return Graph.make(DIMENSION, Worldgen.fromStructure(StructureWorld.fromName("test")));
}

size_t airIn(ref Graph graph, uint slot) {
    size_t air = 0;
    foreach (index; 0 .. CORNER_COUNT) {
        GeneratedVoxels generated = ChunkParams.make(graph.view, slot, cast(Corner) index).generateVoxels();
        foreach (cell; 0 .. cast(size_t) DIMENSION * DIMENSION * DIMENSION) {
            if (generated.voxels.at(cell) == Material.none) {
                air += 1;
            }
        }
        generated.voxels.release();
    }
    return air;
}

float[3] pullAt(ref Graph graph, Position at) {
    graph.view.climateAt(graph.slotOf(at.node), at.local * Point!float.origin());
    Gravity gravity = graph.ensureGravityAt(at);
    return gravity.up.scaled(gravity.strength);
}

float largestPullChange(ref Graph graph, Position start, float[3] heading, uint steps) {
    Position at = start;
    float[3] last = graph.pullAt(at);
    float largest = 0;
    Motion!float step = Motion!float.shift(heading.scaled(PULL_STEP));
    foreach (_; 0 .. steps) {
        at = graph.ensureNormalized(Position(at.node, (at.local * step).orthonormalized()));
        float[3] pull = graph.pullAt(at);
        largest = higherOf(largest, pull.minus(last).magnitude);
        last = pull;
    }
    return largest;
}

float largestPullChangeAround(ref Graph graph, SiteFrame tower, int bottom, int top) {
    float largest = 0;
    int cell = bottom;
    while (cell <= top) {
        Point!float center = sitePlacement(tower, graph.layout) * columnPoint(graph.layout, ColumnSpot(0.5f, 0.5f, cell + 0.5f));
        Position start = graph.ensureNormalized(Position(graph.idAt(tower.node), Motion!float.shiftTo(center)));
        foreach (heading; PULL_HEADINGS) {
            largest = higherOf(largest, graph.largestPullChange(start, heading, PULL_STEPS));
        }
        cell += PULL_CELL_STRIDE;
    }
    return largest;
}

void checkBuriedBeyond(ref Graph graph, uint risen) {
    Horosphere made = graph.horospheres.horosphere(risen);
    uint node = graph.ensureNeighborSlot(made.footNode, made.label);
    Face side = made.label.opposite;
    float altitude = graph.view.planeOfHorosphereIn(risen, node).distanceTo(Point!float.origin());
    foreach (_; 0 .. DEEP_STEPS) {
        node = graph.ensureNeighborSlot(node, side);
        side = side.opposite;
        float deeper = graph.view.planeOfHorosphereIn(risen, node).distanceTo(Point!float.origin());
        assert(deeper < altitude);
        altitude = deeper;
        assert(graph.airIn(node) == 0);
    }
}

unittest {
    Graph graph = structureGraph();
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.bare, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openHorosphere(root, Rise(1, LOWEST_RISE_EDGES)));
    assert(!graph.openHorosphere(forwarded(root, 1), Rise(1, LOWEST_RISE_EDGES)));
    uint risen = graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT);
    assert(risen != ROOT);
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.horospheres.horosphere(risen).footNode), Motion!float.identity()), RADIUS);
    foreach (node; nearby) {
        const(HorosphereRef)[] found = graph.view.ensureHorospheresAt(node.slot);
        foreach (near; found) {
            assert(fabsf(graph.view.planeOfHorosphereIn(near.horosphere, node.slot).distanceTo(Point!float.origin()) - near.plane.distanceTo(Point!float.origin())) < PLANE_TOLERANCE);
        }
    }
    GraphView view = GraphView.over(graph);
    RiseMeasure viewed = view.measureOf(risen);
    RiseMeasure measured = graph.view.measureOf(risen);
    assert(!view.isBlocked && viewed == measured);
    view.release();
    Horosphere made = graph.horospheres.horosphere(risen);
    float footAltitude = graph.view.planeOfHorosphereIn(risen, made.footNode).distanceTo(Point!float.origin());
    float anchorAltitude = graph.ensureState(graph.anchorSlot).surface.distanceTo(Point!float.origin());
    assert(fabsf(footAltitude - anchorAltitude) < PLANE_TOLERANCE);
    uint[GROUND_RING] ring = graph.view.groundRing(graph.anchorSlot, Face.first);
    SiteFrame high = graph.view.atLevel(forwarded(graph.view.turned(root, Turn.pitchUp), RISE_EDGES), 0);
    uint below = graph.view.groundNodeOf(high.node, ROOT);
    uint index = 0;
    while (index < GROUND_RING && ring[index] != below) {
        index += 1;
    }
    assert(index < GROUND_RING);
    assert(graph.view.groundNodeOf(made.footNode, risen) == made.footNode);
    foreach (node; nearby) {
        uint[2] both = [ROOT, risen];
        foreach (over; both) {
            float ground = graph.view.planeOfHorosphereIn(over, graph.view.groundNodeOf(node.slot, over)).distanceTo(Point!float.origin());
            assert(fabsf(ground - FACE_DISTANCE) < PLANE_TOLERANCE);
        }
    }
    assert(graph.view.isOnFootLine(made.footNode, risen));
    assert(!graph.view.isOnFootLine(graph.view.atLevel(forwarded(made.foot, FAR_EDGES), 0).node, risen));
    SiteFrame quarter = made.foot;
    foreach (_; 0 .. GROUND_EDGES) {
        SiteFrame tower = graph.view.turned(graph.view.turned(quarter, Turn.pitchUp), Turn.rollRight);
        assert(graph.isCanonicalMatch(tower));
        assert(graph.isCanonicalMatch(graph.view.turned(graph.view.turned(graph.view.turned(forwarded(tower, LOWEST_RISE_EDGES), Turn.pitchUp), Turn.pitchUp), Turn.rollRight)));
        quarter = graph.view.turned(quarter, Turn.right);
    }
    SiteFrame risenTower = graph.view.turned(graph.view.turned(made.foot, Turn.pitchUp), Turn.rollRight);
    SiteFrame rootTower = graph.view.turned(graph.view.turned(graph.view.turned(forwarded(risenTower, LOWEST_RISE_EDGES), Turn.pitchUp), Turn.pitchUp), Turn.rollRight);
    float length = LOWEST_RISE_EDGES * edgeCells(graph.layout.dimension);
    foreach (cell; PAINTED_CELLS) {
        Point!float fromRisen = graph.view.siteToNode(risenTower, risenTower.node) * columnPoint(graph.layout, ColumnSpot(cell[0] + 0.5f, cell[1] + 0.5f, cell[2] + 0.5f));
        Point!float fromRoot = graph.view.siteToNode(rootTower, risenTower.node) * columnPoint(graph.layout, ColumnSpot(cell[1] + 0.5f, cell[0] + 0.5f, length - cell[2] - 0.5f));
        assert(isSamePoint(fromRisen, fromRoot));
    }
    BlueprintBuilder builder = BlueprintBuilder.make(graph);
    foreach (cell; PAINTED_CELLS) {
        assert(builder.paint(risenTower, CellBox.make(cell[0], cell[0], cell[1], cell[1], cell[2], cell[2]), EVERY_HEIGHT, Material.granite, Cover.over) == PaintResult.painted);
    }
    foreach (cell; PAINTED_CELLS) {
        Point!float center = sitePlacement(risenTower, graph.layout) * columnPoint(graph.layout, ColumnSpot(cell[0] + 0.5f, cell[1] + 0.5f, cell[2] + 0.5f));
        Position at = graph.ensureNormalized(Position(graph.idAt(risenTower.node), Motion!float.shiftTo(center)));
        ChunkPoint inChunk = chunkPointOf(at.local * Point!float.origin());
        int[3] voxel = void;
        foreach (axis; 0 .. 3) {
            voxel[axis] = cast(int) floorf(graph.layout.cubeToGrid(inChunk.coords[axis]));
        }
        assert(graph.ensureBuildingAt(graph.slotOf(at.node)).materialAt(inChunk.corner, voxel, Material.none) == Material.granite);
    }
    builder.release();
    Plane over = risenPlaneOver(root.corner, Face.first, LOWEST_RISE_EDGES, graph.view.edgeOf());
    Plane stored = graph.view.planeOfHorosphereIn(risen, graph.anchorSlot);
    assert(fabsf(over.distanceTo(Point!float.origin()) - stored.distanceTo(Point!float.origin())) < PLANE_TOLERANCE);
    float[3] down = [0, -1, 0];
    float[3] up = [0, 1, 0];
    float[2] equal = [0.5f, 0.5f];
    float[2] whole = [1, 1];
    float[3][2] opposed = [up, down];
    assert(blendedGravity(equal[], whole[], opposed[]).strength < PLANE_TOLERANCE);
    float[1] alone = [0.5f];
    float[1] all = [1];
    float[3][1] single = [up];
    assert(blendedGravity(alone[], all[], single[]).strength == 1.0f);
    float[2] nearFaded = [-1, 0];
    float[2] faded = [0, 1];
    assert(blendedGravity(nearFaded[], faded[], opposed[]).up[1] == down[1]);
    scratch.release();
    graph.release();
}

unittest {
    Horospheres horospheres;
    horospheres.kinds.append(HorosphereKind(0, HorosphereForm.bare, 0));
    HorosphereRef[GROUND_HEIGHTS.length] near;
    foreach (index, height; GROUND_HEIGHTS) {
        horospheres.horospheres.append(Horosphere.init);
        near[index] = HorosphereRef(Plane([0, 1, 0], height), [Plane.init, Plane.init], cast(uint) index + 1);
    }
    Grounds grounds = groundsOf(horospheres, Plane.ofFace(Face.first), near[]);
    assert(grounds.count == MAX_GROUNDS);
    assert(grounds.items[1].surface.height == GROUND_HEIGHTS[0]);
    foreach (ground; grounds.items[1 .. grounds.count]) {
        assert(ground.surface.height < FARTHEST_GROUND);
    }
    horospheres.release();
}

unittest {
    Graph graph = Graph.make(DIMENSION, Worldgen.makeTerrain());
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.terrain, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openHorosphere(root, Rise(1, LOWEST_RISE_EDGES)));
    uint risen = graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT);
    assert(risen != ROOT);
    graph.checkBuriedBeyond(risen);
    graph.release();
}

unittest {
    Graph graph = Graph.make(DIMENSION, Worldgen.makeTerrain());
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.solid, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openHorosphere(root, Rise(1, LOWEST_RISE_EDGES)));
    uint risen = graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT);
    assert(risen != ROOT);
    graph.checkBuriedBeyond(risen);
    graph.release();
}

unittest {
    Graph graph = Graph.make(DIMENSION, Worldgen.makeTerrain());
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.bare, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openHorosphere(root, Rise(1, LOWEST_RISE_EDGES)));
    uint risen = graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT);
    assert(risen != ROOT);
    Horosphere made = graph.horospheres.horosphere(risen);
    GeneratedVoxels generated = ChunkParams.make(graph.view, graph.ensureNeighborSlot(made.footNode, made.label), made.foot.corner).generateVoxels();
    assert(generated.voxels.isFilledWith(Material.none));
    generated.voxels.release();
    graph.release();
}

unittest {
    Graph graph = Graph.make(DIMENSION, Worldgen.makeTerrain());
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.terrain, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openHorosphere(root, Rise(1, FAR_RISE_EDGES)));
    assert(graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT) != ROOT);
    int length = FAR_RISE_EDGES * edgeCells(DIMENSION);
    assert(graph.largestPullChangeAround(graph.view.turned(root, Turn.pitchUp), PULL_CELL_STRIDE, length - PULL_CELL_STRIDE) <= MOST_PULL_CHANGE);
    graph.release();
}

unittest {
    Graph graph = Graph.make(DIMENSION, Worldgen.makeTerrain());
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.terrain, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openHorosphere(root, Rise(1, FAR_RISE_EDGES)));
    uint risen = graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT);
    assert(risen != ROOT);
    Horosphere made = graph.horospheres.horosphere(risen);
    SiteFrame[2] feet = [graph.view.turned(root, Turn.pitchUp), graph.view.turned(made.foot, Turn.pitchUp)];
    foreach (foot; feet) {
        foreach (x; -CLEARING_CELLS .. CLEARING_CELLS) {
            foreach (y; -CLEARING_CELLS .. CLEARING_CELLS) {
                Point!float spot = sitePlacement(foot, graph.layout) * columnPoint(graph.layout, ColumnSpot(x + 0.5f, y + 0.5f, 0.5f));
                Position at = graph.ensureNormalized(Position(graph.idAt(foot.node), Motion!float.shiftTo(spot)));
                uint slot = graph.slotOf(at.node);
                graph.ensureGravityAt(at);
                assert(graph.view.climateAt(slot, at.local * Point!float.origin()).relief == 0);
                assert(graph.loadedClimateAt(slot, at.local * Point!float.origin()).relief == 0);
            }
        }
    }
    NearbyScratch scratch;
    foreach (foot; feet) {
        Position center = Position(graph.idAt(foot.node), Motion!float.identity());
        foreach (node; scratch.collectAll(graph, center, RADIUS)) {
            HorosphereRef expected = graph.view.refIn(risen, node.slot);
            if (columnDistanceOf(expected, Point!float.origin()) <= FLAT_EDGE + NODE_RADIUS) {
                uint found = 0;
                foreach (near; graph.view.ensureHorospheresAt(node.slot)) {
                    if (near.horosphere == risen) {
                        found += 1;
                    }
                }
                assert(found > 0);
            }
        }
    }
    scratch.release();
    graph.release();
}

unittest {
    Graph graph = structureGraph();
    graph.horospheres.kinds.append(HorosphereKind(RISING_SKY_ODDS, HorosphereForm.solid, 0));
    NearbyScratch scratch;
    uint planes = 0;
    foreach (node; scratch.collectAll(graph, Position(graph.idAt(graph.anchorSlot), Motion!float.identity()), NESTING_RADIUS)) {
        const(HorosphereRef)[] near = graph.view.ensureHorospheresAt(node.slot);
        foreach (index; 0 .. near.length) {
            HorosphereRef first = graph.view.horospheresAt(node.slot)[index];
            float altitude = first.plane.distanceTo(Point!float.origin());
            if (altitude > 0 && altitude < FACE_DISTANCE + PLANE_TOLERANCE) {
                planes += 1;
                foreach (other; graph.view.horospheresAt(node.slot)) {
                    assert(other.plane.distanceTo(Point!float.origin()) > 0);
                }
                assert(graph.view.stateAt(node.slot).surface.distanceTo(Point!float.origin()) > 0);
            }
        }
    }
    assert(planes > 0);
    scratch.release();
    graph.release();
}

unittest {
    Graph graph = structureGraph();
    graph.horospheres.kinds.append(HorosphereKind(RISING_SKY_ODDS, HorosphereForm.solid, 0));
    int length = FAR_RISE_EDGES * edgeCells(DIMENSION);
    assert(graph.largestPullChangeAround(graph.view.turned(rootSite(graph.anchorSlot), Turn.pitchUp), PULL_CELL_STRIDE, length) <= MOST_PULL_CHANGE);
    graph.release();
}

unittest {
    Graph graph = structureGraph();
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.upright, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openHorosphere(root, Rise(1, LOWEST_RISE_EDGES)));
    assert(graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT) != ROOT);
    int length = FAR_RISE_EDGES * edgeCells(DIMENSION);
    assert(graph.largestPullChangeAround(graph.view.turned(root, Turn.pitchUp), PULL_CELL_STRIDE, length) <= MOST_PULL_CHANGE);
    graph.release();
}

unittest {
    Graph graph = structureGraph();
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.solid, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openHorosphere(root, Rise(1, FAR_RISE_EDGES)));
    uint first = graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT);
    Horosphere made = graph.horospheres.horosphere(first);
    assert(!graph.view.isClearOfAncestors(made.footNode, made.foot.corner, first, LOWEST_RISE_EDGES));
    graph.release();
}

unittest {
    Graph graph = structureGraph();
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.upright, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openHorosphere(root, Rise(1, LOWEST_RISE_EDGES)));
    uint upright = graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT);
    assert(graph.horospheres.isUpright(upright));
    SiteFrame high = graph.view.segmentSite(upright, RISE_EDGES);
    uint found = 0;
    foreach (near; graph.view.ensureHorospheresAt(high.node)) {
        if (near.horosphere == upright) {
            found += 1;
            int[2] segments = graph.view.segmentsNear(near);
            assert(segments[0] <= RISE_EDGES && segments[1] >= RISE_EDGES);
            assert(columnDistanceOf(near, Point!float.origin()) < NODE_RADIUS);
        }
    }
    assert(found > 0);
    float edge = graph.view.edgeOf();
    Vec4!float[2] line = riseLineOver(root.corner, Face.first, edge);
    Plane above = risenPlaneOver(root.corner, Face.first, LOWEST_RISE_EDGES, edge);
    assert(!isRayApart(line[0], line[1], above, edge));
    assert(isRayApart(line[0], -line[1], above, edge));
    graph.release();
}

unittest {
    Graph graph = structureGraph();
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.bare, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openHorosphere(root, Rise(1, LOWEST_RISE_EDGES)));
    uint first = graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT);
    SiteFrame along = graph.view.atLevel(forwarded(graph.horospheres.horosphere(first).foot, ALONG_EDGES), 0);
    assert(graph.openHorosphere(along, Rise(1, LOWEST_RISE_EDGES)));
    uint second = graph.view.horosphereOver(along.node, along.corner, first);
    assert(second != ROOT && graph.horospheres.horosphere(second).parent == first);
    uint foot = graph.horospheres.horosphere(second).footNode;
    float separation = CLEARANCE_EDGES * graph.view.edgeOf();
    assert(isApart(graph.view.planeOfHorosphereIn(second, foot), graph.view.planeOfHorosphereIn(ROOT, foot), separation));
    uint found = 0;
    foreach (near; graph.view.ensureHorospheresAt(foot)) {
        if (near.horosphere == second) {
            found += 1;
        }
    }
    assert(found > 0);
    graph.release();
}

unittest {
    Graph graph = structureGraph();
    graph.horospheres.kinds.append(HorosphereKind(1, HorosphereForm.bare, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openHorosphere(root, Rise(1, LOWEST_RISE_EDGES)));
    uint first = graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT);
    float separation = CLEARANCE_EDGES * graph.view.edgeOf();
    uint risen = 0;
    foreach (edges; ALONG_EDGES .. FARTHEST_EDGES + 1) {
        SiteFrame along = graph.view.atLevel(forwarded(graph.horospheres.horosphere(first).foot, edges), 0);
        foreach (made; graph.view.risingFrom(graph.view.groundNodeOf(along.node, first), first)) {
            uint foot = graph.horospheres.horosphere(made).footNode;
            assert(graph.horospheres.horosphere(made).parent == first);
            assert(isApart(graph.view.planeOfHorosphereIn(made, foot), graph.view.planeOfHorosphereIn(ROOT, foot), separation));
            risen += 1;
        }
    }
    assert(risen > 0);
    graph.release();
}

unittest {
    Graph graph = structureGraph();
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.bare, 0));
    graph.horospheres.kinds.append(HorosphereKind(1, HorosphereForm.upright, 1));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openHorosphere(root, Rise(1, LOWEST_RISE_EDGES)));
    uint first = graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT);
    float edge = graph.view.edgeOf();
    uint trees = 0;
    foreach (edges; 0 .. FARTHEST_EDGES + 1) {
        SiteFrame along = graph.view.atLevel(forwarded(graph.horospheres.horosphere(first).foot, edges), 0);
        foreach (made; graph.view.risingFrom(graph.view.groundNodeOf(along.node, first), first)) {
            const(Horosphere)* tree = &graph.horospheres.horosphere(made);
            assert(graph.horospheres.isUpright(made) && tree.parent == first);
            Vec4!float[2] line = riseLineOver(tree.foot.corner, tree.label, edge);
            assert(isRayApart(line[0], line[1], graph.view.planeOfHorosphereIn(ROOT, tree.footNode), CLEARANCE_EDGES * edge));
            trees += 1;
        }
    }
    assert(trees > 0);
    graph.release();
}
