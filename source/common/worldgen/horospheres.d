module common.worldgen.horospheres;

import core.math : sqrt;
import core.stdc.math : acoshf, cosh, coshf, expf, fabs, fabsf, floorf, log, sinh, sinhf, sqrtf;
import core.stdc.string : memcpy;
import base.array : Array;
import base.hashmap : FIBONACCI_MULTIPLIER, HashMap;
import base.numbers : higherOf, lowerOf;
import base.slab : Run, RunPool, Slab;
import base.splitmix : unitOf;
import base.vector3 : scaled;
import common.graph : Graph, NO_SLOT, NodeId, ParentList;
import common.position : Position;
import common.traversal : MIRRORED_ORIGINS, NearbyNode, NearbyScratch;
import common.view : GraphView, SlotCorner;
import common.worldgen.blueprint : BlueprintBuilder, CellBox, EVERY_HEIGHT, PaintResult;
import common.worldgen.climate : Climate, CubeClimate, NodeClimate, RELIEF_BOUND, RELIEF_SLACK;
import common.worldgen.generation : ChunkParams, GeneratedVoxels, NodeState, StructureWorld, Worldgen;
import common.worldgen.plane : Plane, PlaneMeasure, logCosh;
import common.worldgen.structure : ClaimKey, ColumnSpot, GROUND_RING, SiteFrame, atLevel, columnPoint, edgeCells, edgeLength, forwarded, groundRing, groundSite, isCanonicalMatch, isSamePoint, pathBetween, rootSite, rootedCorner, sideAxis, siteHash, siteOrigin, sitePlacement, siteToNode, turned;
import geometry.honeycomb : CORNER_COUNT, Corner, FACE_COUNT, FACE_DISTANCE, Face, NODE_RADIUS, across, cornerToNode, cubeScale, faces, mirror, nodeToCorner;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : HorosphereForm, Look, Material, NO_KIND, SitePart, Turn;

enum uint ROOT = 0;
enum ubyte NO_RISE = 0;
enum uint MAX_GROUNDS = 4;
enum uint MOST_NEAR_RINGS = GROUND_RING * GROUND_RING;
enum float RISE_REACH = 7.0f;
enum float GROUND_REACH = 3.0f;
enum uint GROUND_EDGES = 4;
enum ubyte LOWEST_RISE_EDGES = 2;
enum ubyte RISE_EDGE_CHOICES = 3;
enum float CLEARANCE_EDGES = 2.0f;
enum float GRAVITY_FALLOFF = 0.15f;
enum float CHUNK_COORD_SLACK = 1e-3f;
enum float RELIEF_SPREAD = 0.8f;
enum float RISEN_SIDE_MARGIN = 2.0f * NODE_RADIUS + RELIEF_SPREAD;
enum float LINE_TOLERANCE = 0.05f;
enum double APART_TOLERANCE = 1e-3;
enum float GROUND_LIFT_FACTOR = 0.1f;
enum float DESCENT_ALTITUDE = 2.0f;
enum float DESCENT_TOLERANCE = 1e-3f;
enum double DESCENT_TIE_SLACK = 1 + 1e-3;
enum double DESCENT_TIE_FLOOR = 1e-3;
enum float COLUMN_REACH_EDGES = 1.5f;
enum ubyte TEST_DIMENSION = 12;
enum float TEST_RADIUS = 3.0f;
enum float TEST_PLANE_TOLERANCE = 1e-2f;
enum int TEST_FAR_EDGES = 3;
enum int TEST_RISE_EDGES = 3;
enum int TEST_ALONG_EDGES = 4;
enum int TEST_FARTHEST_EDGES = 8;
enum float TEST_FARTHEST_GROUND = 2.0f;
immutable float[5] TEST_GROUND_HEIGHTS = [-2.5f, 1.0f, -0.5f, 2.0f, 1.5f];
immutable int[3][3] TEST_PAINTED_CELLS = [
    [5, 6, 19],
    [8, 5, 3],
    [6, 9, 40],
];

enum Fill : ubyte {
    none,
    flat,
    terrain,
}

struct HorosphereKind {
    double odds;
    HorosphereForm form;
    uint tag;
    Look look;
}

struct Rise {
    ubyte kind;
    ubyte edges;
}

struct Horosphere {
    Plane plane;
    Plane[2] column;
    SiteFrame foot;
    CornerKey key;
    uint keySlot;
    uint parent;
    uint footNode;
    uint users;
    uint tiles;
    int ground;
    int below;
    int balance;
    Face label;
    ubyte kind;
    ubyte edges;
    bool isMeasured;
    bool isKnown;
}

struct HorosphereRef {
    Plane plane;
    Plane[2] column;
    uint horosphere;

    HorosphereRef across(Face side, bool isUpright) const {
        Face[1] path = [side];
        Plane[2] carried = column;
        if (isUpright) {
            carried = [column[0].carriedAlong(path[]), column[1].carriedAlong(path[])];
        }
        return HorosphereRef(plane.carriedAlong(path[]), carried, horosphere);
    }
}

bool contains(ref const Array!HorosphereRef found, uint horosphere) {
    uint index = 0;
    while (index < found.length && found.ptr[index].horosphere != horosphere) {
        index += 1;
    }
    return index < found.length;
}

float columnDistanceOf(ref const HorosphereRef near) {
    float first = sinhf(near.column[0].distanceTo(Point!float.origin()));
    float second = sinhf(near.column[1].distanceTo(Point!float.origin()));
    return acoshf(sqrtf(1 + first * first + second * second));
}

struct Ground {
    Plane surface;
    Fill fill;
}

struct Grounds {
    Ground[MAX_GROUNDS] items;
    uint count;

    uint farthestRisen() const {
        uint farthest = 1;
        foreach (index; 2 .. count) {
            if (fabsf(items[index].surface.distanceTo(Point!float.origin())) > fabsf(items[farthest].surface.distanceTo(Point!float.origin()))) {
                farthest = index;
            }
        }
        return farthest;
    }
}

struct Gravity {
    float[3] up;
    float strength;
}

struct ChunkPoint {
    float[3] coords;
    Corner corner;
}

struct GroundKey {
    NodeId ground;
    uint horosphere;

    size_t toHash() const {
        return ground.toHash() ^ horosphere;
    }
}

struct RisingList {
    uint start;
    uint count;
}

struct CornerKey {
    NodeId node;
    Corner corner;

    size_t toHash() const {
        return node.toHash() ^ (cast(size_t) corner * FIBONACCI_MULTIPLIER);
    }
}

struct NodeHorospheres {
    Run run;
    bool isKnown;
}

struct NodeRises {
    Rise[CORNER_COUNT] rises;
    uint known;
}

