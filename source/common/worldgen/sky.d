module common.worldgen.sky;

import core.stdc.math : coshf, expf, fabsf;
import common.array : Array;
import common.dodeca : Side, VERTEX_COUNT, Vertex, adjacentVertices, canonicalSides, isAdjacentTo, normal;
import common.graph : Graph, ParentList;
import common.hashmap : HashMap;
import common.math : MIsometry, MPoint;
import common.position : Position;
import common.traversal : NearbyNode, NearbyScratch;
import common.worldgen.generation : NodeState, NodeStateKind, StructureWorld, Worldgen;
import common.worldgen.plane : Plane;
import common.worldgen.structure : ClaimKey, GROUND_RING, SiteFrame, SitePart, Turn, atLevel, edgeLength, forwarded, groundNodeOf, groundRing, groundSite, nodeToNode, rootSite, rootedVertex, sideAxis, siteHash, siteOrigin, turned;

enum uint PLANET = 0;
enum ubyte NO_SKY = 0;
enum uint FOOT_NODES = 4;
enum uint GROUND_EDGES = 4;
enum ulong ROLL_SHIFT = 11;
enum double ROLL_SCALE = 1.0 / (1UL << 53);
enum float HALFWAY_TOLERANCE = 0.25f;
enum float PLANE_PRECISION = 1e-6f;
enum ubyte TEST_DIMENSION = 12;
enum float TEST_RADIUS = 3.5f;

enum SkyGround : ubyte {
    terrain,
    flat,
}

struct SkyKind {
    double odds;
    SkyGround ground;
}

struct Realm {
    ClaimKey vertex;
    ClaimKey halfway;
    uint foot;
    Vertex footVertex;
    ubyte kind;
}

struct Skies {
    Array!SkyKind kinds;
    Array!Realm realms;
    HashMap!(ClaimKey, ubyte) forced;
    HashMap!(ClaimKey, ubyte) choices;
    HashMap!(ClaimKey, uint) realmOf;

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

    ubyte rolledKind(ulong hash) const {
        double roll = cast(double)(hash >> ROLL_SHIFT) * ROLL_SCALE;
        double below = 0;
        uint index = 0;
        while (index < kinds.length && roll >= below + kinds.ptr[index].odds) {
            below += kinds.ptr[index].odds;
            index += 1;
        }
        if (index < kinds.length) {
            return cast(ubyte)(index + 1);
        } else {
            return NO_SKY;
        }
    }

    void release() {
        kinds.release();
        realms.release();
        forced.release();
        choices.release();
        realmOf.release();
    }
}

ref const(Realm) realmAt(ref const Graph graph, uint realm) {
    return graph.skies.realms.ptr[realm - 1];
}

bool hasPlaneGroundAt(ref const Graph graph, ref const NodeState state) {
    if (state.realm == PLANET) {
        return graph.worldgen.hasPlaneGround();
    } else {
        return graph.skies.kinds.ptr[graph.realmAt(state.realm).kind].ground == SkyGround.flat;
    }
}

Side halfwaySide(Vertex vertex) {
    Vertex upper = vertex.adjacentVertices[sideAxis(vertex, Side.a)];
    uint axis = 0;
    while (axis < 3 && sideAxis(vertex, upper.canonicalSides[axis]) < 3) {
        axis += 1;
    }
    assert(axis < 3);
    return upper.canonicalSides[axis];
}

ClaimKey planeKey(ref const Graph graph, uint node, Side side) {
    uint current = node;
    bool isLowest = false;
    while (!isLowest) {
        ParentList parents = graph.parents(current);
        uint index = 0;
        while (index < parents.count && !parents.links[index].side.isAdjacentTo(side)) {
            index += 1;
        }
        isLowest = index == parents.count;
        if (!isLowest) {
            current = parents.links[index].slot;
        }
    }
    return ClaimKey(current, side, SitePart.face);
}

