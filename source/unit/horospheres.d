module unit.horospheres;

import core.stdc.math : fabsf, floorf;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : higherOf;
import base.vector3 : Vec3, magnitude, minus, scaled;
import common.graph : Graph;
import common.node : Occupancy;
import common.position : Position;
import common.traversal : NearbyNode, NearbyScratch;
import common.view : GraphView;
import common.worldgen.blueprint : BlueprintBuilder, CellBox, Cover, EVERY_HEIGHT, PaintResult;
import common.worldgen.building : Building;
import common.worldgen.generation : ChunkParams, GeneratedVoxels, StructureWorld, Worldgen;
import common.worldgen.horospheres : CLEARANCE_EDGES, ChunkPoint, EdgeLine, FLAT_EDGE, GROUND_EDGES, Gravity, Grounds, Horosphere, HorosphereId, HorosphereKind, HorosphereRef, Horospheres, LOWEST_RISE_EDGES, MOST_GROUNDS, ROOT, Rise, RiseLine, RiseMeasure, blendedGravity, chunkPointOf, columnDistanceOf, edgeOf, ensureClimate, ensureGravityAt, ensureGroundNode, ensureHorosphereOver, ensureHorospheresAt, ensureMeasure, ensurePlaneIn, ensureRising, ensureSegmentSite, ensureSegmentsNear, groundsOf, isApart, isOnFootLine, isRayApart, loadedClimateAt, openHorosphere, probeBuried, probeClear, probeClearOfAncestors, refIn, riseLineOver, risenPlaneOver;
import common.worldgen.plane : Plane;
import common.worldgen.structure : ColumnSpot, GROUND_RING, SiteFrame, columnPoint, edgeCells, ensureGroundRing, forwarded, moveToLevel, rootSite, sitePlacement, siteToNode, turnSite;
import geometry.honeycomb : CORNER_COUNT, Corner, FACE_DISTANCE, Face, NODE_RADIUS, opposite;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : HorosphereForm, Material, Span, Turn;
import unit.named : blockNamed;
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
enum float EXPOSURE_RADIUS = 4.0f;
immutable Vec3!float[6] PULL_HEADINGS = [Vec3!float(1, 0, 0), Vec3!float(-1, 0, 0), Vec3!float(0, 1, 0), Vec3!float(0, -1, 0), Vec3!float(0, 0, 1), Vec3!float(0, 0, -1)];
immutable float[5] GROUND_HEIGHTS = [-2.5f, 1.0f, -0.5f, 2.0f, 1.5f];
immutable Vec3!int[3] PAINTED_CELLS = [
    Vec3!int(5, 6, 19),
    Vec3!int(8, 5, 3),
    Vec3!int(6, 9, 40),
];

Graph structureGraph() {
    return Graph.make(DIMENSION, Worldgen.fromStructure(StructureWorld.fromName("test")));
}

Rise firstKindRise(ubyte edges) {
    return Rise(MaybeIndex!ubyte.of(0), edges);
}

void openAt(ref Graph graph, SiteFrame site, ubyte edges) {
    bool opened = graph.openHorosphere(site, firstKindRise(edges));
    assert(opened);
}

