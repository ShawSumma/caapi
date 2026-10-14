module common.worldgen.sky;

import core.math : sqrt;
import core.stdc.math : acoshf, cosh, coshf, expf, fabs, fabsf, floorf, log, sinh, sinhf, sqrtf;
import core.stdc.string : memcpy;
import base.array : Array;
import base.hashmap : HashMap;
import base.numbers : higherOf, lowerOf;
import base.slab : Run, RunPool, Slab;
import common.graph : Graph, NO_SLOT, NodeId, ParentList;
import common.position : Position;
import common.traversal : NearbyNode, NearbyScratch;
import common.view : GraphView;
import common.worldgen.blueprint : BlueprintBuilder, CellBox, EVERY_HEIGHT, PaintResult;
import common.worldgen.climate : Climate, CubeClimate, NodeClimate, RELIEF_BOUND, RELIEF_SLACK;
import common.worldgen.generation : ChunkParams, GeneratedVoxels, NodeState, StructureWorld, Worldgen;
import common.worldgen.plane : Plane, logCosh;
import common.worldgen.structure : ClaimKey, ColumnSpot, GROUND_RING, SiteFrame, atLevel, columnPoint, edgeCells, edgeLength, forwarded, groundRing, groundSite, isCanonicalMatch, isSamePoint, pathBetween, rootSite, rootedCorner, sideAxis, siteHash, siteOrigin, sitePlacement, siteToNode, turned;
import geometry.honeycomb : CORNER_COUNT, Corner, FACE_COUNT, FACE_DISTANCE, Face, NODE_RADIUS, across, cornerToNode, cubeScale, faces, mirror, nodeToCorner;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : Material, SitePart, SkyGround, Turn;

enum uint PLANET = 0;
enum ubyte NO_SKY = 0;
enum uint MAX_GROUNDS = 4;
enum float SKY_REACH = 7.0f;
enum float GROUND_REACH = 3.0f;
enum uint GROUND_EDGES = 4;
enum ulong ROLL_SHIFT = 11;
enum double ROLL_SCALE = 1.0 / (1UL << 53);
enum ubyte LOWEST_SKY_EDGES = 2;
enum ubyte SKY_EDGE_CHOICES = 3;
enum float CLEARANCE_EDGES = 2.0f;
enum float GRAVITY_FALLOFF = 0.15f;
enum float CHUNK_COORD_SLACK = 1e-3f;
enum float RELIEF_SPREAD = 0.8f;
enum float SKY_SIDE_MARGIN = 2.0f * NODE_RADIUS + RELIEF_SPREAD;
enum float LINE_TOLERANCE = 0.05f;
enum double APART_TOLERANCE = 1e-3;
enum float GROUND_LIFT_FACTOR = 0.1f;
enum float DESCENT_ALTITUDE = 2.0f;
enum float DESCENT_TOLERANCE = 1e-3f;
enum size_t CORNER_KEY_MULTIPLIER = 0x9E3779B97F4A7C15;
enum ubyte TEST_DIMENSION = 12;
enum float TEST_RADIUS = 3.0f;
enum float TEST_PLANE_TOLERANCE = 1e-2f;
enum int TEST_FAR_EDGES = 3;
enum int TEST_RISE_EDGES = 3;
immutable int[3][3] TEST_PAINTED_CELLS = [
    [5, 6, 19],
    [8, 5, 3],
    [6, 9, 40],
];

struct SkyKind {
    double odds;
    SkyGround ground;
}

struct SkyChoice {
    ubyte kind;
    ubyte edges;
}

struct World {
    Plane plane;
    SiteFrame foot;
    CornerKey key;
    uint keySlot;
    uint parent;
    uint footNode;
    uint users;
    int ground;
    int below;
    int balance;
    Face label;
    ubyte kind;
    ubyte edges;
    bool isMeasured;
    bool isKnown;
    bool isTiled;
}

struct WorldRef {
    Plane plane;
    uint world;
}

bool contains(ref const Array!WorldRef worlds, uint world) {
    uint index = 0;
    while (index < worlds.length && worlds.ptr[index].world != world) {
        index += 1;
    }
    return index < worlds.length;
}

struct Ground {
    Plane surface;
    bool isFlat;
}

struct Grounds {
    Ground[MAX_GROUNDS] items;
    uint count;
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
    uint world;

    size_t toHash() const {
        return ground.toHash() ^ world;
    }
}