ulong vertexHash(ref Graph graph, SiteFrame site) {
    return graph.siteHash(site, SitePart.vertex);
}

SiteFrame[GROUND_EDGES] neighborsOf(ref Graph graph, SiteFrame site) {
    SiteFrame[GROUND_EDGES] neighbors = void;
    SiteFrame heading = site;
    foreach (edge; 0 .. GROUND_EDGES) {
        neighbors[edge] = forwarded(heading, 1);
        heading = graph.turned(heading, Turn.right);
    }
    return neighbors;
}

bool isBesideForced(ref Graph graph, SiteFrame site) {
    uint count = 0;
    foreach (neighbor; graph.neighborsOf(site)) {
        if (graph.skies.forced.find(graph.siteOrigin(neighbor).key) !is null) {
            count += 1;
        }
    }
    return count > 0;
}

bool isOutranked(ref Graph graph, SiteFrame neighbor, ulong mine) {
    ulong theirs = graph.vertexHash(neighbor);
    return graph.skies.forced.find(graph.siteOrigin(neighbor).key) !is null || (graph.skies.rolledKind(theirs) != NO_SKY && theirs > mine);
}

ubyte chosenSky(ref Graph graph, SiteFrame site, ClaimKey key) {
    const(ubyte)* forcedKind = graph.skies.forced.find(key);
    if (forcedKind !is null) {
        return *forcedKind;
    } else {
        ulong mine = graph.vertexHash(site);
        ubyte kind = graph.skies.rolledKind(mine);
        SiteFrame[GROUND_EDGES] neighbors = graph.neighborsOf(site);
        uint edge = 0;
        while (kind != NO_SKY && edge < GROUND_EDGES && !graph.isOutranked(neighbors[edge], mine)) {
            edge += 1;
        }
        if (edge == GROUND_EDGES) {
            return kind;
        } else {
            return NO_SKY;
        }
    }
}

ubyte skyAt(ref Graph graph, uint node, Vertex vertex, ClaimKey key) {
    const(ubyte)* cached = graph.skies.choices.find(key);
    if (cached !is null) {
        return *cached;
    } else {
        ubyte choice = graph.chosenSky(groundSite(node, vertex), key);
        graph.skies.choices.insert(key, choice);
        return choice;
    }
}

uint ensureRealm(ref Graph graph, ClaimKey key, uint node, Vertex vertex, ubyte kind) {
    const(uint)* known = graph.skies.realmOf.find(key);
    if (known !is null) {
        return *known;
    } else {
        Side halfway = halfwaySide(vertex);
        graph.skies.realms.append(Realm(key, graph.planeKey(node, halfway), graph.ensureNeighborSlot(node, halfway), vertex, cast(ubyte)(kind - 1)));
        uint realm = cast(uint) graph.skies.realms.length;
        graph.skies.realmOf.insert(key, realm);
        return realm;
    }
}

uint realmOver(ref Graph graph, uint node, Vertex vertex) {
    ClaimKey key = graph.rootedVertex(node, vertex).key;
    ubyte kind = graph.skyAt(node, vertex, key);
    if (kind == NO_SKY) {
        return PLANET;
    } else {
        return graph.ensureRealm(key, node, vertex, kind);
    }
}

bool isOnFace(Vertex vertex, Side side) {
    return sideAxis(vertex, side) < 3;
}

bool mayBeHalfway(Plane ground, Side side, float coshEdge) {
    float scale = expf(ground.exponent);
    float product = fabsf(side.normal.vec.mip(ground.scaledNormal)) * scale;
    float error = fabsf(ground.scaledNormal.data[3]) * scale * PLANE_PRECISION;
    return error >= HALFWAY_TOLERANCE || fabsf(product - coshEdge) < HALFWAY_TOLERANCE;
}