struct Horospheres {
    Array!HorosphereKind kinds;
    Array!Horosphere horospheres;
    Array!uint freeHorospheres;
    Slab!NodeHorospheres nodes;
    Slab!NodeRises rises;
    RunPool!HorosphereRef refs;
    HashMap!(CornerKey, Rise) forced;
    HashMap!(CornerKey, uint) horosphereOf;
    HashMap!(GroundKey, RisingList) risingFrom;
    Array!uint rising;
    Fill rootFill;
    ubyte rootKind;
    bool isGravityInverted;

    float gravitySign() const {
        if (isGravityInverted) {
            return -1;
        } else {
            return 1;
        }
    }

    void ensureSlots(uint count) {
        nodes.ensure(count);
        rises.ensure(count);
    }

    bool hasRise(uint slot, Corner corner) const {
        return (rises.at(slot).known & (1u << corner)) != 0;
    }

    Rise riseAt(uint slot, Corner corner) const {
        return rises.at(slot).rises[corner];
    }

    void storeRise(uint slot, Corner corner, Rise rise) {
        NodeRises* node = rises.at(slot);
        node.rises[corner] = rise;
        node.known |= 1u << corner;
    }

    ref const(Horosphere) horosphere(uint index) const {
        return horospheres.ptr[index - 1];
    }

    Face labelOf(uint index) const {
        if (index == ROOT) {
            return Face.f0;
        } else {
            return horosphere(index).label;
        }
    }

    ubyte kindOf(uint index) const {
        if (index == ROOT) {
            return rootKind;
        } else {
            return cast(ubyte)(horosphere(index).kind + 1);
        }
    }

    uint tagOf(uint index) const {
        ubyte kind = kindOf(index);
        if (kind == NO_RISE) {
            return NO_KIND;
        } else {
            return kinds.ptr[kind - 1].tag;
        }
    }

    bool isUpright(uint index) const {
        return index != ROOT && kinds.ptr[horosphere(index).kind].form == HorosphereForm.upright;
    }

    bool isUprightKind(ubyte kind) const {
        return kinds.ptr[kind - 1].form == HorosphereForm.upright;
    }

    Fill fillOf(uint index) const {
        ubyte kind = kindOf(index);
        if (index == ROOT && kind == NO_RISE) {
            return rootFill;
        } else if (kinds.ptr[kind - 1].form == HorosphereForm.terrain) {
            return Fill.terrain;
        } else {
            return Fill.none;
        }
    }

    bool isFlat(uint index) const {
        return fillOf(index) != Fill.terrain;
    }

    bool hasHorospheresAt(uint slot) const {
        return nodes.at(slot).isKnown;
    }

    const(HorosphereRef)[] horospheresAt(uint slot) const {
        return refs.slice(nodes.at(slot).run);
    }

    void storeHorospheres(uint slot, const(HorosphereRef)[] found) {
        Run run = refs.reserve(cast(uint) found.length);
        memcpy(refs.slice(run).ptr, found.ptr, found.length * HorosphereRef.sizeof);
        foreach (near; found) {
            horospheres.ptr[near.horosphere - 1].users += 1;
        }
        *nodes.at(slot) = NodeHorospheres(run, true);
    }

    void forget(uint slot) {
        foreach (near; horospheresAt(slot)) {
            horospheres.ptr[near.horosphere - 1].users -= 1;
        }
        refs.release(nodes.at(slot).run);
        *nodes.at(slot) = NodeHorospheres.init;
        *rises.at(slot) = NodeRises.init;
    }

    const(uint)[] knownRising(GroundKey key) const {
        const(RisingList)* known = risingFrom.find(key);
        if (known is null) {
            return null;
        } else {
            return rising.ptr[known.start .. known.start + known.count];
        }
    }

    const(uint)[] storeRising(GroundKey key, const(uint)[] found) {
        RisingList list = RisingList(cast(uint) rising.length, cast(uint) found.length);
        rising.appendAll(found);
        risingFrom.insert(key, list);
        return rising.ptr[list.start .. list.start + list.count];
    }

    void forgetRising() {
        risingFrom.clear();
        rising.clear();
    }

    bool isOpen() const {
        return kinds.length > 0;
    }

    double totalOdds() const {
        double total = 0;
        foreach (kind; kinds.slice()) {
            total += kind.odds;
        }
        return total;
    }

    Rise rolled(ulong hash) const {
        double roll = unitOf(hash);
        double below = 0;
        uint index = 0;
        while (index < kinds.length && roll >= below + kinds.ptr[index].odds) {
            below += kinds.ptr[index].odds;
            index += 1;
        }
        if (index < kinds.length) {
            return Rise(cast(ubyte)(index + 1), cast(ubyte)(LOWEST_RISE_EDGES + hash % RISE_EDGE_CHOICES));
        } else {
            return Rise(NO_RISE, 0);
        }
    }

    void release() {
        kinds.release();
        horospheres.release();
        freeHorospheres.release();
        nodes.release();
        rises.release();
        refs.release();
        forced.release();
        horosphereOf.release();
        risingFrom.release();
        rising.release();
    }
}

float edgeOf(ref const GraphView view) {
    return edgeLength(view.layout).value;
}

float columnReach(ref const GraphView view) {
    return COLUMN_REACH_EDGES * view.edgeOf();
}

void applyDiscoveries(ref Graph target, ref const GraphView view) {
    foreach (slot; view.storedSlots.slice()) {
        if (!target.horospheres.hasHorospheresAt(slot)) {
            target.horospheres.storeHorospheres(slot, view.horospheresAt(slot));
        }
    }
    foreach (key; view.risingKeys.slice()) {
        if (target.horospheres.knownRising(key) is null) {
            target.horospheres.storeRising(key, view.knownRising(key));
        }
    }
    foreach (at; view.choiceKeys.slice()) {
        if (!target.horospheres.hasRise(at.slot, at.corner)) {
            target.horospheres.storeRise(at.slot, at.corner, view.choiceAt(at));
        }
    }
}

bool makeWantedHorospheres(ref Graph target, ref GraphView view) {
    foreach (want; view.wanted.slice()) {
        uint face = want.start;
        foreach (side; view.wantedPaths.ptr[want.pathStart .. want.pathStart + want.pathLength]) {
            face = target.ensureNeighborSlot(face, side);
        }
        target.view.horosphereOver(face, want.corner, want.parent);
    }
    bool isMade = view.wanted.length > 0;
    view.clearWanted();
    return isMade;
}

const(HorosphereRef)[] ensureHorospheresAt(ref GraphView view, uint slot) {
    if (!view.hasHorospheresAt(slot)) {
        Array!HorosphereRef found;
        if (view.horospheres.isOpen()) {
            view.discoverHorospheres(slot, found);
        }
        view.storeHorospheres(slot, found.slice());
        found.release();
    }
    return view.horospheresAt(slot);
}