HorosphereId risenOver(ref Graph graph, uint face, Corner corner, HorosphereId over) {
    Maybe!HorosphereId made = graph.view.ensureHorosphereOver(face, corner, over);
    assert(made.exists);
    return made.value;
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

Vec3!float ensurePullAt(ref Graph graph, Position at) {
    graph.view.ensureClimate(graph.slotOf(at.node).value, at.local * Point!float.origin());
    Gravity gravity = graph.ensureGravityAt(at);
    return gravity.up.scaled(gravity.strength);
}

float largestPullChange(ref Graph graph, Position start, Vec3!float heading, uint steps) {
    Position at = start;
    Vec3!float last = graph.ensurePullAt(at);
    float largest = 0;
    Motion!float step = Motion!float.shift(heading.scaled(PULL_STEP));
    foreach (_; 0 .. steps) {
        at = graph.ensureNormalized(Position(at.node, (at.local * step).orthonormalized()));
        Vec3!float pull = graph.ensurePullAt(at);
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

void checkBuriedBeyond(ref Graph graph, HorosphereId risen) {
    Horosphere made = graph.horospheres.horosphere(risen);
    uint node = graph.ensureNeighborSlot(made.footNode, made.label);
    Face side = made.label.opposite;
    float altitude = graph.view.ensurePlaneIn(risen, node).distanceTo(Point!float.origin());
    foreach (_; 0 .. DEEP_STEPS) {
        node = graph.ensureNeighborSlot(node, side);
        side = side.opposite;
        float deeper = graph.view.ensurePlaneIn(risen, node).distanceTo(Point!float.origin());
        assert(deeper < altitude);
        altitude = deeper;
        size_t air = graph.airIn(node);
        assert(air == 0);
    }
}

unittest {
    Graph graph = structureGraph();
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.bare, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    graph.openAt(root, LOWEST_RISE_EDGES);
    bool beside = graph.openHorosphere(forwarded(root, 1), firstKindRise(LOWEST_RISE_EDGES));
    assert(!beside);
    HorosphereId risen = graph.risenOver(graph.anchorSlot, root.corner, ROOT);
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.horospheres.horosphere(risen).footNode), Motion!float.identity()), RADIUS);
    foreach (node; nearby) {
        const(HorosphereRef)[] found = graph.view.ensureHorospheresAt(node.slot);
        foreach (near; found) {
            Plane carried = graph.view.ensurePlaneIn(near.horosphere, node.slot);
            assert(fabsf(carried.distanceTo(Point!float.origin()) - near.plane.distanceTo(Point!float.origin())) < PLANE_TOLERANCE);
        }
    }
    GraphView view = GraphView.over(graph);
    RiseMeasure viewed = view.ensureMeasure(risen);
    RiseMeasure measured = graph.view.ensureMeasure(risen);
    assert(!view.isBlocked && viewed == measured);
    view.release();
    Horosphere made = graph.horospheres.horosphere(risen);
    float footAltitude = graph.view.ensurePlaneIn(risen, made.footNode).distanceTo(Point!float.origin());
    float anchorAltitude = graph.ensureState(graph.anchorSlot).surface.distanceTo(Point!float.origin());
    assert(fabsf(footAltitude - anchorAltitude) < PLANE_TOLERANCE);
    uint[GROUND_RING] ring = graph.view.ensureGroundRing(graph.anchorSlot, Face.first);
    SiteFrame high = graph.view.moveToLevel(forwarded(graph.view.turnSite(root, Turn.pitchUp), RISE_EDGES), 0);
    uint below = graph.view.ensureGroundNode(high.node, ROOT);
    uint index = 0;
    while (index < GROUND_RING && ring[index] != below) {
        index += 1;
    }
    assert(index < GROUND_RING);
    uint footGround = graph.view.ensureGroundNode(made.footNode, risen);
    assert(footGround == made.footNode);
    foreach (node; nearby) {
        HorosphereId[2] both = [ROOT, risen];
        foreach (over; both) {
            float ground = graph.view.ensurePlaneIn(over, graph.view.ensureGroundNode(node.slot, over)).distanceTo(Point!float.origin());
            assert(fabsf(ground - FACE_DISTANCE) < PLANE_TOLERANCE);
        }
    }
    assert(graph.view.isOnFootLine(made.footNode, risen));
    SiteFrame farAlong = graph.view.moveToLevel(forwarded(made.foot, FAR_EDGES), 0);
    assert(!graph.view.isOnFootLine(farAlong.node, risen));
    SiteFrame quarter = made.foot;
    foreach (_; 0 .. GROUND_EDGES) {
        SiteFrame tower = graph.view.turnSite(graph.view.turnSite(quarter, Turn.pitchUp), Turn.rollRight);
        bool towerMatches = graph.isCanonicalMatch(tower);
        assert(towerMatches);
        SiteFrame across = graph.view.turnSite(graph.view.turnSite(graph.view.turnSite(forwarded(tower, LOWEST_RISE_EDGES), Turn.pitchUp), Turn.pitchUp), Turn.rollRight);
        bool acrossMatches = graph.isCanonicalMatch(across);
        assert(acrossMatches);
        quarter = graph.view.turnSite(quarter, Turn.right);
    }
    SiteFrame risenTower = graph.view.turnSite(graph.view.turnSite(made.foot, Turn.pitchUp), Turn.rollRight);
    SiteFrame rootTower = graph.view.turnSite(graph.view.turnSite(graph.view.turnSite(forwarded(risenTower, LOWEST_RISE_EDGES), Turn.pitchUp), Turn.pitchUp), Turn.rollRight);
    float length = LOWEST_RISE_EDGES * edgeCells(graph.layout.dimension);
    foreach (cell; PAINTED_CELLS) {
        Point!float fromRisen = graph.view.siteToNode(risenTower, risenTower.node) * columnPoint(graph.layout, ColumnSpot(cell.x + 0.5f, cell.y + 0.5f, cell.z + 0.5f));
        Point!float fromRoot = graph.view.siteToNode(rootTower, risenTower.node) * columnPoint(graph.layout, ColumnSpot(cell.y + 0.5f, cell.x + 0.5f, length - cell.z - 0.5f));
        assert(isSamePoint(fromRisen, fromRoot));
    }
    BlueprintBuilder builder = BlueprintBuilder.make(graph);
    foreach (cell; PAINTED_CELLS) {
        PaintResult result = builder.paint(risenTower, CellBox.make(cell.x, cell.x, cell.y, cell.y, cell.z, cell.z), EVERY_HEIGHT, blockNamed("base:granite"), Cover.over);
        assert(result == PaintResult.painted);
    }
    foreach (cell; PAINTED_CELLS) {
        Point!float center = sitePlacement(risenTower, graph.layout) * columnPoint(graph.layout, ColumnSpot(cell.x + 0.5f, cell.y + 0.5f, cell.z + 0.5f));
        Position at = graph.ensureNormalized(Position(graph.idAt(risenTower.node), Motion!float.shiftTo(center)));
        ChunkPoint inChunk = chunkPointOf(at.local * Point!float.origin());
        Vec3!int voxel = void;
        foreach (axis; 0 .. 3) {
            voxel[axis] = cast(int) floorf(graph.layout.cubeToGrid(inChunk.coords[axis]));
        }
        const(Building)* building = graph.ensureBuildingAt(graph.slotOf(at.node).value);
        assert(building.materialAt(inChunk.corner, voxel, Material.none) == blockNamed("base:granite"));
    }
    builder.release();
    Plane over = risenPlaneOver(root.corner, Face.first, LOWEST_RISE_EDGES, graph.view.edgeOf());
    Plane stored = graph.view.ensurePlaneIn(risen, graph.anchorSlot);
    assert(fabsf(over.distanceTo(Point!float.origin()) - stored.distanceTo(Point!float.origin())) < PLANE_TOLERANCE);
    Vec3!float down = Vec3!float(0, -1, 0);
    Vec3!float up = Vec3!float(0, 1, 0);
    float[2] equal = [0.5f, 0.5f];
    float[2] whole = [1, 1];
    Vec3!float[2] opposed = [up, down];
    assert(blendedGravity(equal[], whole[], opposed[]).strength < PLANE_TOLERANCE);
    float[1] alone = [0.5f];
    float[1] all = [1];
    Vec3!float[1] single = [up];
    assert(blendedGravity(alone[], all[], single[]).strength == 1.0f);
    float[2] nearFaded = [-1, 0];
    float[2] faded = [0, 1];
    assert(blendedGravity(nearFaded[], faded[], opposed[]).up.y == down.y);
    scratch.release();
    graph.release();
}