uint realmAcross(ref Graph graph, uint parent, Side side) {
    ClaimKey crossed = graph.planeKey(parent, side);
    uint[GROUND_RING] ring = graph.groundRing(graph.groundNodeOf(parent));
    uint found = PLANET;
    foreach (ground; ring) {
        foreach (index; 0 .. VERTEX_COUNT) {
            Vertex vertex = cast(Vertex) index;
            if (vertex.isOnFace(Side.a)) {
                uint realm = graph.realmOver(ground, vertex);
                if (realm != PLANET && graph.realmAt(realm).halfway == crossed) {
                    found = realm;
                }
            }
        }
    }
    return found;
}

uint enteredRealm(ref Graph graph, uint parent, Side side) {
    NodeState state = graph.nodeAt(parent).state;
    bool isAbove = state.kind == NodeStateKind.sky || state.kind == NodeStateKind.deepSky;
    if (graph.skies.isOpen() && state.realm == PLANET && isAbove && mayBeHalfway(state.surface, side, coshf(edgeLength(graph.layout).value))) {
        return graph.realmAcross(parent, side);
    } else {
        return PLANET;
    }
}

uint[FOOT_NODES] footNodes(ref Graph graph, ref const Realm realm) {
    size_t up = sideAxis(realm.footVertex, Side.a);
    Side first = realm.footVertex.canonicalSides[(up + 1) % 3];
    Side second = realm.footVertex.canonicalSides[(up + 2) % 3];
    uint across = graph.ensureNeighborSlot(realm.foot, first);
    return [realm.foot, across, graph.ensureNeighborSlot(realm.foot, second), graph.ensureNeighborSlot(across, second)];
}

SiteFrame footSite(ref const Realm realm) {
    return groundSite(realm.foot, realm.footVertex);
}

bool openSky(ref Graph graph, SiteFrame site, ubyte kind) {
    SiteFrame at = graph.atLevel(site, 0);
    SiteFrame ground = groundSite(at.node, at.vertex);
    if (graph.isBesideForced(ground)) {
        return false;
    } else {
        graph.skies.forced.insert(graph.siteOrigin(ground).key, kind);
        return true;
    }
}

bool isBeyondHalfway(ref Graph graph, ref const Realm realm, uint slot) {
    Plane halfway = Plane.fromSide(halfwaySide(realm.footVertex));
    float foot = halfway.distanceTo(MPoint!float.origin());
    float there = halfway.transformBy(graph.nodeToNode(realm.foot, slot)).distanceTo(MPoint!float.origin());
    return (foot > 0) == (there > 0);
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.fromStructure(StructureWorld.fromName("test")));
    graph.skies.kinds.append(SkyKind(0, SkyGround.flat));
    SiteFrame world = rootSite(graph.anchorSlot);
    assert(graph.openSky(world, 1));
    assert(!graph.openSky(forwarded(world, 1), 1));
    uint realm = graph.realmOver(graph.anchorSlot, world.vertex);
    assert(realm != PLANET);
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.realmAt(realm).foot), MIsometry!float.identity()), TEST_RADIUS);
    uint inRealm = 0;
    foreach (node; nearby) {
        NodeState state = *graph.ensureNodeStateAt(node.slot);
        bool isBeyond = graph.isBeyondHalfway(graph.realmAt(realm), node.slot);
        assert(isBeyond == (state.realm == realm));
        if (isBeyond) {
            inRealm += 1;
            assert(graph.ensureNodeStateAt(graph.groundNodeOf(node.slot)).realm == realm);
        }
    }
    assert(inRealm > 0 && inRealm < nearby.length);
    float footAltitude = graph.ensureNodeStateAt(graph.realmAt(realm).foot).surface.distanceTo(MPoint!float.origin());
    assert(fabsf(footAltitude - graph.ensureNodeStateAt(graph.anchorSlot).surface.distanceTo(MPoint!float.origin())) < HALFWAY_TOLERANCE);
    scratch.release();
    graph.release();
}