bool isNear(ref const GraphView view, ref const HorosphereRef near) {
    if (view.horospheres.isUpright(near.horosphere)) {
        return columnDistanceOf(near) <= view.columnReach() + NODE_RADIUS;
    } else {
        return fabsf(near.plane.distanceTo(Point!float.origin())) <= GROUND_REACH + NODE_RADIUS;
    }
}

void discoverHorospheres(ref GraphView view, uint slot, ref Array!HorosphereRef found) {
    ParentList parents = view.parents(slot);
    foreach (link; parents.links[0 .. parents.count]) {
        foreach (near; view.ensureHorospheresAt(link.slot)) {
            if (!found.contains(near.horosphere)) {
                HorosphereRef moved = near.across(link.side, view.horospheres.isUpright(near.horosphere));
                if (view.isNear(moved)) {
                    found.append(moved);
                }
            }
        }
    }
    view.addRisingOver(slot, ROOT, found);
    size_t index = 0;
    while (index < found.length) {
        uint over = found.ptr[index].horosphere;
        if (!view.horospheres.isUpright(over)) {
            view.addRisingOver(slot, over, found);
        }
        index += 1;
    }
}

uint groundNodeOf(ref GraphView view, uint slot, uint horosphere) {
    uint current = slot;
    Vec4!double center = Vec4!double.origin();
    Plane start = view.planeOfHorosphereIn(horosphere, current);
    Plane carried = start;
    float altitude = fabsf(carried.distanceTo(Point!float.origin()));
    bool isDescending = altitude > DESCENT_ALTITUDE;
    while (isDescending) {
        Face lowest = Face.f0;
        float lowestAltitude = float.infinity;
        PlaneMeasure measured = carried.measure();
        double[FACE_COUNT] along = void;
        double least = double.infinity;
        foreach (index; 0 .. FACE_COUNT) {
            along[index] = fabs(measured.normal.minkowski(MIRRORED_ORIGINS[index].as!double()));
            least = lowerOf(least, along[index]);
        }
        foreach (index; 0 .. FACE_COUNT) {
            if (along[index] <= least * DESCENT_TIE_SLACK || along[index] * measured.scale < DESCENT_TIE_FLOOR) {
                float candidate = fabsf(measured.distanceTo(Point!float(MIRRORED_ORIGINS[index])));
                if (candidate < lowestAltitude) {
                    lowestAltitude = candidate;
                    lowest = cast(Face) index;
                }
            }
        }
        isDescending = lowestAltitude < altitude - DESCENT_TOLERANCE;
        if (isDescending) {
            current = view.ensureNeighborSlot(current, lowest);
            center = mirror(lowest).as!double() * center;
            carried = carried.reflectAcross(lowest);
            altitude = lowestAltitude;
            isDescending = altitude > DESCENT_ALTITUDE;
        }
    }
    Plane plane = start;
    if (current != slot) {
        plane = view.planeOfHorosphereIn(horosphere, current);
    }
    Vec4!double normal = plane.scaledNormal.as!double();
    normal = normal * (1.0 / sqrt(normal.minkowski(normal)));
    double along = center.minkowski(normal);
    Vec4!double foot = (center - normal * along) * (1.0 / sqrt(1.0 + along * along));
    float lift = GROUND_LIFT_FACTOR * FACE_DISTANCE;
    Vec4!double above = foot * cosh(lift) + normal * sinh(lift);
    Motion!float toAbove = Motion!float.shiftTo(Point!float(above.as!float()));
    return view.slotOf(view.ensureNormalized(Position(view.idAt(current), toAbove)).node);
}

bool isWithinRiseReach(Plane plane) {
    return fabsf(plane.distanceTo(Point!float.origin())) <= RISE_REACH + NODE_RADIUS;
}

void addRisingOver(ref GraphView view, uint slot, uint horosphere, ref Array!HorosphereRef found) {
    foreach (risen; view.risingFrom(view.groundNodeOf(slot, horosphere), horosphere)) {
        if (!found.contains(risen)) {
            HorosphereRef near = view.inheritedRefOf(risen, slot);
            bool isReached = isWithinRiseReach(near.plane);
            if (view.horospheres.isUpright(risen)) {
                isReached = columnDistanceOf(near) <= view.columnReach() + NODE_RADIUS;
            }
            if (isReached) {
                found.append(near);
            }
        }
    }
}

HorosphereRef inheritedRefOf(ref GraphView view, uint horosphere, uint slot) {
    ParentList parents = view.parents(slot);
    foreach (link; parents.links[0 .. parents.count]) {
        foreach (near; view.horospheresAt(link.slot)) {
            if (near.horosphere == horosphere) {
                return near.across(link.side, view.horospheres.isUpright(horosphere));
            }
        }
    }
    return view.refIn(horosphere, slot);
}

HorosphereRef refIn(ref const GraphView view, uint horosphere, uint slot) {
    const(Horosphere)* found = &view.horospheres.horosphere(horosphere);
    Array!Face path = view.pathBetween(found.footNode, slot);
    Plane[2] column = found.column;
    if (view.horospheres.isUpright(horosphere)) {
        column = [found.column[0].carriedAlong(path.slice()), found.column[1].carriedAlong(path.slice())];
    }
    HorosphereRef carried = HorosphereRef(found.plane.carriedAlong(path.slice()), column, horosphere);
    path.release();
    return carried;
}

const(uint)[] risingFrom(ref GraphView view, uint ground, uint horosphere) {
    GroundKey key = GroundKey(view.idAt(ground), horosphere);
    const(uint)[] known = view.knownRising(key);
    if (known !is null) {
        return known;
    } else {
        Face label = view.horospheres.labelOf(horosphere);
        uint[GROUND_RING] ring = view.groundRing(ground, label);
        uint[MOST_NEAR_RINGS] wide = void;
        uint wideCount = 0;
        foreach (face; ring) {
            foreach (outer; view.groundRing(face, label)) {
                if (!wide[0 .. wideCount].containsHorosphere(outer)) {
                    wide[wideCount] = outer;
                    wideCount += 1;
                }
            }
        }
        Array!uint found;
        foreach (face; wide[0 .. wideCount]) {
            bool isClose = ring[].containsHorosphere(face);
            foreach (index; 0 .. CORNER_COUNT) {
                Corner corner = cast(Corner) index;
                if (sideAxis(corner, label) < 3) {
                    Rise rise = view.riseAt(face, corner, horosphere);
                    if (rise.kind != NO_RISE && (isClose || view.horospheres.isUprightKind(rise.kind))) {
                        uint made = view.horosphereOver(face, corner, horosphere);
                        if (made != ROOT && !found.slice().containsHorosphere(made)) {
                            found.append(made);
                        }
                    }
                }
            }
        }
        const(uint)[] stored = view.storeRising(key, found.slice());
        found.release();
        return stored;
    }
}

