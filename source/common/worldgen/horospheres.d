module common.worldgen.horospheres;

import core.math : sqrt;
import core.stdc.math : acoshf, cosh, coshf, expf, fabs, fabsf, floorf, log, sinh, sinhf, sqrtf;
import core.stdc.string : memcpy;
import base.array : Array;
import base.flags : Readiness;
import base.hashmap : HashMap, TABLE_MULTIPLIER;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : clamped, higherOf, lowerOf;
import base.slab : Run, RunPool, Slab;
import base.splitmix : unitOf;
import base.vector3 : Vec3, cross, dot, magnitude, negated, plus, scaled;
import common.graph : Graph, NodeId, ParentEntry, ParentList;
import common.position : Position;
import common.traversal : MIRRORED_ORIGINS, isListed;
import common.view : GraphView, SlotCorner;
import common.worldgen.blueprint : floorDivision;
import common.worldgen.climate : Climate, CubeClimate, NodeClimate, RELIEF_BOUND, RELIEF_SLACK;
import common.worldgen.generation : NodeState;
import common.worldgen.plane : Plane, PlaneMeasure, logCosh;
import common.worldgen.structure : ClaimKey, ColumnSpot, GROUND_RING, SiteFrame, columnPoint, edgeCells, edgeLength, ensureGroundRing, ensureSiteHash, ensureSiteOrigin, forwarded, groundSite, moveToLevel, parentOnCorner, pathBetween, rootedCorner, sideAxis, sitePlacement, turnSite;
import geometry.honeycomb : CORNER_COUNT, CUBE_RADIUS, Corner, FACE_COUNT, FACE_DISTANCE, Face, NODE_RADIUS, across, cornerToNode, cubeScale, faces, mirror, nodeToCorner;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : HorosphereForm, KindTag, Look, SitePart, Span, Turn;

enum HorosphereId ROOT = HorosphereId.init;
enum uint MAX_GROUNDS = 4;
enum uint MOST_NEAR_RINGS = GROUND_RING * GROUND_RING;
enum float RISE_REACH = 7.0f;
enum float GROUND_REACH = 4.5f;
enum float GRAVITY_REACH = GROUND_REACH - NODE_RADIUS;
enum float GRAVITY_FADE = 0.7f;
enum float LEAST_PULL = 1e-4f;
enum float OPPOSED_FROM = 0.88f;
enum float OPPOSED_FULLY = 0.95f;
enum float OPPOSED_WEIGHT = 0.1f;
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
enum float COLUMN_GRAVITY_FULL = 0.55f;
enum float COLUMN_GRAVITY_RISE = 0.3f;
enum float FLAT_CORE = 0.6f;
enum float FLAT_EDGE = 1.5f;
enum uint MOST_FLAT_LINES = 4;

enum Fill : ubyte {
    none,
    flat,
    terrain,
}

struct HorosphereId {
    uint bits;

    static HorosphereId ofIndex(size_t index) {
        return HorosphereId(cast(uint) index + 1);
    }

    size_t index() const {
        assert(bits != 0);
        return bits - 1;
    }
}

struct HorosphereKind {
    double odds;
    HorosphereForm form;
    uint tag;
    Look look;
    uint under;
}

struct Rise {
    MaybeIndex!ubyte kind;
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

struct EdgeLine {
    Plane first;
    Plane second;

    EdgeLine carriedAlong(const(Face)[] path) const {
        return EdgeLine(first.carriedAlong(path), second.carriedAlong(path));
    }
}

struct Horosphere {
    Plane plane;
    EdgeLine column;
    SiteFrame foot;
    CornerKey key;
    uint keySlot;
    HorosphereId parent;
    uint footNode;
    uint users;
    uint tiles;
    int ground;
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
    EdgeLine column;
    HorosphereId horosphere;

    HorosphereRef across(Face side) const {
        Face[1] path = [side];
        return HorosphereRef(plane.carriedAlong(path[]), column.carriedAlong(path[]), horosphere);
    }
}

bool contains(ref const Array!HorosphereRef found, HorosphereId horosphere) {
    uint index = 0;
    while (index < found.length && found.ptr[index].horosphere != horosphere) {
        index += 1;
    }
    return index < found.length;
}

float lineDistanceOf(ref const EdgeLine line, Point!float point) {
    float first = sinhf(line.first.distanceTo(point));
    float second = sinhf(line.second.distanceTo(point));
    return acoshf(sqrtf(1 + first * first + second * second));
}

float columnDistanceOf(ref const HorosphereRef near, Point!float point) {
    return lineDistanceOf(near.column, point);
}

float smoothRamp(float value, float low, float high) {
    float share = clamped((value - low) / (high - low), 0.0f, 1.0f);
    return share * share * (3 - 2 * share);
}

float reliefShareAway(float distance) {
    return smoothRamp(distance, FLAT_CORE, FLAT_EDGE);
}

struct FlatLines {
    EdgeLine[MOST_FLAT_LINES] lines;
    uint count;

