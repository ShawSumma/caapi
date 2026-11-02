module common.worldgen.horospheres;

import core.math : sqrt;
import core.stdc.math : acoshf, cosh, coshf, expf, fabs, fabsf, floorf, log, sinh, sinhf, sqrtf;
import core.stdc.string : memcpy;
import base.array : Array;
import base.flags : Readiness;
import base.hashmap : FIBONACCI_MULTIPLIER, HashMap;
import base.maybe : Maybe;
import base.numbers : higherOf, lowerOf;
import base.slab : Run, RunPool, Slab;
import base.splitmix : unitOf;
import base.vector3 : cross, dot, magnitude, negated, scaled;
import common.graph : Graph, NO_SLOT, NodeId, ParentEntry, ParentList;
import common.position : Position;
import common.traversal : MIRRORED_ORIGINS;
import common.view : GraphView, SlotCorner;
import common.worldgen.blueprint : floorDivision;
import common.worldgen.climate : Climate, CubeClimate, NodeClimate, RELIEF_BOUND, RELIEF_SLACK;
import common.worldgen.generation : NodeState;
import common.worldgen.plane : Plane, PlaneMeasure, logCosh;
import common.worldgen.structure : ClaimKey, ColumnSpot, GROUND_RING, SiteFrame, atLevel, columnPoint, edgeCells, edgeLength, forwarded, groundRing, groundSite, parentOnCorner, pathBetween, rootedCorner, sideAxis, siteHash, siteOrigin, sitePlacement, turned;
import geometry.honeycomb : CORNER_COUNT, Corner, FACE_COUNT, FACE_DISTANCE, Face, NODE_RADIUS, across, cornerToNode, cubeScale, faces, mirror, nodeToCorner;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : HorosphereForm, Look, NO_KIND, SitePart, Turn;

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
enum int COLUMN_GROUND_EDGES = 3;
enum float COLUMN_GRAVITY_REACH = 0.8f;

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
    uint under;
}

struct Rise {
    ubyte kind;
    ubyte edges;
}

enum HorosphereStage : ubyte {
    free,
    open,
    measured,
}

enum GravityPull : ubyte {
    down,
    up,
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
    HorosphereStage stage;

    bool isMeasured() const {
        return stage == HorosphereStage.measured;
    }
}

struct HorosphereRef {
    Plane plane;
    Plane[2] column;
    uint horosphere;