bool containsHorosphere(const(uint)[] list, uint horosphere) {
    size_t index = 0;
    while (index < list.length && list[index] != horosphere) {
        index += 1;
    }
    return index < list.length;
}

Rise riseAt(ref GraphView view, uint face, Corner corner, uint horosphere) {
    ClaimKey rooted = view.rootedCorner(face, corner).key;
    SlotCorner at = SlotCorner(rooted.slot, corner);
    if (view.hasChoice(at)) {
        return view.choiceAt(at);
    } else {
        Rise rise = view.chosenRise(face, corner, horosphere, view.cornerKeyOf(rooted));
        view.storeChoice(at, rise);
        return rise;
    }
}

uint horosphereOver(ref GraphView view, uint face, Corner corner, uint horosphere) {
    Rise rise = view.riseAt(face, corner, horosphere);
    if (rise.kind == NO_RISE) {
        return ROOT;
    } else {
        return view.ensureHorosphere(view.rootedCorner(face, corner).key, face, corner, horosphere, rise);
    }
}

SiteFrame[GROUND_EDGES] neighborsOf(ref GraphView view, SiteFrame site) {
    SiteFrame[GROUND_EDGES] neighbors = void;
    SiteFrame heading = site;
    foreach (edge; 0 .. GROUND_EDGES) {
        neighbors[edge] = forwarded(heading, 1);
        heading = view.turned(heading, Turn.right);
    }
    return neighbors;
}

bool isOutranked(ref GraphView view, SiteFrame neighbor, ulong mine) {
    ulong theirs = view.siteHash(neighbor, SitePart.vertex);
    return view.horospheres.forced.find(view.cornerKeyOf(view.siteOrigin(neighbor).key)) !is null || (view.horospheres.rolled(theirs).kind != NO_RISE && theirs > mine);
}

Rise chosenRise(ref GraphView view, uint face, Corner corner, uint horosphere, CornerKey key) {
    const(Rise)* forcedRise = view.horospheres.forced.find(key);
    if (forcedRise !is null) {
        return *forcedRise;
    } else {
        SiteFrame site = groundSite(face, corner, view.horospheres.labelOf(horosphere));
        ulong mine = view.siteHash(site, SitePart.vertex);
        Rise rise = view.horospheres.rolled(mine);
        SiteFrame[GROUND_EDGES] neighbors = view.neighborsOf(site);
        uint edge = 0;
        while (rise.kind != NO_RISE && edge < GROUND_EDGES && !view.isOutranked(neighbors[edge], mine)) {
            edge += 1;
        }
        if (edge == GROUND_EDGES && view.isRiseClear(face, corner, horosphere, rise)) {
            return rise;
        } else {
            return Rise(NO_RISE, 0);
        }
    }
}

Vec4!float[2] riseLineOver(Corner corner, Face label, float edge) {
    Corner upper = corner.across[sideAxis(corner, label)];
    Vec4!float base = (corner.cornerToNode * Point!float.origin()).v;
    Vec4!float next = (upper.cornerToNode * Point!float.origin()).v;
    return [base, (next - base * coshf(edge)) * (1.0f / sinhf(edge))];
}

Plane risenPlaneOver(Corner corner, Face label, ubyte edges, float edge) {
    Vec4!float[2] line = riseLineOver(corner, label, edge);
    float rise = edges * edge;
    return Plane.fromNormal(-(line[0] * sinhf(rise) + line[1] * coshf(rise)));
}

bool isRayApart(Vec4!float base, Vec4!float along, Plane plane, float separation) {
    Vec4!double normal = plane.scaledNormal().as!double();
    normal = normal * (1.0 / sqrt(normal.minkowski(normal)));
    double a = base.as!double().minkowski(normal);
    double b = along.as!double().minkowski(normal);
    double least = fabs(a);
    if ((a > 0) != (b > 0)) {
        double remaining = a * a - b * b;
        least = 0;
        if (remaining > 0) {
            least = sqrt(remaining);
        }
    }
    return least >= sinh(separation);
}

bool isRiseClear(ref GraphView view, uint face, Corner corner, uint horosphere, Rise rise) {
    if (view.horospheres.isUprightKind(rise.kind)) {
        return view.isColumnClearOfAncestors(face, corner, horosphere);
    } else {
        return view.isClearOfAncestors(face, corner, horosphere, rise.edges);
    }
}

bool isColumnClearOfAncestors(ref GraphView view, uint face, Corner corner, uint horosphere) {
    Vec4!float[2] line = riseLineOver(corner, view.horospheres.labelOf(horosphere), view.edgeOf());
    float separation = CLEARANCE_EDGES * view.edgeOf();
    uint ancestor = horosphere;
    bool isClear = true;
    while (isClear && ancestor != ROOT) {
        ancestor = view.horospheres.horosphere(ancestor).parent;
        isClear = isRayApart(line[0], line[1], view.planeOfHorosphereIn(ancestor, face), separation);
    }
    return isClear;
}

Plane planeOfHorosphereIn(ref GraphView view, uint horosphere, uint slot) {
    if (horosphere == ROOT) {
        return view.stateAt(slot).surface;
    } else {
        return view.refIn(horosphere, slot).plane;
    }
}

bool isApart(Plane first, Plane second, float separation) {
    double product = fabs(first.scaledNormal().minkowski(second.scaledNormal()));
    return product > 0 && log(product) + logCosh(first.height) + logCosh(second.height) >= log(cosh(separation)) - APART_TOLERANCE;
}

bool isClearOfAncestors(ref GraphView view, uint face, Corner corner, uint horosphere, ubyte edges) {
    Plane candidate = risenPlaneOver(corner, view.horospheres.labelOf(horosphere), edges, view.edgeOf());
    float separation = CLEARANCE_EDGES * view.edgeOf();
    uint ancestor = horosphere;
    bool isClear = true;
    while (isClear && ancestor != ROOT) {
        ancestor = view.horospheres.horosphere(ancestor).parent;
        isClear = isApart(candidate, view.planeOfHorosphereIn(ancestor, face), separation);
    }
    return isClear;
}

uint airSideNode(ref Graph graph, uint node, Corner corner, Face label) {
    uint slot = node;
    bool isAcross = false;
    bool isLowest = false;
    while (!isLowest) {
        ParentList parents = graph.parents(slot);
        uint index = 0;
        while (index < parents.count && sideAxis(corner, parents.links[index].side) == 3) {
            index += 1;
        }
        isLowest = index == parents.count;
        if (!isLowest) {
            if (parents.links[index].side == label) {
                isAcross = !isAcross;
            }
            slot = parents.links[index].slot;
        }
    }
    if (isAcross) {
        slot = graph.ensureNeighborSlot(slot, label);
    }
    return slot;
}