struct SkyList {
    uint start;
    uint count;
}

struct CornerKey {
    NodeId node;
    Corner corner;

    size_t toHash() const {
        return node.toHash() ^ (cast(size_t) corner * CORNER_KEY_MULTIPLIER);
    }
}

struct NodeWorlds {
    Run run;
    bool isKnown;
}

struct Skies {
    Array!SkyKind kinds;
    Array!World worlds;
    Array!uint freeWorlds;
    Slab!NodeWorlds nodes;
    RunPool!WorldRef refs;
    HashMap!(CornerKey, SkyChoice) forced;
    HashMap!(CornerKey, SkyChoice) choices;
    HashMap!(CornerKey, uint) worldOf;
    HashMap!(GroundKey, SkyList) risingFrom;
    Array!uint risingSkies;
    bool isPlanetFlat;

    void ensureSlots(uint count) {
        nodes.ensure(count);
    }

    ref const(World) world(uint index) const {
        return worlds.ptr[index - 1];
    }

    Face labelOf(uint index) const {
        return index == PLANET ? Face.f0 : world(index).label;
    }

    bool isFlat(uint index) const {
        return index == PLANET ? isPlanetFlat : kinds.ptr[world(index).kind].ground == SkyGround.flat;
    }

    bool opensSkies(uint index) const {
        return index == PLANET || !isFlat(index);
    }

    bool hasWorldsAt(uint slot) const {
        return nodes.at(slot).isKnown;
    }

    const(WorldRef)[] worldsAt(uint slot) const {
        return refs.slice(nodes.at(slot).run);
    }

    void storeWorlds(uint slot, const(WorldRef)[] found) {
        Run run = refs.reserve(cast(uint) found.length);
        memcpy(refs.slice(run).ptr, found.ptr, found.length * WorldRef.sizeof);
        foreach (near; found) {
            worlds.ptr[near.world - 1].users += 1;
        }
        *nodes.at(slot) = NodeWorlds(run, true);
    }

    void forget(uint slot) {
        foreach (near; worldsAt(slot)) {
            worlds.ptr[near.world - 1].users -= 1;
        }
        refs.release(nodes.at(slot).run);
        *nodes.at(slot) = NodeWorlds.init;
    }

    const(uint)[] knownRising(GroundKey key) const {
        const(SkyList)* known = risingFrom.find(key);
        return known is null ? null : risingSkies.ptr[known.start .. known.start + known.count];
    }

    const(uint)[] storeRising(GroundKey key, const(uint)[] rising) {
        SkyList list = SkyList(cast(uint) risingSkies.length, cast(uint) rising.length);
        risingSkies.appendAll(rising);
        risingFrom.insert(key, list);
        return risingSkies.ptr[list.start .. list.start + list.count];
    }