    HorosphereRef across(Face side, ref const Horospheres horospheres) const {
        Face[1] path = [side];
        Plane[2] carried = column;
        if (horospheres.isUpright(horosphere)) {
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

float columnDistanceOf(ref const HorosphereRef near, Point!float point) {
    float first = sinhf(near.column[0].distanceTo(point));
    float second = sinhf(near.column[1].distanceTo(point));
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
    Readiness state;
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
    GravityPull pull;

    float gravitySign() const {
        if (pull == GravityPull.up) {
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
        return index != ROOT && isUprightKind(cast(ubyte)(horosphere(index).kind + 1));
    }

    bool isUprightKind(ubyte kind) const {
        return kinds.ptr[kind - 1].form != HorosphereForm.terrain && kinds.ptr[kind - 1].form != HorosphereForm.bare;
    }

    bool isSunken(uint index) const {
        return index != ROOT && kinds.ptr[horosphere(index).kind].form == HorosphereForm.sunken;
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

    bool hasHorospheresAt(uint slot) const {
        return nodes.at(slot).state == Readiness.ready;
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
        *nodes.at(slot) = NodeHorospheres(run, Readiness.ready);
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

size_t makeWantedHorospheres(ref Graph target, ref GraphView view) {
    size_t made = view.wanted.length;
    foreach (want; view.wanted.slice()) {
        uint face = want.start;
        foreach (side; view.wantedPaths.ptr[want.pathStart .. want.pathStart + want.pathLength]) {
            face = target.ensureNeighborSlot(face, side);
        }
        target.view.horosphereOver(face, want.corner, want.parent);
    }
    view.clearWanted();
    return made;
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
        return columnDistanceOf(near, Point!float.origin()) <= view.columnReach() + NODE_RADIUS;
    } else {
        return fabsf(near.plane.distanceTo(Point!float.origin())) <= GROUND_REACH + NODE_RADIUS;
    }
}

void discoverHorospheres(ref GraphView view, uint slot, ref Array!HorosphereRef found) {
    ParentList parents = view.parents(slot);
    foreach (link; parents.links[0 .. parents.count]) {
        foreach (near; view.ensureHorospheresAt(link.slot)) {
            if (!found.contains(near.horosphere)) {
                HorosphereRef moved = near.across(link.side, view.horospheres);
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
    Plane carried = view.planeOfHorosphereIn(horosphere, current);
    float altitude = fabsf(carried.distanceTo(Point!float.origin()));
    while (altitude > DESCENT_ALTITUDE) {
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
        if (!(lowestAltitude < altitude - DESCENT_TOLERANCE)) {
            break;
        }
        current = view.ensureNeighborSlot(current, lowest);
        center = mirror(lowest).as!double() * center;
        carried = view.planeOfHorosphereIn(horosphere, current);
        altitude = fabsf(carried.distanceTo(Point!float.origin()));
    }
    Vec4!double normal = carried.scaledNormal.as!double();
    normal = normal * (1.0 / sqrt(normal.minkowski(normal)));
    double along = center.minkowski(normal);
    Vec4!double foot = (center - normal * along) * (1.0 / sqrt(1.0 + along * along));
    float lift = GROUND_LIFT_FACTOR * FACE_DISTANCE;
    Vec4!double above = foot * cosh(lift) + normal * sinh(lift);
    Motion!float toAbove = Motion!float.shiftTo(Point!float(above.as!float()));
    return view.slotOf(view.ensureNormalized(Position(view.idAt(current), toAbove)).node);
}

bool isRiseReached(ref const GraphView view, ref const HorosphereRef near) {
    if (view.horospheres.isUpright(near.horosphere)) {
        return columnDistanceOf(near, Point!float.origin()) <= view.columnReach() + NODE_RADIUS;
    } else {
        return fabsf(near.plane.distanceTo(Point!float.origin())) <= RISE_REACH + NODE_RADIUS;
    }
}

void addRisingOver(ref GraphView view, uint slot, uint horosphere, ref Array!HorosphereRef found) {
    foreach (risen; view.risingFrom(view.groundNodeOf(slot, horosphere), horosphere)) {
        if (!found.contains(risen)) {
            HorosphereRef near = view.inheritedRefOf(risen, slot);
            if (view.isRiseReached(near)) {
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
                return near.across(link.side, view.horospheres);
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
            foreach (index; 0 .. CORNER_COUNT) {
                Corner corner = cast(Corner) index;
                if (sideAxis(corner, label) < 3) {
                    Rise rise = view.riseAt(face, corner, horosphere);
                    if (rise.kind != NO_RISE && (ring[].containsHorosphere(face) || view.horospheres.isUprightKind(rise.kind))) {
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
    if (view.horospheres.kinds.ptr[rise.kind - 1].form == HorosphereForm.sunken) {
        return view.horospheres.tagOf(horosphere) == view.horospheres.kinds.ptr[rise.kind - 1].under;
    } else {
        uint foot = view.airSideNode(face, corner, view.horospheres.labelOf(horosphere));
        if (view.horospheres.isUprightKind(rise.kind)) {
            return view.isColumnClearOfAncestors(foot, corner, horosphere);
        } else {
            return view.isClearOfAncestors(foot, corner, horosphere, rise.edges);
        }
    }
}

bool isColumnClearOfAncestors(ref GraphView view, uint face, Corner corner, uint horosphere) {
    Vec4!float[2] line = riseLineOver(corner, view.horospheres.labelOf(horosphere), view.edgeOf());
    float separation = CLEARANCE_EDGES * view.edgeOf();
    uint ancestor = horosphere;
    while (ancestor != ROOT) {
        ancestor = view.horospheres.horosphere(ancestor).parent;
        if (!isRayApart(line[0], line[1], view.planeOfHorosphereIn(ancestor, face), separation)) {
            return false;
        }
    }
    return true;
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
    while (ancestor != ROOT) {
        ancestor = view.horospheres.horosphere(ancestor).parent;
        if (!isApart(candidate, view.planeOfHorosphereIn(ancestor, face), separation)) {
            return false;
        }
    }
    return true;
}

uint airSideNode(ref GraphView view, uint node, Corner corner, Face label) {
    uint slot = node;
    uint crossings = 0;
    Maybe!ParentEntry lower = parentOnCorner(view.parents(slot), corner);
    while (lower.exists) {
        if (lower.value.side == label) {
            crossings += 1;
        }
        slot = lower.value.slot;
        lower = parentOnCorner(view.parents(slot), corner);
    }
    if (crossings % 2 == 1) {
        slot = view.ensureNeighborSlot(slot, label);
    }
    return slot;
}

Horosphere risenHorosphere(ref Graph graph, uint face, Corner corner, uint parent, Rise rise) {
    Face parentLabel = graph.horospheres.labelOf(parent);
    if (graph.horospheres.isUprightKind(rise.kind)) {
        uint foot = graph.view.airSideNode(face, corner, parentLabel);
        Plane[2] column;
        uint count = 0;
        foreach (side; corner.faces) {
            if (side != parentLabel) {
                column[count] = Plane.ofFace(side);
                count += 1;
            }
        }
        return Horosphere(graph.view.planeOfHorosphereIn(parent, foot), column, groundSite(foot, corner, parentLabel), CornerKey.init, 0, parent, foot, 0, 0, 0, 0, 0, parentLabel, cast(ubyte)(rise.kind - 1), rise.edges, HorosphereStage.open);
    } else {
        SiteFrame tower = graph.view.turned(groundSite(face, corner, parentLabel), Turn.pitchUp);
        SiteFrame top = graph.view.atLevel(forwarded(tower, rise.edges), 0);
        Face label = top.zSide();
        uint foot = graph.view.airSideNode(top.node, top.corner, label);
        return Horosphere(-Plane.ofFace(label), [Plane.init, Plane.init], groundSite(foot, top.corner, label), CornerKey.init, 0, parent, foot, 0, 0, 0, 0, 0, label, cast(ubyte)(rise.kind - 1), rise.edges, HorosphereStage.open);
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
    return horosphere.stage != HorosphereStage.free && horosphere.users == 0 && horosphere.tiles == 0 && graph.horospheres.forced.find(horosphere.key) is null;
}

void releaseIdleHorospheres(ref Graph graph) {
    uint released = 0;
    foreach (index; 0 .. graph.horospheres.horospheres.length) {
        uint idle = cast(uint) index + 1;
        while (idle != ROOT && graph.isIdle(graph.horospheres.horosphere(idle))) {
            uint parent = graph.horospheres.horosphere(idle).parent;
            graph.releaseHorosphere(idle);
            released += 1;
            idle = parent;
        }
    }
    if (released > 0) {
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
    foreach (neighbor; graph.view.neighborsOf(ground)) {
        if (graph.horospheres.forced.find(graph.view.cornerKeyOf(graph.view.siteOrigin(neighbor).key)) !is null) {
            return false;
        }
    }
    ClaimKey key = graph.view.siteOrigin(ground).key;
    graph.horospheres.forced.insert(graph.view.cornerKeyOf(key), rise);
    graph.reference(key.slot);
    return true;
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

float heightAbove(float relief, float altitude, Fill fill) {
    if (fill == Fill.terrain) {
        return altitude - relief;
    } else {
        return altitude;
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

bool isAlongColumn(ref const Horospheres horospheres, ref const HorosphereRef near, Point!float point) {
    if (!horospheres.isUpright(near.horosphere)) {
        return false;
    } else {
        float height = near.plane.distanceTo(point);
        if (horospheres.isSunken(near.horosphere)) {
            height = -height;
        }
        return height > 0 && columnDistanceOf(near, point) <= COLUMN_GRAVITY_REACH;
    }
}

float[3] columnUp(ref const HorosphereRef near, Motion!float local) {
    float[3] across = near.column[0].upAt(local).cross(near.column[1].upAt(local));
    float[3] up = across.scaled(1.0f / across.magnitude);
    if (up.dot(near.plane.upAt(local)) < 0) {
        return up.negated;
    } else {
        return up;
    }
}

Gravity gravityAt(ref const Graph graph, Position position) {
    uint slot = graph.slotOf(position.node);
    assert(graph.isGravityKnown(slot));
    Grounds grounds = graph.groundsIn(slot);
    float sign = graph.horospheres.gravitySign();
    if (grounds.count == 1) {
        float[3] up = grounds.items[0].surface.upAt(position.local);
        Point!float point = position.local * Point!float.origin();
        foreach (ref near; graph.horospheres.horospheresAt(slot)) {
            if (graph.horospheres.isAlongColumn(near, point)) {
                up = columnUp(near, position.local);
            }
        }
        return Gravity(up.scaled(sign), 1.0f);
    } else {
        Point!float point = position.local * Point!float.origin();
        float relief = graph.loadedClimateAt(slot, point).relief;
        float[MAX_GROUNDS] heights = void;
        float[3][MAX_GROUNDS] ups = void;
        foreach (index, ground; grounds.items[0 .. grounds.count]) {
            heights[index] = sign * heightAbove(relief, ground.surface.distanceTo(point), ground.fill);
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
    float own = heightAbove(relief, near.plane.distanceTo(center), view.horospheres.fillOf(near.horosphere));
    float other = heightAbove(relief, view.planeOfHorosphereIn(parent, slot).distanceTo(center), view.horospheres.fillOf(parent));
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
    const(HorosphereRef)[] nearby = graph.view.ensureHorospheresAt(slot);
    if (isInBand(state.surface, graph.horospheres.fillOf(ROOT), relief)) {
        return true;
    }
    foreach (near; nearby) {
        if (graph.horospheres.isUpright(near.horosphere) || isInBand(near.plane, graph.horospheres.fillOf(near.horosphere), relief)) {
            return true;
        }
    }
    return graph.ensureStructureAt(slot);
}

float horosphereHeightAt(ref GraphView view, uint horosphere, Position position) {
    uint slot = view.slotOf(position.node);
    Point!float point = position.local * Point!float.origin();
    float relief = view.climateAt(slot, point).relief;
    return heightAbove(relief, view.planeOfHorosphereIn(horosphere, slot).distanceTo(point), view.horospheres.fillOf(horosphere));
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
    if (view.horospheres.isSunken(horosphere)) {
        return RiseMeasure.init;
    } else if (view.horospheres.isUpright(horosphere)) {
        int reach = COLUMN_GROUND_EDGES * edgeCells(view.layout.dimension);
        return RiseMeasure(view.groundAlong(view.turned(measured.foot, Turn.pitchUp), measured.parent, reach), 0, 0);
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
    stored.stage = HorosphereStage.measured;
}

ref const(Horosphere) measuredHorosphere(ref Graph graph, uint horosphere) {
    if (!graph.horospheres.horosphere(horosphere).isMeasured) {
        graph.storeMeasure(horosphere, graph.view.measureOf(horosphere));
    }
    return graph.horospheres.horosphere(horosphere);
}

int lowestSegment(ref GraphView view, uint horosphere) {
    const(Horosphere)* found = &view.horospheres.horosphere(horosphere);
    int ground = found.ground;
    if (!found.isMeasured) {
        ground = view.measureOf(horosphere).ground;
    }
    return lowerOf(0, floorDivision(ground, edgeCells(view.layout.dimension)) - 1);
}

int[2] segmentsNear(ref GraphView view, ref const HorosphereRef near) {
    float edge = view.edgeOf();
    float height = near.plane.distanceTo(Point!float.origin());
    int low = cast(int) floorf((height - NODE_RADIUS) / edge) - 2;
    int high = cast(int) floorf((height + NODE_RADIUS) / edge) + 1;
    if (view.horospheres.isSunken(near.horosphere)) {
        return [low, lowerOf(0, high)];
    } else {
        return [higherOf(view.lowestSegment(near.horosphere), low), high];
    }
}

SiteFrame columnSiteOf(ref Graph graph, SiteFrame site) {
    SiteFrame at = graph.view.atLevel(site, 0);
    return graph.view.turned(groundSite(graph.view.airSideNode(at.node, at.corner, at.ySide), at.corner, at.ySide), Turn.pitchUp);
}

SiteFrame segmentSite(ref GraphView view, uint horosphere, int segment) {
    const(Horosphere)* found = &view.horospheres.horosphere(horosphere);
    return view.atLevel(forwarded(view.turned(found.foot, Turn.pitchUp), segment), 0);
}