Horosphere risenHorosphere(ref Graph graph, uint face, Corner corner, uint parent, Rise rise) {
    Face parentLabel = graph.horospheres.labelOf(parent);
    if (graph.horospheres.isUprightKind(rise.kind)) {
        Plane[2] column;
        uint count = 0;
        foreach (side; corner.faces) {
            if (side != parentLabel) {
                column[count] = Plane.ofFace(side);
                count += 1;
            }
        }
        return Horosphere(graph.view.planeOfHorosphereIn(parent, face), column, groundSite(face, corner, parentLabel), CornerKey.init, 0, parent, face, 0, 0, 0, 0, 0, parentLabel, cast(ubyte)(rise.kind - 1), rise.edges, false, true);
    } else {
        SiteFrame tower = graph.view.turned(groundSite(face, corner, parentLabel), Turn.pitchUp);
        SiteFrame top = graph.view.atLevel(forwarded(tower, rise.edges), 0);
        Face label = top.zSide();
        uint foot = graph.airSideNode(top.node, top.corner, label);
        return Horosphere(-Plane.ofFace(label), [Plane.init, Plane.init], groundSite(foot, top.corner, label), CornerKey.init, 0, parent, foot, 0, 0, 0, 0, 0, label, cast(ubyte)(rise.kind - 1), rise.edges, false, true);
    }
}

uint makeHorosphere(ref Graph graph, ClaimKey rooted, uint face, Corner corner, uint parent, Rise rise) {
    CornerKey key = graph.view.cornerKeyOf(rooted);
    Horosphere made = graph.risenHorosphere(face, corner, parent, rise);
    made.key = key;
    made.keySlot = rooted.slot;
    uint index = void;
    if (graph.horospheres.freeHorospheres.length > 0) {
        index = graph.horospheres.freeHorospheres.ptr[graph.horospheres.freeHorospheres.length - 1];
        graph.horospheres.freeHorospheres.length -= 1;
        graph.horospheres.horospheres.ptr[index - 1] = made;
    } else {
        graph.horospheres.horospheres.append(made);
        index = cast(uint) graph.horospheres.horospheres.length;
    }
    graph.horospheres.horosphereOf.insert(key, index);
    graph.reference(made.footNode);
    graph.reference(rooted.slot);
    if (parent != ROOT) {
        graph.horospheres.horospheres.ptr[parent - 1].users += 1;
    }
    return index;
}

bool isIdle(ref const Graph graph, ref const Horosphere horosphere) {
    return horosphere.isKnown && horosphere.users == 0 && horosphere.tiles == 0 && graph.horospheres.forced.find(horosphere.key) is null;
}

void releaseIdleHorospheres(ref Graph graph) {
    bool isReleased = false;
    foreach (index; 0 .. graph.horospheres.horospheres.length) {
        uint idle = cast(uint) index + 1;
        while (idle != ROOT && graph.isIdle(graph.horospheres.horosphere(idle))) {
            uint parent = graph.horospheres.horosphere(idle).parent;
            graph.releaseHorosphere(idle);
            isReleased = true;
            idle = parent;
        }
    }
    if (isReleased) {
        graph.horospheres.forgetRising();
    }
}

void releaseHorosphere(ref Graph graph, uint index) {
    Horosphere released = graph.horospheres.horosphere(index);
    graph.unreference(released.footNode);
    graph.unreference(released.keySlot);
    graph.horospheres.horosphereOf.remove(released.key);
    if (released.parent != ROOT) {
        graph.horospheres.horospheres.ptr[released.parent - 1].users -= 1;
    }
    graph.horospheres.horospheres.ptr[index - 1] = Horosphere.init;
    graph.horospheres.freeHorospheres.append(index);
}

bool openHorosphere(ref Graph graph, SiteFrame site, Rise rise) {
    SiteFrame at = graph.view.atLevel(site, 0);
    SiteFrame ground = groundSite(at.node, at.corner, at.ySide);
    uint besides = 0;
    foreach (neighbor; graph.view.neighborsOf(ground)) {
        if (graph.horospheres.forced.find(graph.view.cornerKeyOf(graph.view.siteOrigin(neighbor).key)) !is null) {
            besides += 1;
        }
    }
    if (besides > 0) {
        return false;
    } else {
        ClaimKey key = graph.view.siteOrigin(ground).key;
        graph.horospheres.forced.insert(graph.view.cornerKeyOf(key), rise);
        graph.reference(key.slot);
        return true;
    }
}

Grounds groundsAt(ref GraphView view, uint slot) {
    Plane surface = view.stateAt(slot).surface;
    return groundsOf(view.horospheres, surface, view.ensureHorospheresAt(slot));
}

Grounds groundsIn(ref const Graph graph, uint slot) {
    return groundsOf(graph.horospheres, graph.stateAt(slot).surface, graph.horospheres.horospheresAt(slot));
}

Grounds groundsOf(ref const Horospheres horospheres, Plane surface, const(HorosphereRef)[] near) {
    Grounds grounds;
    grounds.items[0] = Ground(surface, horospheres.fillOf(ROOT));
    grounds.count = 1;
    foreach (found; near) {
        if (!horospheres.isUpright(found.horosphere) && fabsf(found.plane.distanceTo(Point!float.origin())) <= GROUND_REACH) {
            Ground ground = Ground(found.plane, horospheres.fillOf(found.horosphere));
            if (grounds.count < MAX_GROUNDS) {
                grounds.items[grounds.count] = ground;
                grounds.count += 1;
            } else {
                uint farthest = grounds.farthestRisen();
                if (fabsf(found.plane.distanceTo(Point!float.origin())) < fabsf(grounds.items[farthest].surface.distanceTo(Point!float.origin()))) {
                    grounds.items[farthest] = ground;
                }
            }
        }
    }
    return grounds;
}

ChunkPoint chunkPointOf(Point!float point) {
    ChunkPoint best;
    float leastOutside = float.infinity;
    foreach (index; 0 .. CORNER_COUNT) {
        Corner corner = cast(Corner) index;
        Vec4!float dual = corner.nodeToCorner * point.v;
        float[3] coords = void;
        float outside = 0;
        foreach (axis; 0 .. 3) {
            coords[axis] = dual.c[axis] / dual.c[3] * (1 / cubeScale());
            outside = higherOf(-coords[axis], outside);
            outside = higherOf(coords[axis] - 1, outside);
        }
        if (outside < leastOutside) {
            leastOutside = outside;
            best = ChunkPoint(coords, corner);
        }
    }
    return best;
}

float heightAbove(float relief, float altitude, bool isFlat) {
    if (isFlat) {
        return altitude;
    } else {
        return altitude - relief;
    }
}