    float reliefShareAt(Point!float point) const {
        float share = 1;
        foreach (ref line; lines[0 .. count]) {
            share = lowerOf(share, reliefShareAway(lineDistanceOf(line, point)));
        }
        return share;
    }
}

FlatLines flatLinesNear(ref const Horospheres horospheres, const(HorosphereRef)[] near, Point!float center) {
    FlatLines found;
    foreach (ref line; near) {
        if (found.count < MOST_FLAT_LINES && !horospheres.isUpright(line.horosphere) && columnDistanceOf(line, center) <= FLAT_EDGE + CUBE_RADIUS) {
            found.lines[found.count] = line.column;
            found.count += 1;
        }
    }
    return found;
}

float reliefShareAmong(ref const Horospheres horospheres, const(HorosphereRef)[] near, Point!float point) {
    float share = 1;
    foreach (ref line; near) {
        if (!horospheres.isUpright(line.horosphere)) {
            share = lowerOf(share, reliefShareAway(columnDistanceOf(line, point)));
        }
    }
    return share;
}

struct Ground {
    Plane surface;
    Fill fill;
    HorosphereId horosphere;
}

struct Grounds {
    Ground[MAX_GROUNDS] items;
    uint count;

    uint farthestRisen() const {
        uint farthest = 1;
        foreach (index; 2 .. count) {
            if (items[index].surface.distanceTo(Point!float.origin()) > items[farthest].surface.distanceTo(Point!float.origin())) {
                farthest = index;
            }
        }
        return farthest;
    }
}

struct Gravity {
    Vec3!float up;
    float strength;
}

struct ChunkPoint {
    Vec3!float coords;
    Corner corner;
}

struct GroundKey {
    NodeId ground;
    HorosphereId horosphere;