    void forgetRising() {
        risingFrom.clear();
        risingSkies.clear();
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

    SkyChoice rolled(ulong hash) const {
        double roll = cast(double)(hash >> ROLL_SHIFT) * ROLL_SCALE;
        double below = 0;
        uint index = 0;
        while (index < kinds.length && roll >= below + kinds.ptr[index].odds) {
            below += kinds.ptr[index].odds;
            index += 1;
        }
        if (index < kinds.length) {
            return SkyChoice(cast(ubyte)(index + 1), cast(ubyte)(LOWEST_SKY_EDGES + hash % SKY_EDGE_CHOICES));
        } else {
            return SkyChoice(NO_SKY, 0);
        }
    }

    void release() {
        kinds.release();
        worlds.release();
        freeWorlds.release();
        nodes.release();
        refs.release();
        forced.release();
        choices.release();
        worldOf.release();
        risingFrom.release();
        risingSkies.release();
    }
}

float edgeOf(ref const GraphView view) {
    return edgeLength(view.layout).value;
}

void applyDiscoveries(ref Graph target, ref const GraphView view) {
    foreach (slot; view.storedSlots.slice()) {
        if (!target.skies.hasWorldsAt(slot)) {
            target.skies.storeWorlds(slot, view.worldsAt(slot));
        }
    }
    foreach (key; view.risingKeys.slice()) {
        if (target.skies.knownRising(key) is null) {
            target.skies.storeRising(key, view.knownRising(key));
        }
    }
    foreach (key; view.choiceKeys.slice()) {
        if (target.skies.choices.find(key) is null) {
            target.skies.choices.insert(key, *view.knownChoice(key));
        }
    }
}

bool makeWantedWorlds(ref Graph target, ref GraphView view) {
    foreach (want; view.wanted.slice()) {
        uint face = want.start;
        foreach (side; view.wantedPaths.ptr[want.pathStart .. want.pathStart + want.pathLength]) {
            face = target.ensureNeighborSlot(face, side);
        }
        target.view.skyOver(face, want.corner, want.parent);
    }
    bool isMade = view.wanted.length > 0;
    view.clearWanted();
    return isMade;
}

const(WorldRef)[] ensureWorldsAt(ref GraphView view, uint slot) {
    if (!view.hasWorldsAt(slot)) {
        Array!WorldRef found;
        if (view.skies.isOpen()) {
            view.discoverWorlds(slot, found);
        }
        view.storeWorlds(slot, found.slice());
        found.release();
    }
    return view.worldsAt(slot);
}

void discoverWorlds(ref GraphView view, uint slot, ref Array!WorldRef found) {
    ParentList parents = view.parents(slot);
    foreach (link; parents.links[0 .. parents.count]) {
        foreach (near; view.ensureWorldsAt(link.slot)) {
            Plane plane = near.plane.reflectAcross(link.side);
            if (!found.contains(near.world) && fabsf(plane.distanceTo(Point!float.origin())) <= GROUND_REACH + NODE_RADIUS) {
                found.append(WorldRef(plane, near.world));
            }
        }
    }
    view.addSkiesOver(slot, PLANET, found);
    size_t index = 0;
    while (index < found.length) {
        uint over = found.ptr[index].world;
        if (view.skies.opensSkies(over)) {
            view.addSkiesOver(slot, over, found);
        }
        index += 1;
    }
}

uint worldGroundNodeOf(ref GraphView view, uint slot, uint world) {
    uint current = slot;
    Vec4!double center = Vec4!double.origin();
    Plane carried = view.planeOfWorldIn(world, current);
    float altitude = fabsf(carried.distanceTo(Point!float.origin()));
    bool isDescending = altitude > DESCENT_ALTITUDE;
    while (isDescending) {
        Face lowest = Face.f0;
        float lowestAltitude = float.infinity;
        foreach (index; 0 .. FACE_COUNT) {
            float candidate = fabsf(carried.distanceTo(mirror(cast(Face) index) * Point!float.origin()));
            if (candidate < lowestAltitude) {
                lowestAltitude = candidate;
                lowest = cast(Face) index;
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
    Plane plane = view.planeOfWorldIn(world, current);
    Vec4!double normal = plane.scaledNormal.as!double();
    normal = normal * (1.0 / sqrt(normal.minkowski(normal)));
    double along = center.minkowski(normal);
    Vec4!double foot = (center - normal * along) * (1.0 / sqrt(1.0 + along * along));
    float lift = GROUND_LIFT_FACTOR * FACE_DISTANCE;
    Vec4!double above = foot * cosh(lift) + normal * sinh(lift);
    Motion!float toAbove = Motion!float.shiftTo(Point!float(above.as!float()));
    return view.slotOf(view.ensureNormalized(Position(view.idAt(current), toAbove)).node);
}

bool isWithinSkyReach(Plane plane) {
    return fabsf(plane.distanceTo(Point!float.origin())) <= SKY_REACH + NODE_RADIUS;
}

void addSkiesOver(ref GraphView view, uint slot, uint world, ref Array!WorldRef found) {
    foreach (sky; view.skiesRisingFrom(view.worldGroundNodeOf(slot, world), world)) {
        if (!found.contains(sky)) {
            Plane skyPlane = view.inheritedPlaneOf(sky, slot);
            if (isWithinSkyReach(skyPlane)) {
                found.append(WorldRef(skyPlane, sky));
            }
        }
    }
}

Plane inheritedPlaneOf(ref GraphView view, uint sky, uint slot) {
    ParentList parents = view.parents(slot);
    foreach (link; parents.links[0 .. parents.count]) {
        foreach (near; view.worldsAt(link.slot)) {
            if (near.world == sky) {
                return near.plane.reflectAcross(link.side);
            }
        }
    }
    return view.planeOfWorldIn(sky, slot);
}

const(uint)[] skiesRisingFrom(ref GraphView view, uint ground, uint world) {
    GroundKey key = GroundKey(view.idAt(ground), world);
    const(uint)[] known = view.knownRising(key);
    if (known !is null) {
        return known;
    } else {
        Face label = view.skies.labelOf(world);
        uint[GROUND_RING] ring = view.groundRing(ground, label);
        uint[GROUND_RING * CORNER_COUNT] rising = void;
        uint count = 0;
        foreach (face; ring) {
            foreach (index; 0 .. CORNER_COUNT) {
                Corner corner = cast(Corner) index;
                if (sideAxis(corner, label) < 3) {
                    uint sky = view.skyOver(face, corner, world);
                    if (sky != PLANET && !rising[0 .. count].containsWorld(sky)) {
                        rising[count] = sky;
                        count += 1;
                    }
                }
            }
        }
        return view.storeRising(key, rising[0 .. count]);
    }
}

bool containsWorld(const(uint)[] worlds, uint world) {
    size_t index = 0;
    while (index < worlds.length && worlds[index] != world) {
        index += 1;
    }
    return index < worlds.length;
}

uint skyOver(ref GraphView view, uint face, Corner corner, uint world) {
    ClaimKey rooted = view.rootedCorner(face, corner).key;
    CornerKey key = view.cornerKeyOf(rooted);
    const(SkyChoice)* cached = view.knownChoice(key);
    SkyChoice choice = void;
    if (cached !is null) {
        choice = *cached;
    } else {
        choice = view.chosenSky(face, corner, world, key);
        view.storeChoice(key, choice);
    }
    if (choice.kind == NO_SKY) {
        return PLANET;
    } else {
        return view.ensureWorld(rooted, face, corner, world, choice);
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
    return view.skies.forced.find(view.cornerKeyOf(view.siteOrigin(neighbor).key)) !is null || (view.skies.rolled(theirs).kind != NO_SKY && theirs > mine);
}

SkyChoice chosenSky(ref GraphView view, uint face, Corner corner, uint world, CornerKey key) {
    const(SkyChoice)* forcedChoice = view.skies.forced.find(key);
    if (forcedChoice !is null) {
        return *forcedChoice;
    } else {
        SiteFrame site = groundSite(face, corner, view.skies.labelOf(world));
        ulong mine = view.siteHash(site, SitePart.vertex);
        SkyChoice choice = view.skies.rolled(mine);
        SiteFrame[GROUND_EDGES] neighbors = view.neighborsOf(site);
        uint edge = 0;
        while (choice.kind != NO_SKY && edge < GROUND_EDGES && !view.isOutranked(neighbors[edge], mine)) {
            edge += 1;
        }
        if (edge == GROUND_EDGES && view.isClearOfAncestors(face, corner, world, choice.edges)) {
            return choice;
        } else {
            return SkyChoice(NO_SKY, 0);
        }
    }
}

Plane skyPlaneOver(Corner corner, Face label, ubyte edges, float edge) {
    Corner upper = corner.across[sideAxis(corner, label)];
    Vec4!float base = (corner.cornerToNode * Point!float.origin()).v;
    Vec4!float next = (upper.cornerToNode * Point!float.origin()).v;
    Vec4!float along = (next - base * coshf(edge)) * (1.0f / sinhf(edge));
    float rise = edges * edge;
    return Plane.fromNormal(-(base * sinhf(rise) + along * coshf(rise)));
}

Plane planeOfWorldIn(ref GraphView view, uint world, uint slot) {
    if (world == PLANET) {
        return view.stateAt(slot).surface;
    } else {
        const(World)* found = &view.skies.world(world);
        Array!Face path = view.pathBetween(found.footNode, slot);
        Plane plane = found.plane.carriedAlong(path.slice());
        path.release();
        return plane;
    }
}

bool isApart(Plane first, Plane second, float separation) {
    double product = fabs(first.scaledNormal().minkowski(second.scaledNormal()));
    return product > 0 && log(product) + logCosh(first.height) + logCosh(second.height) >= log(cosh(separation)) - APART_TOLERANCE;
}

bool isClearOfAncestors(ref GraphView view, uint face, Corner corner, uint world, ubyte edges) {
    Plane candidate = skyPlaneOver(corner, view.skies.labelOf(world), edges, view.edgeOf());
    float separation = CLEARANCE_EDGES * view.edgeOf();
    uint ancestor = world;
    bool isClear = true;
    while (isClear && ancestor != PLANET) {
        ancestor = view.skies.world(ancestor).parent;
        isClear = isApart(candidate, view.planeOfWorldIn(ancestor, face), separation);
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

uint makeWorld(ref Graph graph, ClaimKey rooted, uint face, Corner corner, uint parent, SkyChoice choice) {
    CornerKey key = graph.view.cornerKeyOf(rooted);
    SiteFrame tower = graph.view.turned(groundSite(face, corner, graph.skies.labelOf(parent)), Turn.pitchUp);
    SiteFrame top = graph.view.atLevel(forwarded(tower, choice.edges), 0);
    Face label = top.zSide();
    uint foot = graph.airSideNode(top.node, top.corner, label);
    Plane plane = -Plane.ofFace(label);
    World made = World(plane, groundSite(foot, top.corner, label), key, rooted.slot, parent, foot, 0, 0, 0, 0, label, cast(ubyte)(choice.kind - 1), choice.edges, false, true, false);
    uint world = void;
    if (graph.skies.freeWorlds.length > 0) {
        world = graph.skies.freeWorlds.ptr[graph.skies.freeWorlds.length - 1];
        graph.skies.freeWorlds.length -= 1;
        graph.skies.worlds.ptr[world - 1] = made;
    } else {
        graph.skies.worlds.append(made);
        world = cast(uint) graph.skies.worlds.length;
    }
    graph.skies.worldOf.insert(key, world);
    graph.reference(foot);
    graph.reference(rooted.slot);
    if (parent != PLANET) {
        graph.skies.worlds.ptr[parent - 1].users += 1;
    }
    return world;
}

bool isIdle(ref const Graph graph, ref const World world) {
    return world.isKnown && world.users == 0 && !world.isTiled && graph.skies.forced.find(world.key) is null;
}

void releaseIdleWorlds(ref Graph graph) {
    bool isReleased = true;
    while (isReleased) {
        isReleased = false;
        foreach (index; 0 .. graph.skies.worlds.length) {
            if (graph.isIdle(graph.skies.worlds.ptr[index])) {
                graph.releaseWorld(cast(uint) index + 1);
                isReleased = true;
            }
        }
    }
}

void releaseWorld(ref Graph graph, uint index) {
    World world = graph.skies.world(index);
    graph.unreference(world.footNode);
    graph.unreference(world.keySlot);
    graph.skies.worldOf.remove(world.key);
    if (world.parent != PLANET) {
        graph.skies.worlds.ptr[world.parent - 1].users -= 1;
    }
    graph.skies.worlds.ptr[index - 1] = World.init;
    graph.skies.freeWorlds.append(index);
    graph.skies.forgetRising();
}

bool openSky(ref Graph graph, SiteFrame site, SkyChoice choice) {
    SiteFrame at = graph.view.atLevel(site, 0);
    SiteFrame ground = groundSite(at.node, at.corner, at.ySide);
    uint besides = 0;
    foreach (neighbor; graph.view.neighborsOf(ground)) {
        if (graph.skies.forced.find(graph.view.cornerKeyOf(graph.view.siteOrigin(neighbor).key)) !is null) {
            besides += 1;
        }
    }
    if (besides > 0) {
        return false;
    } else {
        ClaimKey key = graph.view.siteOrigin(ground).key;
        graph.skies.forced.insert(graph.view.cornerKeyOf(key), choice);
        graph.reference(key.slot);
        return true;
    }
}

Grounds groundsAt(ref GraphView view, uint slot) {
    Plane surface = view.stateAt(slot).surface;
    return groundsOf(view.skies, surface, view.ensureWorldsAt(slot));
}

Grounds groundsIn(ref const Graph graph, uint slot) {
    return groundsOf(graph.skies, graph.stateAt(slot).surface, graph.skies.worldsAt(slot));
}

Grounds groundsOf(ref const Skies skies, Plane surface, const(WorldRef)[] worlds) {
    Grounds grounds;
    grounds.items[0] = Ground(surface, skies.isFlat(PLANET));
    grounds.count = 1;
    foreach (sky; worlds) {
        if (grounds.count < MAX_GROUNDS && fabsf(sky.plane.distanceTo(Point!float.origin())) <= GROUND_REACH) {
            grounds.items[grounds.count] = Ground(sky.plane, skies.isFlat(sky.world));
            grounds.count += 1;
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
            if (coords[axis] < 0 && -coords[axis] > outside) {
                outside = -coords[axis];
            }
            if (coords[axis] > 1 && coords[axis] - 1 > outside) {
                outside = coords[axis] - 1;
            }
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

Gravity gravityAt(ref const Graph graph, Position position) {
    uint slot = graph.slotOf(position.node);
    Grounds grounds = graph.groundsIn(slot);
    if (grounds.count == 1) {
        return Gravity(grounds.items[0].surface.upAt(position.local), 1.0f);
    } else {
        Point!float point = position.local * Point!float.origin();
        float relief = graph.loadedClimateAt(slot, point).relief;
        float[MAX_GROUNDS] heights = void;
        float[3][MAX_GROUNDS] ups = void;
        foreach (index, ground; grounds.items[0 .. grounds.count]) {
            heights[index] = heightAbove(relief, ground.surface.distanceTo(point), ground.isFlat);
            ups[index] = ground.surface.upAt(position.local);
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
    float strength = along / total;
    if (strength < 0) {
        strength = 0;
    }
    return Gravity(up, strength);
}

bool isPaintedBySky(ref GraphView view, uint slot, WorldRef sky) {
    return view.isOnSkySide(slot, sky) || view.isOnFootLine(slot, sky.world);
}

bool isOnSkySide(ref GraphView view, uint slot, WorldRef sky) {
    Point!float center = Point!float.origin();
    float relief = view.stateAt(slot).climate.climate().relief;
    uint parent = view.skies.world(sky.world).parent;
    float own = heightAbove(relief, sky.plane.distanceTo(center), view.skies.isFlat(sky.world));
    float other = heightAbove(relief, view.planeOfWorldIn(parent, slot).distanceTo(center), view.skies.isFlat(parent));
    return own - other <= SKY_SIDE_MARGIN;
}

// The foot line is where the foot corner's two faces other than the ground's meet, and cosh^2 of the distance to it
// is 1 plus sinh^2 of the distance to each of those planes.
bool isOnFootLine(ref const GraphView view, uint slot, uint sky) {
    const(World)* world = &view.skies.world(sky);
    Array!Face path = view.pathBetween(world.footNode, slot);
    float coshSquared = 1;
    foreach (side; world.foot.corner.faces) {
        if (side != world.label) {
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

bool isInBand(Plane plane, bool isFlat, float relief) {
    float altitude = plane.distanceTo(Point!float.origin());
    float top = 0;
    float bottom = 0;
    if (!isFlat) {
        top = lowerOf(relief + RELIEF_SLACK, RELIEF_BOUND);
        bottom = higherOf(relief - RELIEF_SLACK, -RELIEF_BOUND);
    }
    return altitude - NODE_RADIUS < top && altitude + NODE_RADIUS > bottom;
}

bool mayHoldContent(ref Graph graph, uint slot) {
    NodeState state = *graph.ensureState(slot);
    float relief = state.climate.climate().relief;
    bool holds = graph.ensureStructureAt(slot) || isInBand(state.surface, graph.skies.isFlat(PLANET), relief);
    foreach (sky; graph.view.ensureWorldsAt(slot)) {
        holds = holds || isInBand(sky.plane, graph.skies.isFlat(sky.world), relief);
    }
    return holds;
}

float worldHeightAt(ref GraphView view, uint world, Position position) {
    uint slot = view.slotOf(position.node);
    Point!float point = position.local * Point!float.origin();
    float relief = view.climateAt(slot, point).relief;
    return heightAbove(relief, view.planeOfWorldIn(world, slot).distanceTo(point), view.skies.isFlat(world));
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
        around[crossed] = node != NO_SLOT && graph.nodeAt(node).hasState ? graph.stateAt(node).climate : own;
    }
    return CubeClimate.fromAround(around).at(at.coords);
}

Position cellOnLine(ref GraphView view, SiteFrame line, int cell) {
    Point!float inSite = sitePlacement(line, view.layout) * columnPoint(view.layout, ColumnSpot(0, 0, cell + 0.5f));
    return view.ensureNormalized(Position(view.idAt(line.node), Motion!float.shiftTo(inSite)));
}

int groundAlong(ref GraphView view, SiteFrame line, uint world, int span) {
    int cell = -span;
    while (cell < span && view.worldHeightAt(world, view.cellOnLine(line, cell)) < 0) {
        cell += 1;
    }
    return cell;
}

bool isSkyNearer(ref GraphView view, SiteFrame line, uint sky, int cell) {
    Position at = view.cellOnLine(line, cell);
    return view.worldHeightAt(sky, at) < view.worldHeightAt(view.skies.world(sky).parent, at);
}

int balanceAlong(ref GraphView view, SiteFrame line, uint sky, int most) {
    int nearer = 0;
    int farther = 1;
    while (farther < most && view.isSkyNearer(line, sky, farther)) {
        nearer = farther;
        farther = lowerOf(farther * 2, most);
    }
    if (farther == most && view.isSkyNearer(line, sky, most)) {
        return most;
    } else {
        while (farther - nearer > 1) {
            int middle = (nearer + farther) / 2;
            if (view.isSkyNearer(line, sky, middle)) {
                nearer = middle;
            } else {
                farther = middle;
            }
        }
        return farther;
    }
}

struct SkyMeasure {
    int ground;
    int below;
    int balance;
}

SkyMeasure measureOf(ref GraphView view, uint sky) {
    World world = view.skies.world(sky);
    int span = world.edges * edgeCells(view.layout.dimension);
    SiteFrame up = view.turned(world.foot, Turn.pitchUp);
    SiteFrame down = view.turned(view.turned(forwarded(up, world.edges), Turn.pitchUp), Turn.pitchUp);
    return SkyMeasure(view.groundAlong(up, sky, span), view.groundAlong(down, world.parent, span), view.balanceAlong(up, sky, span));
}

void storeMeasure(ref Graph graph, uint sky, SkyMeasure measure) {
    World* stored = &graph.skies.worlds.ptr[sky - 1];
    stored.ground = measure.ground;
    stored.below = measure.below;
    stored.balance = measure.balance;
    stored.isMeasured = true;
}

ref const(World) measuredWorld(ref Graph graph, uint sky) {
    if (!graph.skies.world(sky).isMeasured) {
        graph.storeMeasure(sky, graph.view.measureOf(sky));
    }
    return graph.skies.world(sky);
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.fromStructure(StructureWorld.fromName("test")));
    graph.skies.kinds.append(SkyKind(0, SkyGround.flat));
    SiteFrame world = rootSite(graph.anchorSlot);
    assert(graph.openSky(world, SkyChoice(1, LOWEST_SKY_EDGES)));
    assert(!graph.openSky(forwarded(world, 1), SkyChoice(1, LOWEST_SKY_EDGES)));
    uint sky = graph.view.skyOver(graph.anchorSlot, world.corner, PLANET);
    assert(sky != PLANET);
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.skies.world(sky).footNode), Motion!float.identity()), TEST_RADIUS);
    foreach (node; nearby) {
        const(WorldRef)[] worlds = graph.view.ensureWorldsAt(node.slot);
        foreach (found; worlds) {
            assert(fabsf(graph.view.planeOfWorldIn(found.world, node.slot).distanceTo(Point!float.origin()) - found.plane.distanceTo(Point!float.origin())) < TEST_PLANE_TOLERANCE);
        }
        bool isNear = fabsf(graph.view.planeOfWorldIn(sky, node.slot).distanceTo(Point!float.origin())) <= GROUND_REACH;
        assert(!isNear || worlds.length == 1);
    }
    GraphView view = GraphView.over(graph);
    SkyMeasure viewed = view.measureOf(sky);
    SkyMeasure measured = graph.view.measureOf(sky);
    assert(!view.isBlocked && viewed == measured);
    view.release();
    World made = graph.skies.world(sky);
    float footAltitude = graph.view.planeOfWorldIn(sky, made.footNode).distanceTo(Point!float.origin());
    float anchorAltitude = graph.ensureState(graph.anchorSlot).surface.distanceTo(Point!float.origin());
    assert(fabsf(footAltitude - anchorAltitude) < TEST_PLANE_TOLERANCE);
    uint[GROUND_RING] ring = graph.view.groundRing(graph.anchorSlot, Face.f0);
    SiteFrame high = graph.view.atLevel(forwarded(graph.view.turned(world, Turn.pitchUp), TEST_RISE_EDGES), 0);
    uint below = graph.view.worldGroundNodeOf(high.node, PLANET);
    uint index = 0;
    while (index < GROUND_RING && ring[index] != below) {
        index += 1;
    }
    assert(index < GROUND_RING);
    assert(graph.view.worldGroundNodeOf(made.footNode, sky) == made.footNode);
    foreach (node; nearby) {
        uint[2] worlds = [PLANET, sky];
        foreach (over; worlds) {
            float ground = graph.view.planeOfWorldIn(over, graph.view.worldGroundNodeOf(node.slot, over)).distanceTo(Point!float.origin());
            assert(fabsf(ground - FACE_DISTANCE) < TEST_PLANE_TOLERANCE);
        }
    }
    assert(graph.view.isOnFootLine(made.footNode, sky));
    assert(!graph.view.isOnFootLine(graph.view.atLevel(forwarded(made.foot, TEST_FAR_EDGES), 0).node, sky));
    SiteFrame quarter = made.foot;
    foreach (_; 0 .. GROUND_EDGES) {
        SiteFrame tower = graph.view.turned(graph.view.turned(quarter, Turn.pitchUp), Turn.rollRight);
        assert(graph.isCanonicalMatch(tower));
        assert(graph.isCanonicalMatch(graph.view.turned(graph.view.turned(graph.view.turned(forwarded(tower, LOWEST_SKY_EDGES), Turn.pitchUp), Turn.pitchUp), Turn.rollRight)));
        quarter = graph.view.turned(quarter, Turn.right);
    }
    SiteFrame skyTower = graph.view.turned(graph.view.turned(made.foot, Turn.pitchUp), Turn.rollRight);
    SiteFrame planetTower = graph.view.turned(graph.view.turned(graph.view.turned(forwarded(skyTower, LOWEST_SKY_EDGES), Turn.pitchUp), Turn.pitchUp), Turn.rollRight);
    float length = LOWEST_SKY_EDGES * edgeCells(graph.layout.dimension);
    foreach (cell; TEST_PAINTED_CELLS) {
        Point!float fromSky = graph.view.siteToNode(skyTower, skyTower.node) * columnPoint(graph.layout, ColumnSpot(cell[0] + 0.5f, cell[1] + 0.5f, cell[2] + 0.5f));
        Point!float fromPlanet = graph.view.siteToNode(planetTower, skyTower.node) * columnPoint(graph.layout, ColumnSpot(cell[1] + 0.5f, cell[0] + 0.5f, length - cell[2] - 0.5f));
        assert(isSamePoint(fromSky, fromPlanet));
    }
    BlueprintBuilder builder = BlueprintBuilder.make(graph);
    foreach (cell; TEST_PAINTED_CELLS) {
        assert(builder.paint(skyTower, CellBox.make(cell[0], cell[0], cell[1], cell[1], cell[2], cell[2]), EVERY_HEIGHT, Material.granite, false) == PaintResult.painted);
    }
    foreach (cell; TEST_PAINTED_CELLS) {
        Point!float center = sitePlacement(skyTower, graph.layout) * columnPoint(graph.layout, ColumnSpot(cell[0] + 0.5f, cell[1] + 0.5f, cell[2] + 0.5f));
        Position at = graph.ensureNormalized(Position(graph.idAt(skyTower.node), Motion!float.shiftTo(center)));
        ChunkPoint inChunk = chunkPointOf(at.local * Point!float.origin());
        int[3] voxel = void;
        foreach (axis; 0 .. 3) {
            voxel[axis] = cast(int) floorf(graph.layout.cubeToGrid(inChunk.coords[axis]));
        }
        assert(graph.ensureBuildingAt(graph.slotOf(at.node)).materialAt(inChunk.corner, voxel, Material.none) == Material.granite);
    }
    builder.release();
    Plane over = skyPlaneOver(world.corner, Face.f0, LOWEST_SKY_EDGES, graph.view.edgeOf());
    Plane stored = graph.view.planeOfWorldIn(sky, graph.anchorSlot);
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
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.makeTerrain());
    graph.skies.kinds.append(SkyKind(0, SkyGround.flat));
    SiteFrame root = rootSite(graph.anchorSlot);
    assert(graph.openSky(root, SkyChoice(1, LOWEST_SKY_EDGES)));
    uint sky = graph.view.skyOver(graph.anchorSlot, root.corner, PLANET);
    assert(sky != PLANET);
    World world = graph.skies.world(sky);
    uint solid = graph.ensureNeighborSlot(world.footNode, world.label);
    GeneratedVoxels generated = ChunkParams.make(graph.view, solid, world.foot.corner).generateVoxels();
    assert(generated.voxels.isUniform() && generated.voxels.at(0) != Material.none);
    generated.voxels.release();
    graph.release();
}