bool isGravityKnown(ref const Graph graph, uint slot) {
    return graph.nodeAt(slot).hasState && graph.horospheres.hasHorospheresAt(slot);
}

Gravity ensureGravityAt(ref Graph graph, Position position) {
    uint slot = graph.slotOf(position.node);
    graph.ensureState(slot);
    graph.view.ensureHorospheresAt(slot);
    return graph.gravityAt(position);
}

const(Look)* lookOfGround(ref const Graph graph, uint horosphere) {
    ubyte kind = graph.horospheres.kindOf(horosphere);
    if (kind != NO_RISE && graph.horospheres.kinds.ptr[kind - 1].look.name !is null) {
        return &graph.horospheres.kinds.ptr[kind - 1].look;
    } else {
        return &graph.structures.blueprint.look;
    }
}

const(Look)* lookAt(ref const Graph graph, Position position) {
    uint slot = graph.slotOf(position.node);
    if (!graph.isGravityKnown(slot)) {
        return &graph.structures.blueprint.look;
    } else {
        Point!float point = position.local * Point!float.origin();
        uint nearest = ROOT;
        float least = fabsf(graph.stateAt(slot).surface.distanceTo(point));
        foreach (near; graph.horospheres.horospheresAt(slot)) {
            float away = fabsf(near.plane.distanceTo(point));
            if (!graph.horospheres.isUpright(near.horosphere) && away < least) {
                least = away;
                nearest = near.horosphere;
            }
        }
        return graph.lookOfGround(nearest);
    }
}

Gravity gravityAt(ref const Graph graph, Position position) {
    uint slot = graph.slotOf(position.node);
    assert(graph.isGravityKnown(slot));
    Grounds grounds = graph.groundsIn(slot);
    float sign = graph.horospheres.gravitySign();
    if (grounds.count == 1) {
        return Gravity(grounds.items[0].surface.upAt(position.local).scaled(sign), 1.0f);
    } else {
        Point!float point = position.local * Point!float.origin();
        float relief = graph.loadedClimateAt(slot, point).relief;
        float[MAX_GROUNDS] heights = void;
        float[3][MAX_GROUNDS] ups = void;
        foreach (index, ground; grounds.items[0 .. grounds.count]) {
            heights[index] = sign * heightAbove(relief, ground.surface.distanceTo(point), ground.fill != Fill.terrain);
            ups[index] = ground.surface.upAt(position.local).scaled(sign);
        }
        return blendedGravity(heights[0 .. grounds.count], ups[0 .. grounds.count]);
    }
}

Gravity blendedGravity(const(float)[] heights, const(float[3])[] ups) {
    size_t nearest = 0;
    foreach (index, height; heights) {
        if (height < heights[nearest]) {
            nearest = index;
        }
    }
    float[3] up = ups[nearest];
    float along = 0;
    float total = 0;
    foreach (index, height; heights) {
        float weight = expf(-(height - heights[nearest]) / GRAVITY_FALLOFF);
        along += weight * (ups[index][0] * up[0] + ups[index][1] * up[1] + ups[index][2] * up[2]);
        total += weight;
    }
    return Gravity(up, higherOf(0.0f, along / total));
}

bool isPaintedBy(ref GraphView view, uint slot, HorosphereRef near) {
    return view.horospheres.isUpright(near.horosphere) || view.isOnRisenSide(slot, near) || view.isOnFootLine(slot, near.horosphere);
}

bool isOnRisenSide(ref GraphView view, uint slot, HorosphereRef near) {
    Point!float center = Point!float.origin();
    float relief = view.stateAt(slot).climate.climate().relief;
    uint parent = view.horospheres.horosphere(near.horosphere).parent;
    float own = heightAbove(relief, near.plane.distanceTo(center), view.horospheres.isFlat(near.horosphere));
    float other = heightAbove(relief, view.planeOfHorosphereIn(parent, slot).distanceTo(center), view.horospheres.isFlat(parent));
    return own - other <= RISEN_SIDE_MARGIN;
}

bool isOnFootLine(ref const GraphView view, uint slot, uint horosphere) {
    const(Horosphere)* found = &view.horospheres.horosphere(horosphere);
    Array!Face path = view.pathBetween(found.footNode, slot);
    float coshSquared = 1;
    foreach (side; found.foot.corner.faces) {
        if (side != found.label) {
            float across = sinhf(Plane.ofFace(side).carriedAlong(path.slice()).distanceTo(Point!float.origin()));
            coshSquared += across * across;
        }
    }
    path.release();
    float reach = coshf(edgeLineDistance() + LINE_TOLERANCE);
    return coshSquared <= reach * reach;
}

float edgeLineDistance() {
    Vec4!float corner = (Corner.c0.cornerToNode * Point!float.origin()).v;
    Vec4!float next = (Corner.c0.across[0].cornerToNode * Point!float.origin()).v;
    Vec4!float edge = next + corner * corner.minkowski(next);
    Vec4!float along = edge * (1.0f / sqrtf(edge.minkowski(edge)));
    Vec4!float center = Point!float.origin().v;
    float alongCorner = center.minkowski(corner);
    float alongEdge = center.minkowski(along);
    return acoshf(sqrtf(alongCorner * alongCorner - alongEdge * alongEdge));
}

bool isInBand(Plane plane, Fill fill, float relief) {
    float altitude = plane.distanceTo(Point!float.origin());
    float top = 0;
    float bottom = 0;
    if (fill == Fill.terrain) {
        top = lowerOf(relief + RELIEF_SLACK, RELIEF_BOUND);
        bottom = higherOf(relief - RELIEF_SLACK, -RELIEF_BOUND);
    }
    return fill != Fill.none && altitude - NODE_RADIUS < top && altitude + NODE_RADIUS > bottom;
}

bool mayHoldContent(ref Graph graph, uint slot) {
    NodeState state = *graph.ensureState(slot);
    float relief = state.climate.climate().relief;
    bool holds = isInBand(state.surface, graph.horospheres.fillOf(ROOT), relief);
    foreach (near; graph.view.ensureHorospheresAt(slot)) {
        holds = holds || graph.horospheres.isUpright(near.horosphere) || isInBand(near.plane, graph.horospheres.fillOf(near.horosphere), relief);
    }
    return holds || graph.ensureStructureAt(slot);
}

float horosphereHeightAt(ref GraphView view, uint horosphere, Position position) {
    uint slot = view.slotOf(position.node);
    Point!float point = position.local * Point!float.origin();
    float relief = view.climateAt(slot, point).relief;
    return heightAbove(relief, view.planeOfHorosphereIn(horosphere, slot).distanceTo(point), view.horospheres.isFlat(horosphere));
}