    size_t toHash() const {
        return ground.toHash() ^ horosphere.bits;
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
        return node.toHash() ^ (cast(size_t) corner * TABLE_MULTIPLIER);
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
    Array!HorosphereId freeHorospheres;
    Slab!NodeHorospheres nodes;
    Slab!NodeRises rises;
    RunPool!HorosphereRef refs;
    HashMap!(CornerKey, Rise) forced;
    HashMap!(CornerKey, HorosphereId) horosphereOf;
    HashMap!(GroundKey, RisingList) risingFrom;
    Array!HorosphereId rising;
    Fill rootFill;
    MaybeIndex!ubyte rootKind;
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

    ref const(Horosphere) horosphere(HorosphereId id) const {
        return horospheres.ptr[id.index];
    }

    Face labelOf(HorosphereId id) const {
        if (id == ROOT) {
            return Face.first;
        } else {
            return horosphere(id).label;
        }
    }

    MaybeIndex!ubyte kindOf(HorosphereId id) const {
        if (id == ROOT) {
            return rootKind;
        } else {
            return MaybeIndex!ubyte.of(horosphere(id).kind);
        }
    }

    KindTag tagOf(HorosphereId id) const {
        MaybeIndex!ubyte kind = kindOf(id);
        if (kind.exists) {
            return KindTag.of(kinds.ptr[kind.value].tag);
        } else {
            return KindTag.init;
        }
    }

    bool isUpright(HorosphereId id) const {
        return id != ROOT && isUprightKind(horosphere(id).kind);
    }

    bool isUprightKind(ubyte kind) const {
        HorosphereForm form = kinds.ptr[kind].form;
        return form == HorosphereForm.upright || form == HorosphereForm.sunken;
    }

    bool isSunken(HorosphereId id) const {
        return id != ROOT && kinds.ptr[horosphere(id).kind].form == HorosphereForm.sunken;
    }

    Fill fillOf(HorosphereId id) const {
        MaybeIndex!ubyte kind = kindOf(id);
        if (!kind.exists) {
            return rootFill;
        } else if (kinds.ptr[kind.value].form == HorosphereForm.terrain) {
            return Fill.terrain;
        } else if (kinds.ptr[kind.value].form == HorosphereForm.solid) {
            return Fill.flat;
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
            horospheres.ptr[near.horosphere.index].users += 1;
        }
        *nodes.at(slot) = NodeHorospheres(run, Readiness.ready);
    }

    void forget(uint slot) {
        foreach (near; horospheresAt(slot)) {
            horospheres.ptr[near.horosphere.index].users -= 1;
        }
        refs.release(nodes.at(slot).run);
        *nodes.at(slot) = NodeHorospheres.init;
        *rises.at(slot) = NodeRises.init;
    }

    Maybe!(const(HorosphereId)[]) knownRising(GroundKey key) const {
        const(RisingList)* known = risingFrom.find(key);
        if (known is null) {
            return Maybe!(const(HorosphereId)[]).init;
        } else {
            return Maybe!(const(HorosphereId)[]).of(rising.ptr[known.start .. known.start + known.count]);
        }
    }

    const(HorosphereId)[] storeRising(GroundKey key, const(HorosphereId)[] found) {
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
            return Rise(MaybeIndex!ubyte.of(cast(ubyte) index), cast(ubyte)(LOWEST_RISE_EDGES + hash % RISE_EDGE_CHOICES));
        } else {
            return Rise.init;
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
        if (!target.horospheres.knownRising(key).exists) {
            target.horospheres.storeRising(key, view.knownRising(key).value);
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
        target.view.ensureHorosphereOver(face, want.corner, want.parent);
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

bool isWithinPlaneReach(ref const GraphView view, ref const HorosphereRef near, float planeReach) {
    if (view.horospheres.isUpright(near.horosphere)) {
        return columnDistanceOf(near, Point!float.origin()) <= view.columnReach() + NODE_RADIUS;
    } else {
        return near.plane.distanceTo(Point!float.origin()) <= planeReach + NODE_RADIUS;
    }
}

bool isWithinRisingReach(Plane plane) {
    return fabsf(plane.distanceTo(Point!float.origin())) <= RISE_REACH + NODE_RADIUS;
}

void discoverHorospheres(ref GraphView view, uint slot, ref Array!HorosphereRef found) {
    ParentList parents = view.parents(slot);
    foreach (link; parents.links[0 .. parents.count]) {
        foreach (near; view.ensureHorospheresAt(link.slot)) {
            if (!found.contains(near.horosphere)) {
                HorosphereRef moved = near.across(link.side);
                if (view.isWithinPlaneReach(moved, GROUND_REACH)) {
                    found.append(moved);
                }
            }
        }
    }
    view.addRisingOver(slot, ROOT, found);
    size_t index = 0;
    while (index < found.length) {
        HorosphereId over = found.ptr[index].horosphere;
        if (!view.horospheres.isUpright(over) && isWithinRisingReach(found.ptr[index].plane)) {
            view.addRisingOver(slot, over, found);
        }
        index += 1;
    }
}

uint ensureGroundNode(ref GraphView view, uint slot, HorosphereId horosphere) {
    uint current = slot;
    Vec4!double center = Vec4!double.origin();
    Plane carried = view.ensurePlaneIn(horosphere, current);
    float altitude = fabsf(carried.distanceTo(Point!float.origin()));
    while (altitude > DESCENT_ALTITUDE) {
        Maybe!Face lowest;
        float lowestAltitude = 0;
        PlaneMeasure measured = carried.measure();
        double[FACE_COUNT] along = void;
        foreach (index; 0 .. FACE_COUNT) {
            along[index] = fabs(measured.normal.minkowski(MIRRORED_ORIGINS[index].as!double()));
        }
        double least = along[0];
        foreach (index; 1 .. FACE_COUNT) {
            least = lowerOf(least, along[index]);
        }
        foreach (index; 0 .. FACE_COUNT) {
            if (along[index] <= least * DESCENT_TIE_SLACK || along[index] * measured.scale < DESCENT_TIE_FLOOR) {
                float candidate = fabsf(measured.distanceTo(Point!float(MIRRORED_ORIGINS[index])));
                if (!lowest.exists || candidate < lowestAltitude) {
                    lowestAltitude = candidate;
                    lowest = Maybe!Face.of(cast(Face) index);
                }
            }
        }
        if (!lowest.exists || !(lowestAltitude < altitude - DESCENT_TOLERANCE)) {
            break;
        }
        current = view.ensureNeighborSlot(current, lowest.value);
        center = mirror(lowest.value).as!double() * center;
        carried = view.ensurePlaneIn(horosphere, current);
        altitude = fabsf(carried.distanceTo(Point!float.origin()));
    }
    Vec4!double normal = carried.scaledNormal.as!double();
    normal = normal * (1.0 / sqrt(normal.minkowski(normal)));
    double along = center.minkowski(normal);
    Vec4!double foot = (center - normal * along) * (1.0 / sqrt(1.0 + along * along));
    float lift = GROUND_LIFT_FACTOR * FACE_DISTANCE;
    Vec4!double above = foot * cosh(lift) + normal * sinh(lift);
    Motion!float toAbove = Motion!float.shiftTo(Point!float(above.as!float()));
    return view.slotOf(view.ensureNormalized(Position(view.idAt(current), toAbove)).node).value;
}

void addRisingOver(ref GraphView view, uint slot, HorosphereId horosphere, ref Array!HorosphereRef found) {
    foreach (risen; view.ensureRising(view.ensureGroundNode(slot, horosphere), horosphere)) {
        if (!found.contains(risen)) {
            HorosphereRef near = view.inheritedRefOf(risen, slot);
            if (view.isWithinPlaneReach(near, RISE_REACH)) {
                found.append(near);
            }
        }
    }
}

HorosphereRef inheritedRefOf(ref const GraphView view, HorosphereId horosphere, uint slot) {
    ParentList parents = view.parents(slot);
    foreach (link; parents.links[0 .. parents.count]) {
        foreach (near; view.horospheresAt(link.slot)) {
            if (near.horosphere == horosphere) {
                return near.across(link.side);
            }
        }
    }
    return view.refIn(horosphere, slot);
}

HorosphereRef refIn(ref const GraphView view, HorosphereId horosphere, uint slot) {
    const(Horosphere)* found = &view.horospheres.horosphere(horosphere);
    Array!Face path = view.pathBetween(found.footNode, slot);
    HorosphereRef carried = HorosphereRef(found.plane.carriedAlong(path.slice()), found.column.carriedAlong(path.slice()), horosphere);
    path.release();
    return carried;
}

const(HorosphereId)[] ensureRising(ref GraphView view, uint ground, HorosphereId horosphere) {
    GroundKey key = GroundKey(view.idAt(ground), horosphere);
    Maybe!(const(HorosphereId)[]) known = view.knownRising(key);
    if (known.exists) {
        return known.value;
    } else {
        Face label = view.horospheres.labelOf(horosphere);
        uint[GROUND_RING] ring = view.ensureGroundRing(ground, label);
        uint[MOST_NEAR_RINGS] wide = void;
        uint wideCount = 0;
        foreach (face; ring) {
            foreach (outer; view.ensureGroundRing(face, label)) {
                if (!wide[0 .. wideCount].isListed(outer)) {
                    wide[wideCount] = outer;
                    wideCount += 1;
                }
            }
        }
        Array!HorosphereId found;
        foreach (face; wide[0 .. wideCount]) {
            foreach (index; 0 .. CORNER_COUNT) {
                Corner corner = cast(Corner) index;
                if (sideAxis(corner, label) < 3) {
                    Rise rise = view.ensureRise(face, corner, horosphere);
                    if (rise.kind.exists && (ring[].isListed(face) || view.horospheres.isUprightKind(rise.kind.value))) {
                        Maybe!HorosphereId made = view.ensureHorosphereOver(face, corner, horosphere);
                        if (made.exists && !found.slice().isListed(made.value)) {
                            found.append(made.value);
                        }
                    }
                }
            }
        }
        const(HorosphereId)[] stored = view.storeRising(key, found.slice());
        found.release();
        return stored;
    }
}

Rise ensureRise(ref GraphView view, uint face, Corner corner, HorosphereId horosphere) {
    ClaimKey rooted = view.rootedCorner(face, corner).key;
    SlotCorner at = SlotCorner(rooted.slot, corner);
    if (view.hasChoice(at)) {
        return view.choiceAt(at);
    } else {
        Rise rise = view.ensureChosenRise(face, corner, horosphere, view.cornerKeyOf(rooted));
        view.storeChoice(at, rise);
        return rise;
    }
}

Maybe!HorosphereId ensureHorosphereOver(ref GraphView view, uint face, Corner corner, HorosphereId horosphere) {
    Rise rise = view.ensureRise(face, corner, horosphere);
    if (rise.kind.exists) {
        return view.ensureHorosphere(view.rootedCorner(face, corner).key, face, corner, horosphere, rise);
    } else {
        return Maybe!HorosphereId.init;
    }
}

SiteFrame[GROUND_EDGES] ensureNeighbors(ref GraphView view, SiteFrame site) {
    SiteFrame[GROUND_EDGES] neighbors = void;
    SiteFrame heading = site;
    foreach (edge; 0 .. GROUND_EDGES) {
        neighbors[edge] = forwarded(heading, 1);
        heading = view.turnSite(heading, Turn.right);
    }
    return neighbors;
}

bool probeOutranked(ref GraphView view, SiteFrame neighbor, ulong mine) {
    ulong theirs = view.ensureSiteHash(neighbor, SitePart.vertex);
    CornerKey key = view.cornerKeyOf(view.ensureSiteOrigin(neighbor).key);
    return view.horospheres.forced.find(key) !is null || (view.horospheres.rolled(theirs).kind.exists && theirs > mine);
}

Rise ensureChosenRise(ref GraphView view, uint face, Corner corner, HorosphereId horosphere, CornerKey key) {
    const(Rise)* forcedRise = view.horospheres.forced.find(key);
    if (forcedRise !is null) {
        return *forcedRise;
    } else {
        SiteFrame site = groundSite(face, corner, view.horospheres.labelOf(horosphere));
        ulong mine = view.ensureSiteHash(site, SitePart.vertex);
        Rise rise = view.horospheres.rolled(mine);
        SiteFrame[GROUND_EDGES] neighbors = view.ensureNeighbors(site);
        uint edge = 0;
        bool outranked = !rise.kind.exists;
        while (!outranked && edge < GROUND_EDGES) {
            outranked = view.probeOutranked(neighbors[edge], mine);
            if (!outranked) {
                edge += 1;
            }
        }
        bool clear = false;
        if (edge == GROUND_EDGES) {
            clear = view.probeRiseClear(face, corner, horosphere, rise);
        }
        if (clear) {
            return rise;
        } else {
            return Rise.init;
        }
    }
}

struct RiseLine {
    Vec4!float base;
    Vec4!float along;
}

RiseLine riseLineOver(Corner corner, Face label, float edge) {
    Corner upper = corner.across[sideAxis(corner, label)];
    Vec4!float base = (corner.cornerToNode * Point!float.origin()).v;
    Vec4!float next = (upper.cornerToNode * Point!float.origin()).v;
    return RiseLine(base, (next - base * coshf(edge)) * (1.0f / sinhf(edge)));
}

Plane risenPlaneOver(Corner corner, Face label, ubyte edges, float edge) {
    RiseLine line = riseLineOver(corner, label, edge);
    float rise = edges * edge;
    return Plane.fromNormal(-(line.base * sinhf(rise) + line.along * coshf(rise)));
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

bool probeRiseClear(ref GraphView view, uint face, Corner corner, HorosphereId horosphere, Rise rise) {
    if (view.horospheres.kinds.ptr[rise.kind.value].form == HorosphereForm.sunken) {
        return view.horospheres.tagOf(horosphere) == KindTag.of(view.horospheres.kinds.ptr[rise.kind.value].under);
    } else {
        uint foot = view.ensureAirSideNode(face, corner, view.horospheres.labelOf(horosphere));
        if (view.horospheres.isUprightKind(rise.kind.value)) {
            return view.probeColumnClearOfAncestors(foot, corner, horosphere);
        } else {
            return view.probeClearOfAncestors(foot, corner, horosphere, rise.edges);
        }
    }
}

bool probeColumnClearOfAncestors(ref GraphView view, uint face, Corner corner, HorosphereId horosphere) {
    RiseLine line = riseLineOver(corner, view.horospheres.labelOf(horosphere), view.edgeOf());
    float separation = CLEARANCE_EDGES * view.edgeOf();
    HorosphereId ancestor = horosphere;
    while (ancestor != ROOT) {
        ancestor = view.horospheres.horosphere(ancestor).parent;
        Plane plane = view.ensurePlaneIn(ancestor, face);
        if (!isRayApart(line.base, line.along, plane, separation)) {
            return false;
        }
    }
    return true;
}

Plane ensurePlaneIn(ref GraphView view, HorosphereId horosphere, uint slot) {
    if (horosphere == ROOT) {
        return view.ensureState(slot).surface;
    } else {
        return view.refIn(horosphere, slot).plane;
    }
}

bool isApart(Plane first, Plane second, float separation) {
    double product = first.scaledNormal().minkowski(second.scaledNormal());
    return product < 0 && log(-product) + logCosh(first.height) + logCosh(second.height) >= log(cosh(separation)) - APART_TOLERANCE;
}

bool probeClearOfAncestors(ref GraphView view, uint face, Corner corner, HorosphereId horosphere, ubyte edges) {
    Plane candidate = risenPlaneOver(corner, view.horospheres.labelOf(horosphere), edges, view.edgeOf());
    float separation = CLEARANCE_EDGES * view.edgeOf();
    HorosphereId ancestor = horosphere;
    while (ancestor != ROOT) {
        ancestor = view.horospheres.horosphere(ancestor).parent;
        Plane plane = view.ensurePlaneIn(ancestor, face);
        if (!isApart(candidate, plane, separation)) {
            return false;
        }
    }
    return true;
}

uint ensureAirSideNode(ref GraphView view, uint node, Corner corner, Face label) {
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

EdgeLine edgeLineOver(Corner corner, Face label) {
    Face[2] sides;
    uint count = 0;
    foreach (side; corner.faces) {
        if (side != label) {
            sides[count] = side;
            count += 1;
        }
    }
    return EdgeLine(Plane.ofFace(sides[0]), Plane.ofFace(sides[1]));
}

Horosphere risenHorosphere(ref Graph graph, uint face, Corner corner, HorosphereId parent, Rise rise) {
    Face parentLabel = graph.horospheres.labelOf(parent);
    Horosphere made;
    made.parent = parent;
    made.kind = rise.kind.value;
    made.edges = rise.edges;
    made.stage = HorosphereStage.open;
    if (graph.horospheres.isUprightKind(rise.kind.value)) {
        uint foot = graph.view.ensureAirSideNode(face, corner, parentLabel);
        made.plane = graph.view.ensurePlaneIn(parent, foot);
        made.column = edgeLineOver(corner, parentLabel);
        made.foot = groundSite(foot, corner, parentLabel);
        made.footNode = foot;
        made.label = parentLabel;
    } else {
        SiteFrame tower = graph.view.turnSite(groundSite(face, corner, parentLabel), Turn.pitchUp);
        SiteFrame top = graph.view.moveToLevel(forwarded(tower, rise.edges), 0);
        Face label = top.zSide();
        uint foot = graph.view.ensureAirSideNode(top.node, top.corner, label);
        made.plane = -Plane.ofFace(label);
        made.column = edgeLineOver(top.corner, label);
        made.foot = groundSite(foot, top.corner, label);
        made.footNode = foot;
        made.label = label;
    }
    return made;
}

HorosphereId makeHorosphere(ref Graph graph, ClaimKey rooted, uint face, Corner corner, HorosphereId parent, Rise rise) {
    CornerKey key = graph.view.cornerKeyOf(rooted);
    Horosphere made = graph.risenHorosphere(face, corner, parent, rise);
    made.key = key;
    made.keySlot = rooted.slot;
    HorosphereId id = void;
    if (graph.horospheres.freeHorospheres.length > 0) {
        id = graph.horospheres.freeHorospheres.ptr[graph.horospheres.freeHorospheres.length - 1];
        graph.horospheres.freeHorospheres.length -= 1;
        graph.horospheres.horospheres.ptr[id.index] = made;
    } else {
        id = HorosphereId.ofIndex(graph.horospheres.horospheres.length);
        graph.horospheres.horospheres.append(made);
    }
    graph.horospheres.horosphereOf.insert(key, id);
    graph.reference(made.footNode);
    graph.reference(rooted.slot);
    if (parent != ROOT) {
        graph.horospheres.horospheres.ptr[parent.index].users += 1;
    }
    return id;
}

bool isIdle(ref const Graph graph, ref const Horosphere horosphere) {
    return horosphere.stage != HorosphereStage.free && horosphere.users == 0 && horosphere.tiles == 0 && graph.horospheres.forced.find(horosphere.key) is null;
}

void releaseIdleHorospheres(ref Graph graph) {
    uint released = 0;
    foreach (index; 0 .. graph.horospheres.horospheres.length) {
        HorosphereId idle = HorosphereId.ofIndex(index);
        while (idle != ROOT && graph.isIdle(graph.horospheres.horosphere(idle))) {
            HorosphereId parent = graph.horospheres.horosphere(idle).parent;
            graph.releaseHorosphere(idle);
            released += 1;
            idle = parent;
        }
    }
    if (released > 0) {
        graph.horospheres.forgetRising();
    }
}

void releaseHorosphere(ref Graph graph, HorosphereId id) {
    Horosphere released = graph.horospheres.horosphere(id);
    graph.unreference(released.footNode);
    graph.unreference(released.keySlot);
    graph.horospheres.horosphereOf.remove(released.key);
    if (released.parent != ROOT) {
        graph.horospheres.horospheres.ptr[released.parent.index].users -= 1;
    }
    graph.horospheres.horospheres.ptr[id.index] = Horosphere.init;
    graph.horospheres.freeHorospheres.append(id);
}

bool openHorosphere(ref Graph graph, SiteFrame site, Rise rise) {
    SiteFrame at = graph.view.moveToLevel(site, 0);
    SiteFrame ground = groundSite(at.node, at.corner, at.ySide);
    foreach (neighbor; graph.view.ensureNeighbors(ground)) {
        CornerKey beside = graph.view.cornerKeyOf(graph.view.ensureSiteOrigin(neighbor).key);
        if (graph.horospheres.forced.find(beside) !is null) {
            return false;
        }
    }
    ClaimKey key = graph.view.ensureSiteOrigin(ground).key;
    graph.horospheres.forced.insert(graph.view.cornerKeyOf(key), rise);
    graph.reference(key.slot);
    return true;
}

Grounds ensureGrounds(ref GraphView view, uint slot) {
    Plane surface = view.ensureState(slot).surface;
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
        if (!horospheres.isUpright(found.horosphere) && found.plane.distanceTo(Point!float.origin()) <= GROUND_REACH) {
            Ground ground = Ground(found.plane, horospheres.fillOf(found.horosphere), found.horosphere);
            if (grounds.count < MAX_GROUNDS) {
                grounds.items[grounds.count] = ground;
                grounds.count += 1;
            } else {
                uint farthest = grounds.farthestRisen();
                if (found.plane.distanceTo(Point!float.origin()) < grounds.items[farthest].surface.distanceTo(Point!float.origin())) {
                    grounds.items[farthest] = ground;
                }
            }
        }
    }
    return grounds;
}

ChunkPoint chunkPointOf(Point!float point) {
    ChunkPoint best;
    float leastOutside = 0;
    foreach (index; 0 .. CORNER_COUNT) {
        Corner corner = cast(Corner) index;
        Vec4!float dual = corner.nodeToCorner * point.v;
        Vec3!float coords = void;
        float outside = 0;
        foreach (axis; 0 .. 3) {
            coords[axis] = dual.c[axis] / dual.c[3] * (1 / cubeScale());
            outside = higherOf(-coords[axis], outside);
            outside = higherOf(coords[axis] - 1, outside);
        }
        if (index == 0 || outside < leastOutside) {
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
    uint slot = graph.slotOf(position.node).value;
    graph.ensureState(slot);
    graph.view.ensureHorospheresAt(slot);
    return graph.gravityAt(position);
}

const(Look)* lookOfGround(ref const Graph graph, HorosphereId horosphere) {
    MaybeIndex!ubyte kind = graph.horospheres.kindOf(horosphere);
    if (kind.exists && graph.horospheres.kinds.ptr[kind.value].look.name !is null) {
        return &graph.horospheres.kinds.ptr[kind.value].look;
    } else {
        return &graph.structures.blueprint.look;
    }
}

const(Look)* lookAt(ref const Graph graph, Position position) {
    uint slot = graph.slotOf(position.node).value;
    if (!graph.isGravityKnown(slot)) {
        return &graph.structures.blueprint.look;
    } else {
        Point!float point = position.local * Point!float.origin();
        HorosphereId nearest = ROOT;
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

float columnGravityShare(ref const Horospheres horospheres, ref const HorosphereRef near, Point!float point) {
    if (!horospheres.isUpright(near.horosphere)) {
        return 0;
    } else {
        float height = near.plane.distanceTo(point);
        if (horospheres.isSunken(near.horosphere)) {
            height = -height;
        }
        return smoothRamp(height, 0, COLUMN_GRAVITY_RISE) * (1 - smoothRamp(columnDistanceOf(near, point), COLUMN_GRAVITY_FULL, COLUMN_GRAVITY_REACH));
    }
}

Vec3!float columnUp(ref const HorosphereRef near, Motion!float local) {
    Vec3!float across = near.column.first.upAt(local).cross(near.column.second.upAt(local));
    Vec3!float up = across.scaled(1.0f / across.magnitude);
    if (up.dot(near.plane.upAt(local)) < 0) {
        return up.negated;
    } else {
        return up;
    }
}

Gravity gravityAt(ref const Graph graph, Position position) {
    uint slot = graph.slotOf(position.node).value;
    assert(graph.isGravityKnown(slot));
    Grounds grounds = graph.groundsIn(slot);
    float sign = graph.horospheres.gravitySign();
    Point!float point = position.local * Point!float.origin();
    float[MAX_GROUNDS] weights = [1, 0, 0, 0];
    Gravity field = Gravity(grounds.items[0].surface.upAt(position.local).scaled(sign), 1.0f);
    if (grounds.count > 1) {
        float relief = graph.loadedClimateAt(slot, point).relief;
        float[MAX_GROUNDS] heights = void;
        float[MAX_GROUNDS] shares = void;
        Vec3!float[MAX_GROUNDS] ups = void;
        foreach (index, ground; grounds.items[0 .. grounds.count]) {
            float altitude = ground.surface.distanceTo(point);
            heights[index] = sign * heightAbove(relief, altitude, ground.fill);
            shares[index] = 1 - smoothRamp(altitude, GRAVITY_REACH - GRAVITY_FADE, GRAVITY_REACH);
            ups[index] = ground.surface.upAt(position.local).scaled(sign);
        }
        heights[0] = lowerOf(heights[0], GRAVITY_REACH);
        shares[0] = 1;
        weights = groundWeights(heights[0 .. grounds.count], shares[0 .. grounds.count]);
        field = weightedGravity(weights[0 .. grounds.count], ups[0 .. grounds.count]);
    }
    return graph.bentAlongColumns(field, grounds, weights, position, point);
}

Gravity bentAlongColumns(ref const Graph graph, Gravity field, ref const Grounds grounds, ref const float[MAX_GROUNDS] weights, Position position, Point!float point) {
    Vec3!float pull = field.up.scaled(field.strength);
    Readiness bent = Readiness.pending;
    foreach (ref near; graph.horospheres.horospheresAt(graph.slotOf(position.node).value)) {
        float share = graph.horospheres.columnGravityShare(near, point);
        if (share > 0) {
            HorosphereId parent = graph.horospheres.horosphere(near.horosphere).parent;
            float kept = 1;
            foreach (index; 1 .. grounds.count) {
                if (grounds.items[index].horosphere != parent) {
                    kept -= weights[index];
                }
            }
            float mixed = share * kept;
            pull = pull.scaled(1 - mixed).plus(columnUp(near, position.local).scaled(graph.horospheres.gravitySign() * mixed));
            bent = Readiness.ready;
        }
    }
    if (bent == Readiness.pending) {
        return field;
    } else {
        return gravityOfPull(pull, field.up, pull.magnitude);
    }
}

float[MAX_GROUNDS] groundWeights(const(float)[] heights, const(float)[] shares) {
    Maybe!float lowest;
    foreach (index, height; heights) {
        if (shares[index] > 0 && (!lowest.exists || height < lowest.value)) {
            lowest = Maybe!float.of(height);
        }
    }
    float[MAX_GROUNDS] weights = 0;
    float total = 0;
    foreach (index, height; heights) {
        if (shares[index] > 0) {
            weights[index] = shares[index] * expf(-(height - lowest.value) / GRAVITY_FALLOFF);
            total += weights[index];
        }
    }
    foreach (index; 0 .. heights.length) {
        weights[index] = weights[index] / total;
    }
    return weights;
}

Gravity weightedGravity(const(float)[] weights, const(Vec3!float)[] ups) {
    Vec3!float pull = Vec3!float(0, 0, 0);
    size_t heaviest = 0;
    foreach (index, weight; weights) {
        pull = pull.plus(ups[index].scaled(weight));
        if (weight > weights[heaviest]) {
            heaviest = index;
        }
    }
    float opposed = 0;
    foreach (index, weight; weights) {
        opposed = higherOf(opposed, smoothRamp(weight, 0, OPPOSED_WEIGHT) * smoothRamp(-ups[index].dot(ups[heaviest]), OPPOSED_FROM, OPPOSED_FULLY));
    }
    Vec3!float toward = pull.scaled(1 - opposed).plus(ups[heaviest].scaled(opposed));
    return gravityOfPull(toward, ups[heaviest], higherOf(0.0f, pull.dot(ups[heaviest])));
}

Gravity gravityOfPull(Vec3!float pull, Vec3!float idleUp, float strength) {
    float length = pull.magnitude;
    if (length < LEAST_PULL) {
        return Gravity(idleUp, 0);
    } else {
        return Gravity(pull.scaled(1 / length), strength);
    }
}

Gravity blendedGravity(const(float)[] heights, const(float)[] shares, const(Vec3!float)[] ups) {
    float[MAX_GROUNDS] weights = groundWeights(heights, shares);
    return weightedGravity(weights[0 .. heights.length], ups);
}

bool probePaintedBy(ref GraphView view, uint slot, HorosphereRef near) {
    if (view.horospheres.isUpright(near.horosphere)) {
        return true;
    } else if (!isWithinRisingReach(near.plane)) {
        return false;
    } else {
        bool risen = view.probeRisenSide(slot, near);
        return risen || view.isOnFootLine(slot, near.horosphere);
    }
}

bool probeRisenSide(ref GraphView view, uint slot, HorosphereRef near) {
    Point!float center = Point!float.origin();
    float relief = view.ensureState(slot).climate.climate().relief;
    HorosphereId parent = view.horospheres.horosphere(near.horosphere).parent;
    float own = heightAbove(relief, near.plane.distanceTo(center), view.horospheres.fillOf(near.horosphere));
    float other = heightAbove(relief, view.ensurePlaneIn(parent, slot).distanceTo(center), view.horospheres.fillOf(parent));
    return own - other <= RISEN_SIDE_MARGIN;
}

bool isOnFootLine(ref const GraphView view, uint slot, HorosphereId horosphere) {
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
    Vec4!float corner = (Corner.first.cornerToNode * Point!float.origin()).v;
    Vec4!float next = (Corner.first.across[0].cornerToNode * Point!float.origin()).v;
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

bool probeMayHoldContent(ref Graph graph, uint slot) {
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

float ensureHorosphereHeight(ref GraphView view, HorosphereId horosphere, Position position) {
    uint slot = view.slotOf(position.node).value;
    Point!float point = position.local * Point!float.origin();
    float relief = view.ensureClimate(slot, point).relief;
    return heightAbove(relief, view.ensurePlaneIn(horosphere, slot).distanceTo(point), view.horospheres.fillOf(horosphere));
}

float ensurePlaneHeight(ref GraphView view, HorosphereId horosphere, Position position) {
    return view.ensurePlaneIn(horosphere, view.slotOf(position.node).value).distanceTo(position.local * Point!float.origin());
}

Climate ensureClimate(ref GraphView view, uint slot, Point!float point) {
    ChunkPoint at = chunkPointOf(point);
    Climate here = CubeClimate.ensureAround(view, slot, at.corner).at(at.coords);
    here.relief = here.relief * view.horospheres.reliefShareAmong(view.ensureHorospheresAt(slot), point);
    return here;
}

Climate loadedClimateAt(ref const Graph graph, uint slot, Point!float point) {
    ChunkPoint at = chunkPointOf(point);
    Face[3] sides = at.corner.faces;
    NodeClimate own = graph.stateAt(slot).climate;
    NodeClimate[8] around;
    foreach (crossed; 0 .. 8) {
        MaybeIndex!uint node = MaybeIndex!uint.of(slot);
        foreach (axis; 0 .. 3) {
            if (node.exists && (crossed & (1u << axis)) != 0) {
                node = graph.neighborSlot(node.value, sides[axis]);
            }
        }
        around[crossed] = own;
        if (node.exists && graph.nodeAt(node.value).hasState) {
            around[crossed] = graph.stateAt(node.value).climate;
        }
    }
    Climate here = CubeClimate.fromAround(around).at(at.coords);
    here.relief = here.relief * graph.horospheres.reliefShareAmong(graph.horospheres.horospheresAt(slot), point);
    return here;
}

Position ensureCellOnLine(ref GraphView view, SiteFrame line, int cell) {
    Point!float inSite = sitePlacement(line, view.layout) * columnPoint(view.layout, ColumnSpot(0, 0, cell + 0.5f));
    return view.ensureNormalized(Position(view.idAt(line.node), Motion!float.shiftTo(inSite)));
}

int ensureGroundAlong(ref GraphView view, SiteFrame line, HorosphereId horosphere, int span) {
    int cell = -span;
    bool grounded = false;
    while (cell < span && !grounded) {
        float height = view.ensureHorosphereHeight(horosphere, view.ensureCellOnLine(line, cell));
        grounded = !(height < 0);
        if (!grounded) {
            cell += 1;
        }
    }
    return cell;
}

bool probeRisenNearer(ref GraphView view, SiteFrame line, HorosphereId horosphere, int cell) {
    Position at = view.ensureCellOnLine(line, cell);
    float risen = view.ensurePlaneHeight(horosphere, at);
    float lower = view.ensurePlaneHeight(view.horospheres.horosphere(horosphere).parent, at);
    return risen < lower;
}

int ensureBalanceAlong(ref GraphView view, SiteFrame line, HorosphereId horosphere, int most) {
    int nearer = 0;
    int farther = 1;
    bool closer = farther < most;
    if (closer) {
        closer = view.probeRisenNearer(line, horosphere, farther);
    }
    while (closer) {
        nearer = farther;
        farther = lowerOf(farther * 2, most);
        closer = farther < most;
        if (closer) {
            closer = view.probeRisenNearer(line, horosphere, farther);
        }
    }
    bool nearerAtMost = false;
    if (farther == most) {
        nearerAtMost = view.probeRisenNearer(line, horosphere, most);
    }
    if (nearerAtMost) {
        return most;
    } else {
        while (farther - nearer > 1) {
            int middle = (nearer + farther) / 2;
            bool middleNearer = view.probeRisenNearer(line, horosphere, middle);
            if (middleNearer) {
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
    int balance;
}

RiseMeasure ensureMeasure(ref GraphView view, HorosphereId horosphere) {
    Horosphere measured = view.horospheres.horosphere(horosphere);
    if (view.horospheres.isSunken(horosphere)) {
        return RiseMeasure.init;
    } else if (view.horospheres.isUpright(horosphere)) {
        int reach = COLUMN_GROUND_EDGES * edgeCells(view.layout.dimension);
        return RiseMeasure(view.ensureGroundAlong(view.turnSite(measured.foot, Turn.pitchUp), measured.parent, reach), 0);
    } else {
        int span = measured.edges * edgeCells(view.layout.dimension);
        return RiseMeasure(0, view.ensureBalanceAlong(view.turnSite(measured.foot, Turn.pitchUp), horosphere, span));
    }
}

void storeMeasure(ref Graph graph, HorosphereId horosphere, RiseMeasure measure) {
    Horosphere* stored = &graph.horospheres.horospheres.ptr[horosphere.index];
    stored.ground = measure.ground;
    stored.balance = measure.balance;
    stored.stage = HorosphereStage.measured;
}

ref const(Horosphere) ensureMeasured(ref Graph graph, HorosphereId horosphere) {
    if (!graph.horospheres.horosphere(horosphere).isMeasured) {
        graph.storeMeasure(horosphere, graph.view.ensureMeasure(horosphere));
    }
    return graph.horospheres.horosphere(horosphere);
}

int ensureLowestSegment(ref GraphView view, HorosphereId horosphere) {
    const(Horosphere)* found = &view.horospheres.horosphere(horosphere);
    int ground = found.ground;
    if (!found.isMeasured) {
        ground = view.ensureMeasure(horosphere).ground;
    }
    return lowerOf(0, floorDivision(ground, edgeCells(view.layout.dimension)) - 1);
}

Span ensureSegmentsNear(ref GraphView view, ref const HorosphereRef near) {
    float edge = view.edgeOf();
    float height = near.plane.distanceTo(Point!float.origin());
    int low = cast(int) floorf((height - NODE_RADIUS) / edge) - 2;
    int high = cast(int) floorf((height + NODE_RADIUS) / edge) + 1;
    if (view.horospheres.isSunken(near.horosphere)) {
        return Span(low, lowerOf(0, high));
    } else {
        return Span(higherOf(view.ensureLowestSegment(near.horosphere), low), high);
    }
}

SiteFrame ensureColumnSite(ref Graph graph, SiteFrame site) {
    SiteFrame at = graph.view.moveToLevel(site, 0);
    return graph.view.turnSite(groundSite(graph.view.ensureAirSideNode(at.node, at.corner, at.ySide), at.corner, at.ySide), Turn.pitchUp);
}

SiteFrame ensureSegmentSite(ref GraphView view, HorosphereId horosphere, int segment) {
    const(Horosphere)* found = &view.horospheres.horosphere(horosphere);
    return view.moveToLevel(forwarded(view.turnSite(found.foot, Turn.pitchUp), segment), 0);
}