unittest {
    Horospheres horospheres;
    horospheres.kinds.append(HorosphereKind(0, HorosphereForm.bare, 0));
    HorosphereRef[GROUND_HEIGHTS.length] near;
    foreach (index, height; GROUND_HEIGHTS) {
        horospheres.horospheres.append(Horosphere.init);
        near[index] = HorosphereRef(Plane(Vec3!float(0, 1, 0), height), EdgeLine.init, HorosphereId.ofIndex(index));
    }
    Grounds grounds = groundsOf(horospheres, Plane.ofFace(Face.first), near[]);
    assert(grounds.count == MOST_GROUNDS);
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
    graph.openAt(root, LOWEST_RISE_EDGES);
    HorosphereId risen = graph.risenOver(graph.anchorSlot, root.corner, ROOT);
    graph.checkBuriedBeyond(risen);
    graph.release();
}

unittest {
    Graph graph = Graph.make(DIMENSION, Worldgen.makeTerrain());
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.solid, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    graph.openAt(root, LOWEST_RISE_EDGES);
    HorosphereId risen = graph.risenOver(graph.anchorSlot, root.corner, ROOT);
    graph.checkBuriedBeyond(risen);
    graph.release();
}

unittest {
    Graph graph = Graph.make(DIMENSION, Worldgen.makeTerrain());
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.bare, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    graph.openAt(root, LOWEST_RISE_EDGES);
    HorosphereId risen = graph.risenOver(graph.anchorSlot, root.corner, ROOT);
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
    graph.openAt(root, FAR_RISE_EDGES);
    graph.risenOver(graph.anchorSlot, root.corner, ROOT);
    int length = FAR_RISE_EDGES * edgeCells(DIMENSION);
    float largest = graph.largestPullChangeAround(graph.view.turnSite(root, Turn.pitchUp), PULL_CELL_STRIDE, length - PULL_CELL_STRIDE);
    assert(largest <= MOST_PULL_CHANGE);
    graph.release();
}