float planeHeightAt(ref GraphView view, uint horosphere, Position position) {
    return view.planeOfHorosphereIn(horosphere, view.slotOf(position.node)).distanceTo(position.local * Point!float.origin());
}

Climate climateAt(ref GraphView view, uint slot, Point!float point) {
    ChunkPoint at = chunkPointOf(point);
    return CubeClimate.around(view, slot, at.corner).at(at.coords);
}

Climate loadedClimateAt(ref const Graph graph, uint slot, Point!float point) {
    ChunkPoint at = chunkPointOf(point);
    Face[3] sides = at.corner.faces;
    NodeClimate own = graph.stateAt(slot).climate;
    NodeClimate[8] around;
    foreach (crossed; 0 .. 8) {
        uint node = slot;
        foreach (axis; 0 .. 3) {
            if (node != NO_SLOT && (crossed & (1u << axis)) != 0) {
                node = graph.neighborSlot(node, sides[axis]);
            }
        }
        around[crossed] = own;
        if (node != NO_SLOT && graph.nodeAt(node).hasState) {
            around[crossed] = graph.stateAt(node).climate;
        }
    }
    return CubeClimate.fromAround(around).at(at.coords);
}

Position cellOnLine(ref GraphView view, SiteFrame line, int cell) {
    Point!float inSite = sitePlacement(line, view.layout) * columnPoint(view.layout, ColumnSpot(0, 0, cell + 0.5f));
    return view.ensureNormalized(Position(view.idAt(line.node), Motion!float.shiftTo(inSite)));
}

int groundAlong(ref GraphView view, SiteFrame line, uint horosphere, int span) {
    int cell = -span;
    while (cell < span && view.horosphereHeightAt(horosphere, view.cellOnLine(line, cell)) < 0) {
        cell += 1;
    }
    return cell;
}

bool isRisenNearer(ref GraphView view, SiteFrame line, uint horosphere, int cell) {
    Position at = view.cellOnLine(line, cell);
    return view.planeHeightAt(horosphere, at) < view.planeHeightAt(view.horospheres.horosphere(horosphere).parent, at);
}

int balanceAlong(ref GraphView view, SiteFrame line, uint horosphere, int most) {
    int nearer = 0;
    int farther = 1;
    while (farther < most && view.isRisenNearer(line, horosphere, farther)) {
        nearer = farther;
        farther = lowerOf(farther * 2, most);
    }
    if (farther == most && view.isRisenNearer(line, horosphere, most)) {
        return most;
    } else {
        while (farther - nearer > 1) {
            int middle = (nearer + farther) / 2;
            if (view.isRisenNearer(line, horosphere, middle)) {
                nearer = middle;
            } else {
                farther = middle;
            }
        }
        return farther;
    }
}

struct RiseMeasure {
    int ground;
    int below;
    int balance;
}

RiseMeasure measureOf(ref GraphView view, uint horosphere) {
    Horosphere measured = view.horospheres.horosphere(horosphere);
    if (view.horospheres.isUpright(horosphere)) {
        return RiseMeasure.init;
    } else {
        int span = measured.edges * edgeCells(view.layout.dimension);
        SiteFrame up = view.turned(measured.foot, Turn.pitchUp);
        SiteFrame down = view.turned(view.turned(forwarded(up, measured.edges), Turn.pitchUp), Turn.pitchUp);
        return RiseMeasure(view.groundAlong(up, horosphere, span), view.groundAlong(down, measured.parent, span), view.balanceAlong(up, horosphere, span));
    }
}

void storeMeasure(ref Graph graph, uint horosphere, RiseMeasure measure) {
    Horosphere* stored = &graph.horospheres.horospheres.ptr[horosphere - 1];
    stored.ground = measure.ground;
    stored.below = measure.below;
    stored.balance = measure.balance;
    stored.isMeasured = true;
}

ref const(Horosphere) measuredHorosphere(ref Graph graph, uint horosphere) {
    if (!graph.horospheres.horosphere(horosphere).isMeasured) {
        graph.storeMeasure(horosphere, graph.view.measureOf(horosphere));
    }
    return graph.horospheres.horosphere(horosphere);
}

int[2] segmentsNear(ref GraphView view, ref const HorosphereRef near) {
    float edge = view.edgeOf();
    float height = near.plane.distanceTo(Point!float.origin());
    return [higherOf(0, cast(int) floorf((height - NODE_RADIUS) / edge) - 2), cast(int) floorf((height + NODE_RADIUS) / edge) + 1];
}

SiteFrame segmentSite(ref GraphView view, uint horosphere, int segment) {
    const(Horosphere)* found = &view.horospheres.horosphere(horosphere);
    return view.atLevel(forwarded(view.turned(found.foot, Turn.pitchUp), segment), 0);
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.fromStructure(StructureWorld.fromName("test")));
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.bare, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openHorosphere(root, Rise(1, LOWEST_RISE_EDGES)));
    assert(!graph.openHorosphere(forwarded(root, 1), Rise(1, LOWEST_RISE_EDGES)));
    uint risen = graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT);
    assert(risen != ROOT);
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.horospheres.horosphere(risen).footNode), Motion!float.identity()), TEST_RADIUS);
    foreach (node; nearby) {
        const(HorosphereRef)[] found = graph.view.ensureHorospheresAt(node.slot);
        foreach (near; found) {
            assert(fabsf(graph.view.planeOfHorosphereIn(near.horosphere, node.slot).distanceTo(Point!float.origin()) - near.plane.distanceTo(Point!float.origin())) < TEST_PLANE_TOLERANCE);
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
    assert(fabsf(footAltitude - anchorAltitude) < TEST_PLANE_TOLERANCE);
    uint[GROUND_RING] ring = graph.view.groundRing(graph.anchorSlot, Face.f0);
    SiteFrame high = graph.view.atLevel(forwarded(graph.view.turned(root, Turn.pitchUp), TEST_RISE_EDGES), 0);
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
            assert(fabsf(ground - FACE_DISTANCE) < TEST_PLANE_TOLERANCE);
        }
    }
    assert(graph.view.isOnFootLine(made.footNode, risen));
    assert(!graph.view.isOnFootLine(graph.view.atLevel(forwarded(made.foot, TEST_FAR_EDGES), 0).node, risen));
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
    foreach (cell; TEST_PAINTED_CELLS) {
        Point!float fromRisen = graph.view.siteToNode(risenTower, risenTower.node) * columnPoint(graph.layout, ColumnSpot(cell[0] + 0.5f, cell[1] + 0.5f, cell[2] + 0.5f));
        Point!float fromRoot = graph.view.siteToNode(rootTower, risenTower.node) * columnPoint(graph.layout, ColumnSpot(cell[1] + 0.5f, cell[0] + 0.5f, length - cell[2] - 0.5f));
        assert(isSamePoint(fromRisen, fromRoot));
    }
    BlueprintBuilder builder = BlueprintBuilder.make(graph);
    foreach (cell; TEST_PAINTED_CELLS) {
        assert(builder.paint(risenTower, CellBox.make(cell[0], cell[0], cell[1], cell[1], cell[2], cell[2]), EVERY_HEIGHT, Material.granite, false) == PaintResult.painted);
    }
    foreach (cell; TEST_PAINTED_CELLS) {
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
    Plane over = risenPlaneOver(root.corner, Face.f0, LOWEST_RISE_EDGES, graph.view.edgeOf());
    Plane stored = graph.view.planeOfHorosphereIn(risen, graph.anchorSlot);
    assert(fabsf(over.distanceTo(Point!float.origin()) - stored.distanceTo(Point!float.origin())) < TEST_PLANE_TOLERANCE);
    float[3] down = [0, -1, 0];
    float[3] up = [0, 1, 0];
    float[2] equal = [0.5f, 0.5f];
    float[3][2] opposed = [up, down];
    assert(blendedGravity(equal[], opposed[]).strength < TEST_PLANE_TOLERANCE);
    float[1] alone = [0.5f];
    float[3][1] single = [up];
    assert(blendedGravity(alone[], single[]).strength == 1.0f);
    scratch.release();
    graph.release();
}