unittest {
    Graph graph = Graph.make(DIMENSION, Worldgen.makeTerrain());
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.terrain, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    graph.openAt(root, FAR_RISE_EDGES);
    HorosphereId risen = graph.risenOver(graph.anchorSlot, root.corner, ROOT);
    Horosphere made = graph.horospheres.horosphere(risen);
    SiteFrame[2] feet = [graph.view.turnSite(root, Turn.pitchUp), graph.view.turnSite(made.foot, Turn.pitchUp)];
    foreach (foot; feet) {
        foreach (x; -CLEARING_CELLS .. CLEARING_CELLS) {
            foreach (y; -CLEARING_CELLS .. CLEARING_CELLS) {
                Point!float spot = sitePlacement(foot, graph.layout) * columnPoint(graph.layout, ColumnSpot(x + 0.5f, y + 0.5f, 0.5f));
                Position at = graph.ensureNormalized(Position(graph.idAt(foot.node), Motion!float.shiftTo(spot)));
                uint slot = graph.slotOf(at.node).value;
                graph.ensureGravityAt(at);
                float relief = graph.view.ensureClimate(slot, at.local * Point!float.origin()).relief;
                assert(relief == 0);
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
                Plane surface = graph.view.ensureState(node.slot).surface;
                assert(surface.distanceTo(Point!float.origin()) > 0);
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
    float largest = graph.largestPullChangeAround(graph.view.turnSite(rootSite(graph.anchorSlot), Turn.pitchUp), PULL_CELL_STRIDE, length);
    assert(largest <= MOST_PULL_CHANGE);
    graph.release();
}

unittest {
    Graph graph = structureGraph();
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.upright, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    graph.openAt(root, LOWEST_RISE_EDGES);
    graph.risenOver(graph.anchorSlot, root.corner, ROOT);
    int length = FAR_RISE_EDGES * edgeCells(DIMENSION);
    float largest = graph.largestPullChangeAround(graph.view.turnSite(root, Turn.pitchUp), PULL_CELL_STRIDE, length);
    assert(largest <= MOST_PULL_CHANGE);
    graph.release();
}

unittest {
    Graph graph = structureGraph();
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.solid, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    graph.openAt(root, FAR_RISE_EDGES);
    HorosphereId first = graph.risenOver(graph.anchorSlot, root.corner, ROOT);
    Horosphere made = graph.horospheres.horosphere(first);
    bool clear = graph.view.probeClearOfAncestors(made.footNode, made.foot.corner, first, LOWEST_RISE_EDGES);
    assert(!clear);
    graph.release();
}

unittest {
    Graph graph = structureGraph();
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.upright, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    graph.openAt(root, LOWEST_RISE_EDGES);
    HorosphereId upright = graph.risenOver(graph.anchorSlot, root.corner, ROOT);
    assert(graph.horospheres.isUpright(upright));
    SiteFrame high = graph.view.ensureSegmentSite(upright, RISE_EDGES);
    uint found = 0;
    foreach (near; graph.view.ensureHorospheresAt(high.node)) {
        if (near.horosphere == upright) {
            found += 1;
            Span segments = graph.view.ensureSegmentsNear(near);
            assert(segments.low <= RISE_EDGES && segments.high >= RISE_EDGES);
            assert(columnDistanceOf(near, Point!float.origin()) < NODE_RADIUS);
        }
    }
    assert(found > 0);
    float edge = graph.view.edgeOf();
    RiseLine line = riseLineOver(root.corner, Face.first, edge);
    Plane above = risenPlaneOver(root.corner, Face.first, LOWEST_RISE_EDGES, edge);
    assert(!isRayApart(line.base, line.along, above, edge));
    assert(isRayApart(line.base, -line.along, above, edge));
    graph.release();
}

unittest {
    Graph graph = structureGraph();
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.bare, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    graph.openAt(root, LOWEST_RISE_EDGES);
    HorosphereId first = graph.risenOver(graph.anchorSlot, root.corner, ROOT);
    SiteFrame along = graph.view.moveToLevel(forwarded(graph.horospheres.horosphere(first).foot, ALONG_EDGES), 0);
    graph.openAt(along, LOWEST_RISE_EDGES);
    HorosphereId second = graph.risenOver(along.node, along.corner, first);
    assert(graph.horospheres.horosphere(second).parent == first);
    uint foot = graph.horospheres.horosphere(second).footNode;
    float separation = CLEARANCE_EDGES * graph.view.edgeOf();
    Plane secondPlane = graph.view.ensurePlaneIn(second, foot);
    Plane rootPlane = graph.view.ensurePlaneIn(ROOT, foot);
    assert(isApart(secondPlane, rootPlane, separation));
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
    graph.openAt(root, LOWEST_RISE_EDGES);
    HorosphereId first = graph.risenOver(graph.anchorSlot, root.corner, ROOT);
    float separation = CLEARANCE_EDGES * graph.view.edgeOf();
    uint risen = 0;
    foreach (edges; ALONG_EDGES .. FARTHEST_EDGES + 1) {
        SiteFrame along = graph.view.moveToLevel(forwarded(graph.horospheres.horosphere(first).foot, edges), 0);
        foreach (made; graph.view.ensureRising(graph.view.ensureGroundNode(along.node, first), first)) {
            uint foot = graph.horospheres.horosphere(made).footNode;
            assert(graph.horospheres.horosphere(made).parent == first);
            Plane madePlane = graph.view.ensurePlaneIn(made, foot);
            Plane rootPlane = graph.view.ensurePlaneIn(ROOT, foot);
            assert(isApart(madePlane, rootPlane, separation));
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
    graph.openAt(root, LOWEST_RISE_EDGES);
    HorosphereId first = graph.risenOver(graph.anchorSlot, root.corner, ROOT);
    float edge = graph.view.edgeOf();
    uint trees = 0;
    foreach (edges; 0 .. FARTHEST_EDGES + 1) {
        SiteFrame along = graph.view.moveToLevel(forwarded(graph.horospheres.horosphere(first).foot, edges), 0);
        foreach (made; graph.view.ensureRising(graph.view.ensureGroundNode(along.node, first), first)) {
            const(Horosphere)* tree = &graph.horospheres.horosphere(made);
            assert(graph.horospheres.isUpright(made) && tree.parent == first);
            RiseLine line = riseLineOver(tree.foot.corner, tree.label, edge);
            Plane ground = graph.view.ensurePlaneIn(ROOT, tree.footNode);
            assert(isRayApart(line.base, line.along, ground, CLEARANCE_EDGES * edge));
            trees += 1;
        }
    }
    assert(trees > 0);
    graph.release();
}

unittest {
    Graph graph = Graph.make(DIMENSION, Worldgen.makeTerrain());
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(graph, Position.origin(), EXPOSURE_RADIUS);
    uint clear = 0;
    uint buried = 0;
    foreach (node; nearby) {
        bool open = graph.view.probeClear(node.slot);
        bool under = graph.view.probeBuried(node.slot);
        assert(!(open && under));
        if (open) {
            clear += 1;
            foreach (index; 0 .. CORNER_COUNT) {
                assert(ChunkParams.make(graph.view, node.slot, cast(Corner) index).predictOccupancy() == Occupancy.empty);
            }
        } else if (under) {
            buried += 1;
            assert(airIn(graph, node.slot) == 0);
        }
    }
    assert(clear > 0 && buried > 0);
    scratch.release();
    graph.release();
}