unittest {
    Horospheres horospheres;
    horospheres.kinds.append(HorosphereKind(0, HorosphereForm.bare, 0));
    HorosphereRef[TEST_GROUND_HEIGHTS.length] near;
    foreach (index, height; TEST_GROUND_HEIGHTS) {
        horospheres.horospheres.append(Horosphere.init);
        near[index] = HorosphereRef(Plane([0, 1, 0], height), [Plane.init, Plane.init], cast(uint) index + 1);
    }
    Grounds grounds = groundsOf(horospheres, Plane.ofFace(Face.f0), near[]);
    assert(grounds.count == MAX_GROUNDS);
    foreach (ground; grounds.items[1 .. grounds.count]) {
        assert(fabsf(ground.surface.height) < TEST_FARTHEST_GROUND);
    }
    horospheres.release();
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.makeTerrain());
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.terrain, 0));
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.bare, 1));
    SiteFrame root = rootSite(graph.anchorSlot);
    SiteFrame beside = graph.view.turned(forwarded(graph.view.turned(root, Turn.right), 2), Turn.left);
    assert(graph.openHorosphere(root, Rise(1, LOWEST_RISE_EDGES)));
    assert(graph.openHorosphere(beside, Rise(2, LOWEST_RISE_EDGES)));
    uint risen = graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT);
    assert(risen != ROOT);
    Horosphere made = graph.horospheres.horosphere(risen);
    uint solid = graph.ensureNeighborSlot(made.footNode, made.label);
    GeneratedVoxels generated = ChunkParams.make(graph.view, solid, made.foot.corner).generateVoxels();
    assert(!generated.voxels.isFilledWith(Material.none));
    generated.voxels.release();
    SiteFrame at = graph.view.atLevel(beside, 0);
    uint bare = graph.view.horosphereOver(at.node, at.corner, ROOT);
    Horosphere empty = graph.horospheres.horosphere(bare);
    generated = ChunkParams.make(graph.view, graph.ensureNeighborSlot(empty.footNode, empty.label), empty.foot.corner).generateVoxels();
    assert(generated.voxels.isFilledWith(Material.none));
    generated.voxels.release();
    graph.release();
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.fromStructure(StructureWorld.fromName("test")));
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.upright, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openHorosphere(root, Rise(1, LOWEST_RISE_EDGES)));
    uint upright = graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT);
    assert(graph.horospheres.isUpright(upright));
    SiteFrame high = graph.view.segmentSite(upright, TEST_RISE_EDGES);
    bool isFound = false;
    foreach (near; graph.view.ensureHorospheresAt(high.node)) {
        if (near.horosphere == upright) {
            isFound = true;
            int[2] segments = graph.view.segmentsNear(near);
            assert(segments[0] <= TEST_RISE_EDGES && segments[1] >= TEST_RISE_EDGES);
            assert(columnDistanceOf(near) < NODE_RADIUS);
        }
    }
    assert(isFound);
    float edge = graph.view.edgeOf();
    Vec4!float[2] line = riseLineOver(root.corner, Face.f0, edge);
    Plane above = risenPlaneOver(root.corner, Face.f0, LOWEST_RISE_EDGES, edge);
    assert(!isRayApart(line[0], line[1], above, edge));
    assert(isRayApart(line[0], -line[1], above, edge));
    graph.release();
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.fromStructure(StructureWorld.fromName("test")));
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.bare, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openHorosphere(root, Rise(1, LOWEST_RISE_EDGES)));
    uint first = graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT);
    SiteFrame along = graph.view.atLevel(forwarded(graph.horospheres.horosphere(first).foot, TEST_ALONG_EDGES), 0);
    assert(graph.openHorosphere(along, Rise(1, LOWEST_RISE_EDGES)));
    uint second = graph.view.horosphereOver(along.node, along.corner, first);
    assert(second != ROOT && graph.horospheres.horosphere(second).parent == first);
    uint foot = graph.horospheres.horosphere(second).footNode;
    float separation = CLEARANCE_EDGES * graph.view.edgeOf();
    assert(isApart(graph.view.planeOfHorosphereIn(second, foot), graph.view.planeOfHorosphereIn(ROOT, foot), separation));
    bool isFound = false;
    foreach (near; graph.view.ensureHorospheresAt(foot)) {
        isFound = isFound || near.horosphere == second;
    }
    assert(isFound);
    graph.release();
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.fromStructure(StructureWorld.fromName("test")));
    graph.horospheres.kinds.append(HorosphereKind(1, HorosphereForm.bare, 0));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openHorosphere(root, Rise(1, LOWEST_RISE_EDGES)));
    uint first = graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT);
    float separation = CLEARANCE_EDGES * graph.view.edgeOf();
    uint risen = 0;
    foreach (edges; TEST_ALONG_EDGES .. TEST_FARTHEST_EDGES + 1) {
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
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.fromStructure(StructureWorld.fromName("test")));
    graph.horospheres.kinds.append(HorosphereKind(0, HorosphereForm.bare, 0));
    graph.horospheres.kinds.append(HorosphereKind(1, HorosphereForm.upright, 1));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openHorosphere(root, Rise(1, LOWEST_RISE_EDGES)));
    uint first = graph.view.horosphereOver(graph.anchorSlot, root.corner, ROOT);
    float edge = graph.view.edgeOf();
    uint trees = 0;
    foreach (edges; 0 .. TEST_FARTHEST_EDGES + 1) {
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
