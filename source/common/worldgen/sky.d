module common.worldgen.sky;

import core.math : sqrt;
import core.stdc.math : acoshf, cosh, coshf, expf, fabsf, floorf, logf, sinh, sinhf, sqrtf;
import common.array : Array;
import common.dodeca : BOUNDING_SPHERE_RADIUS, SIDE_COUNT, Side, VERTEX_COUNT, Vertex, adjacentVertices, canonicalSides, dualToNode, faceDistance, nodeToDual, reflection, vertexDualToChunkFactor;
import common.graph : Graph, NO_SLOT, Node, NodeId, ParentList;
import common.hashmap : HashMap;
import common.material : Material;
import common.math : MIsometry, MPoint, MVector;
import common.position : Position;
import common.traversal : NearbyNode, NearbyScratch;
import common.worldgen.blueprint : BlueprintBuilder, CellBox, EVERY_HEIGHT, PaintResult, lowerOf;
import common.worldgen.generation : ChunkIncidentEnviroFactors, ChunkParams, EnviroFactors, GeneratedVoxels, NodeState, StructureWorld, TERRAIN_SMOOTHNESS, Worldgen, terrainElevation, terrainElevationSlack;
import common.worldgen.plane : Plane;
import common.worldgen.structure : ClaimKey, ColumnSpot, GROUND_RING, SiteFrame, SitePart, Turn, atLevel, columnPoint, edgeCells, edgeLength, forwarded, groundRing, groundSite, isCanonicalMatch, isSamePoint, nodeToNode, rootSite, rootedVertex, sideAxis, siteHash, siteOrigin, sitePlacement, siteToNode, turned;

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
enum float ELEVATION_SPREAD = 8.0f;
enum float SKY_SIDE_MARGIN = 2.0f * BOUNDING_SPHERE_RADIUS + ELEVATION_SPREAD / TERRAIN_SMOOTHNESS;
enum float LINE_TOLERANCE = 0.05f;
enum float GROUND_LIFT_FACTOR = 0.1f;
enum float DESCENT_ALTITUDE = 2.0f;
enum float DESCENT_TOLERANCE = 1e-3f;
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

enum SkyGround : ubyte {
    terrain,
    flat,
}

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
    ClaimKey vertex;
    uint parent;
    uint footNode;
    uint users;
    int ground;
    int below;
    int balance;
    Side label;
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
    Vertex vertex;
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

struct Skies {
    Array!SkyKind kinds;
    Array!World worlds;
    Array!uint freeWorlds;
    HashMap!(ClaimKey, SkyChoice) forced;
    HashMap!(ClaimKey, SkyChoice) choices;
    HashMap!(ClaimKey, uint) worldOf;
    HashMap!(GroundKey, SkyList) risingFrom;
    Array!uint risingSkies;

    void forgetRising() {
        risingFrom.release();
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
        forced.release();
        choices.release();
        worldOf.release();
        risingFrom.release();
        risingSkies.release();
    }
}

ref const(World) worldAt(ref const Graph graph, uint world) {
    return graph.skies.worlds.ptr[world - 1];
}

Side labelOf(ref const Graph graph, uint world) {
    if (world == PLANET) {
        return Side.a;
    } else {
        return graph.worldAt(world).label;
    }
}

bool isFlatWorld(ref const Graph graph, uint world) {
    if (world == PLANET) {
        return graph.worldgen.hasPlaneGround();
    } else {
        return graph.skies.kinds.ptr[graph.worldAt(world).kind].ground == SkyGround.flat;
    }
}

float edgeOf(ref const Graph graph) {
    return edgeLength(graph.layout).value;
}

const(WorldRef)[] worldsAt(ref const Graph graph, uint slot) {
    const(Node)* node = graph.nodeAt(slot);
    if (node.worldCount == 0) {
        return null;
    } else {
        return graph.worldRefs.at(node.worldStart)[0 .. node.worldCount];
    }
}

const(WorldRef)[] ensureWorldsAt(ref Graph graph, uint slot) {
    if (!graph.nodeAt(slot).hasWorlds) {
        Array!WorldRef found;
        if (graph.skies.isOpen()) {
            graph.discoverWorlds(slot, found);
        }
        uint start = graph.reserveWorlds(cast(uint) found.length);
        foreach (index, near; found.slice()) {
            *graph.worldRefs.at(start + cast(uint) index) = near;
            graph.skies.worlds.ptr[near.world - 1].users += 1;
        }
        Node* node = graph.nodeAt(slot);
        node.worldStart = start;
        node.worldCount = cast(uint) found.length;
        node.hasWorlds = true;
        found.release();
    }
    return graph.worldsAt(slot);
}

void discoverWorlds(ref Graph graph, uint slot, ref Array!WorldRef found) {
    ParentList parents = graph.parents(slot);
    foreach (link; parents.links[0 .. parents.count]) {
        foreach (near; graph.ensureWorldsAt(link.slot)) {
            Plane plane = near.plane.reflectAcross(link.side);
            if (!found.contains(near.world) && fabsf(plane.distanceTo(MPoint!float.origin())) <= GROUND_REACH + BOUNDING_SPHERE_RADIUS) {
                found.append(WorldRef(plane, near.world));
            }
        }
    }
    graph.addSkiesOver(slot, PLANET, found);
    size_t index = 0;
    while (index < found.length) {
        uint over = found.ptr[index].world;
        if (graph.opensSkies(over)) {
            graph.addSkiesOver(slot, over, found);
        }
        index += 1;
    }
}

uint worldGroundNodeOf(ref Graph graph, uint slot, uint world) {
    uint current = slot;
    MVector!double center = MVector!double.origin();
    Plane carried = graph.planeNear(world, current);
    float altitude = fabsf(carried.distanceTo(MPoint!float.origin()));
    bool isDescending = altitude > DESCENT_ALTITUDE;
    while (isDescending) {
        Side lowest = Side.a;
        float lowestAltitude = float.infinity;
        foreach (index; 0 .. SIDE_COUNT) {
            float candidate = fabsf(carried.distanceTo(reflection(cast(Side) index) * MPoint!float.origin()));
            if (candidate < lowestAltitude) {
                lowestAltitude = candidate;
                lowest = cast(Side) index;
            }
        }
        isDescending = lowestAltitude < altitude - DESCENT_TOLERANCE;
        if (isDescending) {
            current = graph.ensureNeighborSlot(current, lowest);
            center = reflection(lowest).toType!double() * center;
            carried = carried.reflectAcross(lowest);
            altitude = lowestAltitude;
            isDescending = altitude > DESCENT_ALTITUDE;
        }
    }
    Plane plane = graph.planeNear(world, current);
    MVector!double normal = plane.scaledNormal.toType!double();
    normal = normal * (1.0 / sqrt(normal.mip(normal)));
    double along = center.mip(normal);
    MVector!double foot = (center - normal * along) * (1.0 / sqrt(1.0 + along * along));
    float lift = GROUND_LIFT_FACTOR * faceDistance();
    MVector!double above = foot * cosh(lift) + normal * sinh(lift);
    MIsometry!float toAbove = MIsometry!float.fromTranslation(MPoint!float.origin(), MPoint!float(above.toType!float()));
    return graph.slotOf(graph.ensureNormalized(Position(graph.idAt(current), toAbove)).node);
}

Plane planeNear(ref Graph graph, uint world, uint slot) {
    if (world == PLANET) {
        return graph.ensureNodeStateAt(slot).surface;
    } else {
        foreach (near; graph.worldsAt(slot)) {
            if (near.world == world) {
                return near.plane;
            }
        }
        return graph.planeOfWorldIn(world, slot);
    }
}

bool isWithinSkyReach(Plane plane) {
    return fabsf(plane.distanceTo(MPoint!float.origin())) <= SKY_REACH + BOUNDING_SPHERE_RADIUS;
}

bool opensSkies(ref const Graph graph, uint world) {
    return world == PLANET || !graph.isFlatWorld(world);
}

void addSkiesOver(ref Graph graph, uint slot, uint world, ref Array!WorldRef found) {
    SkyList rising = graph.skiesRisingFrom(graph.worldGroundNodeOf(slot, world), world);
    foreach (index; rising.start .. rising.start + rising.count) {
        uint sky = graph.skies.risingSkies.ptr[index];
        if (!found.contains(sky)) {
            Plane skyPlane = graph.inheritedPlaneOf(sky, slot);
            if (isWithinSkyReach(skyPlane)) {
                found.append(WorldRef(skyPlane, sky));
            }
        }
    }
}

Plane inheritedPlaneOf(ref Graph graph, uint sky, uint slot) {
    ParentList parents = graph.parents(slot);
    foreach (link; parents.links[0 .. parents.count]) {
        foreach (near; graph.worldsAt(link.slot)) {
            if (near.world == sky) {
                return near.plane.reflectAcross(link.side);
            }
        }
    }
    return graph.planeOfWorldIn(sky, slot);
}

SkyList skiesRisingFrom(ref Graph graph, uint ground, uint world) {
    GroundKey key = GroundKey(graph.idAt(ground), world);
    const(SkyList)* known = graph.skies.risingFrom.find(key);
    if (known !is null) {
        return *known;
    } else {
        Side label = graph.labelOf(world);
        uint[GROUND_RING] ring = graph.groundRing(ground, label);
        SkyList rising = SkyList(cast(uint) graph.skies.risingSkies.length, 0);
        foreach (face; ring) {
            foreach (index; 0 .. VERTEX_COUNT) {
                Vertex vertex = cast(Vertex) index;
                if (sideAxis(vertex, label) < 3) {
                    uint sky = graph.skyOver(face, vertex, world);
                    if (sky != PLANET && !graph.skies.risingSkies.slice()[rising.start .. $].containsWorld(sky)) {
                        graph.skies.risingSkies.append(sky);
                        rising.count += 1;
                    }
                }
            }
        }
        graph.skies.risingFrom.insert(key, rising);
        return rising;
    }
}

bool containsWorld(const(uint)[] worlds, uint world) {
    size_t index = 0;
    while (index < worlds.length && worlds[index] != world) {
        index += 1;
    }
    return index < worlds.length;
}

uint skyOver(ref Graph graph, uint face, Vertex vertex, uint world) {
    ClaimKey key = graph.rootedVertex(face, vertex).key;
    const(SkyChoice)* cached = graph.skies.choices.find(key);
    SkyChoice choice = void;
    if (cached !is null) {
        choice = *cached;
    } else {
        choice = graph.chosenSky(face, vertex, world, key);
        graph.skies.choices.insert(key, choice);
        graph.nodeAt(key.slot).hasChoices = true;
    }
    if (choice.kind == NO_SKY) {
        return PLANET;
    } else {
        return graph.ensureWorld(key, face, vertex, world, choice);
    }
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

bool isOutranked(ref Graph graph, SiteFrame neighbor, ulong mine) {
    ulong theirs = graph.siteHash(neighbor, SitePart.vertex);
    return graph.skies.forced.find(graph.siteOrigin(neighbor).key) !is null || (graph.skies.rolled(theirs).kind != NO_SKY && theirs > mine);
}

SkyChoice chosenSky(ref Graph graph, uint face, Vertex vertex, uint world, ClaimKey key) {
    const(SkyChoice)* forcedChoice = graph.skies.forced.find(key);
    if (forcedChoice !is null) {
        return *forcedChoice;
    } else {
        SiteFrame site = groundSite(face, vertex, graph.labelOf(world));
        ulong mine = graph.siteHash(site, SitePart.vertex);
        SkyChoice choice = graph.skies.rolled(mine);
        SiteFrame[GROUND_EDGES] neighbors = graph.neighborsOf(site);
        uint edge = 0;
        while (choice.kind != NO_SKY && edge < GROUND_EDGES && !graph.isOutranked(neighbors[edge], mine)) {
            edge += 1;
        }
        if (edge == GROUND_EDGES && graph.isClearOfAncestors(face, vertex, world, choice.edges)) {
            return choice;
        } else {
            return SkyChoice(NO_SKY, 0);
        }
    }
}

Plane skyPlaneOver(Vertex vertex, Side label, ubyte edges, float edge) {
    Vertex upper = vertex.adjacentVertices[sideAxis(vertex, label)];
    MVector!float base = (vertex.dualToNode * MPoint!float.origin()).vec;
    MVector!float next = (upper.dualToNode * MPoint!float.origin()).vec;
    MVector!float along = (next - base * coshf(edge)) * (1.0f / sinhf(edge));
    float rise = edges * edge;
    return Plane(-(base * sinhf(rise) + along * coshf(rise)), 0.0f);
}

Plane planeOfWorldIn(ref Graph graph, uint world, uint slot) {
    if (world == PLANET) {
        return graph.ensureNodeStateAt(slot).surface;
    } else {
        return graph.worldAt(world).plane.transformBy(graph.nodeToNode(graph.worldAt(world).footNode, slot));
    }
}

bool isApart(Plane first, Plane second, float separation) {
    float product = fabsf(first.scaledNormal.mip(second.scaledNormal));
    return product > 0 && logf(product) + first.exponent + second.exponent >= logf(coshf(separation));
}

bool isClearOfAncestors(ref Graph graph, uint face, Vertex vertex, uint world, ubyte edges) {
    Plane candidate = skyPlaneOver(vertex, graph.labelOf(world), edges, graph.edgeOf());
    float separation = CLEARANCE_EDGES * graph.edgeOf();
    uint ancestor = world;
    bool isClear = true;
    while (isClear && ancestor != PLANET) {
        ancestor = graph.worldAt(ancestor).parent;
        isClear = isApart(candidate, graph.planeOfWorldIn(ancestor, face), separation);
    }
    return isClear;
}

uint airSideNode(ref Graph graph, uint node, Vertex vertex, Side label) {
    uint slot = node;
    bool isAcross = false;
    bool isLowest = false;
    while (!isLowest) {
        ParentList parents = graph.parents(slot);
        uint index = 0;
        while (index < parents.count && sideAxis(vertex, parents.links[index].side) == 3) {
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

uint ensureWorld(ref Graph graph, ClaimKey key, uint face, Vertex vertex, uint parent, SkyChoice choice) {
    const(uint)* known = graph.skies.worldOf.find(key);
    if (known !is null) {
        return *known;
    } else {
        SiteFrame tower = graph.turned(groundSite(face, vertex, graph.labelOf(parent)), Turn.pitchUp);
        SiteFrame top = graph.atLevel(forwarded(tower, choice.edges), 0);
        Side label = top.zSide();
        uint foot = graph.airSideNode(top.node, top.vertex, label);
        Plane plane = Plane.fromSide(label);
        if (plane.distanceTo(MPoint!float.origin()) < 0) {
            plane = -plane;
        }
        World made = World(plane, groundSite(foot, top.vertex, label), key, parent, foot, 0, 0, 0, 0, label, cast(ubyte)(choice.kind - 1), choice.edges, false, true, false);
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
        graph.reference(key.slot);
        if (parent != PLANET) {
            graph.skies.worlds.ptr[parent - 1].users += 1;
        }
        return world;
    }
}

bool isIdle(ref const Graph graph, ref const World world) {
    return world.isKnown && world.users == 0 && !world.isTiled && graph.skies.forced.find(world.vertex) is null;
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
    World world = graph.worldAt(index);
    graph.unreference(world.footNode);
    graph.unreference(world.vertex.slot);
    graph.skies.worldOf.remove(world.vertex);
    if (world.parent != PLANET) {
        graph.skies.worlds.ptr[world.parent - 1].users -= 1;
    }
    graph.skies.worlds.ptr[index - 1] = World.init;
    graph.skies.freeWorlds.append(index);
    graph.skies.forgetRising();
}

bool openSky(ref Graph graph, SiteFrame site, SkyChoice choice) {
    SiteFrame at = graph.atLevel(site, 0);
    SiteFrame ground = groundSite(at.node, at.vertex, at.ySide);
    uint besides = 0;
    foreach (neighbor; graph.neighborsOf(ground)) {
        if (graph.skies.forced.find(graph.siteOrigin(neighbor).key) !is null) {
            besides += 1;
        }
    }
    if (besides > 0) {
        return false;
    } else {
        ClaimKey key = graph.siteOrigin(ground).key;
        graph.skies.forced.insert(key, choice);
        graph.reference(key.slot);
        return true;
    }
}

Grounds groundsAt(ref Graph graph, uint slot) {
    graph.ensureNodeStateAt(slot);
    graph.ensureWorldsAt(slot);
    return graph.groundsIn(slot);
}

Grounds groundsIn(ref const Graph graph, uint slot) {
    Grounds grounds;
    grounds.items[0] = Ground(graph.nodeAt(slot).state.surface, graph.isFlatWorld(PLANET));
    grounds.count = 1;
    foreach (sky; graph.worldsAt(slot)) {
        if (grounds.count < MAX_GROUNDS && fabsf(sky.plane.distanceTo(MPoint!float.origin())) <= GROUND_REACH) {
            grounds.items[grounds.count] = Ground(sky.plane, graph.isFlatWorld(sky.world));
            grounds.count += 1;
        }
    }
    return grounds;
}

ChunkPoint chunkPointOf(MPoint!float point) {
    ChunkPoint best;
    float leastOutside = float.infinity;
    foreach (index; 0 .. VERTEX_COUNT) {
        Vertex vertex = cast(Vertex) index;
        MVector!float dual = vertex.nodeToDual * point.vec;
        float[3] coords = void;
        float outside = 0;
        foreach (axis; 0 .. 3) {
            coords[axis] = dual.data[axis] / dual.data[3] * vertexDualToChunkFactor();
            if (coords[axis] < 0 && -coords[axis] > outside) {
                outside = -coords[axis];
            }
            if (coords[axis] > 1 && coords[axis] - 1 > outside) {
                outside = coords[axis] - 1;
            }
        }
        if (outside < leastOutside) {
            leastOutside = outside;
            best = ChunkPoint(coords, vertex);
        }
    }
    return best;
}

ChunkIncidentEnviroFactors loadedEnviro(ref const Graph graph, uint slot, Vertex vertex) {
    Side[3] sides = vertex.canonicalSides;
    EnviroFactors own = graph.nodeAt(slot).state.enviro;
    ChunkIncidentEnviroFactors result;
    foreach (corner; 0 .. 8) {
        uint around = slot;
        foreach (axis; 0 .. 3) {
            if (around != NO_SLOT && (corner & (4 >> axis)) != 0) {
                around = graph.neighborSlot(around, sides[axis]);
            }
        }
        EnviroFactors enviro = own;
        if (around != NO_SLOT && graph.nodeAt(around).hasState) {
            enviro = graph.nodeAt(around).state.enviro;
        }
        result.maxElevations[corner] = enviro.maxElevation;
        result.temperatures[corner] = enviro.temperature;
        result.rainfalls[corner] = enviro.rainfall;
        result.blockinesses[corner] = enviro.blockiness;
    }
    return result;
}

float heightAbove(ref const ChunkIncidentEnviroFactors env, ChunkPoint at, float altitude, bool isFlat) {
    if (isFlat) {
        return altitude;
    } else {
        return altitude - terrainElevation(env, at.coords, altitude) / TERRAIN_SMOOTHNESS;
    }
}

Gravity gravityAt(ref const Graph graph, Position position) {
    uint slot = graph.slotOf(position.node);
    Grounds grounds = graph.groundsIn(slot);
    if (grounds.count == 1) {
        return Gravity(grounds.items[0].surface.upAt(position.local), 1.0f);
    } else {
        MPoint!float point = position.local * MPoint!float.origin();
        ChunkPoint at = chunkPointOf(point);
        ChunkIncidentEnviroFactors env = graph.loadedEnviro(slot, at.vertex);
        float[MAX_GROUNDS] heights = void;
        float[3][MAX_GROUNDS] ups = void;
        foreach (index, ground; grounds.items[0 .. grounds.count]) {
            heights[index] = heightAbove(env, at, ground.surface.distanceTo(point), ground.isFlat);
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

bool isPaintedBySky(ref Graph graph, uint slot, WorldRef sky) {
    return graph.isOnSkySide(slot, sky) || graph.isOnFootLine(slot, sky.world);
}

bool isOnSkySide(ref Graph graph, uint slot, WorldRef sky) {
    MPoint!float center = MPoint!float.origin();
    ChunkPoint at = chunkPointOf(center);
    ChunkIncidentEnviroFactors env = ChunkIncidentEnviroFactors.make(graph, slot, at.vertex);
    uint parent = graph.worldAt(sky.world).parent;
    float own = heightAbove(env, at, sky.plane.distanceTo(center), graph.isFlatWorld(sky.world));
    float other = heightAbove(env, at, graph.planeOfWorldIn(parent, slot).distanceTo(center), graph.isFlatWorld(parent));
    return own - other <= SKY_SIDE_MARGIN;
}

bool isOnFootLine(ref const Graph graph, uint slot, uint sky) {
    World world = graph.worldAt(sky);
    MVector!float center = (graph.nodeToNode(slot, world.footNode) * MPoint!float.origin()).vec;
    float alongFoot = center.mip((world.foot.vertex.dualToNode * MPoint!float.origin()).vec);
    float alongUp = center.mip(world.plane.scaledNormal);
    float reach = coshf(edgeLineDistance() + LINE_TOLERANCE);
    return alongFoot * alongFoot - alongUp * alongUp <= reach * reach;
}

float edgeLineDistance() {
    MVector!float vertex = (Vertex.a.dualToNode * MPoint!float.origin()).vec;
    MVector!float next = (Vertex.a.adjacentVertices[0].dualToNode * MPoint!float.origin()).vec;
    MVector!float across = next + vertex * vertex.mip(next);
    MVector!float along = across * (1.0f / sqrtf(across.mip(across)));
    MVector!float center = MPoint!float.origin().vec;
    float alongVertex = center.mip(vertex);
    float alongEdge = center.mip(along);
    return acoshf(sqrtf(alongVertex * alongVertex - alongEdge * alongEdge));
}

bool isInBand(Plane plane, bool isFlat, EnviroFactors enviro) {
    float altitude = plane.distanceTo(MPoint!float.origin());
    float top = 0;
    float bottom = 0;
    if (!isFlat) {
        float slack = terrainElevationSlack() + ELEVATION_SPREAD;
        top = (enviro.maxElevation + slack) / TERRAIN_SMOOTHNESS;
        bottom = (enviro.maxElevation - slack) / TERRAIN_SMOOTHNESS;
    }
    return altitude - BOUNDING_SPHERE_RADIUS < top && altitude + BOUNDING_SPHERE_RADIUS > bottom;
}

bool mayHoldContent(ref Graph graph, uint slot) {
    NodeState state = *graph.ensureNodeStateAt(slot);
    bool holds = graph.ensureStructureAt(slot) || isInBand(state.surface, graph.isFlatWorld(PLANET), state.enviro);
    foreach (sky; graph.ensureWorldsAt(slot)) {
        holds = holds || isInBand(sky.plane, graph.isFlatWorld(sky.world), state.enviro);
    }
    return holds;
}

float worldHeightAt(ref Graph graph, uint world, Position position) {
    uint slot = graph.slotOf(position.node);
    MPoint!float point = position.local * MPoint!float.origin();
    ChunkPoint at = chunkPointOf(point);
    ChunkIncidentEnviroFactors env = ChunkIncidentEnviroFactors.make(graph, slot, at.vertex);
    return heightAbove(env, at, graph.planeOfWorldIn(world, slot).distanceTo(point), graph.isFlatWorld(world));
}

Position cellOnLine(ref Graph graph, SiteFrame line, int cell) {
    MPoint!float inSite = sitePlacement(line, graph.layout) * columnPoint(graph.layout, ColumnSpot(0, 0, cell + 0.5f));
    return graph.ensureNormalized(Position(graph.idAt(line.node), MIsometry!float.fromTranslation(MPoint!float.origin(), inSite)));
}

int groundAlong(ref Graph graph, SiteFrame line, uint world, int span) {
    int cell = -span;
    while (cell < span && graph.worldHeightAt(world, graph.cellOnLine(line, cell)) < 0) {
        cell += 1;
    }
    return cell;
}

bool isSkyNearer(ref Graph graph, SiteFrame line, uint sky, int cell) {
    Position at = graph.cellOnLine(line, cell);
    return graph.worldHeightAt(sky, at) < graph.worldHeightAt(graph.worldAt(sky).parent, at);
}

int balanceAlong(ref Graph graph, SiteFrame line, uint sky, int most) {
    int nearer = 0;
    int farther = 1;
    while (farther < most && graph.isSkyNearer(line, sky, farther)) {
        nearer = farther;
        farther = lowerOf(farther * 2, most);
    }
    if (farther == most && graph.isSkyNearer(line, sky, most)) {
        return most;
    } else {
        while (farther - nearer > 1) {
            int middle = (nearer + farther) / 2;
            if (graph.isSkyNearer(line, sky, middle)) {
                nearer = middle;
            } else {
                farther = middle;
            }
        }
        return farther;
    }
}

void measureSky(ref Graph graph, uint sky) {
    World world = graph.worldAt(sky);
    int span = world.edges * edgeCells(graph.layout.dimension);
    SiteFrame up = graph.turned(world.foot, Turn.pitchUp);
    SiteFrame down = graph.turned(graph.turned(forwarded(up, world.edges), Turn.pitchUp), Turn.pitchUp);
    int ground = graph.groundAlong(up, sky, span);
    int below = graph.groundAlong(down, world.parent, span);
    int balance = graph.balanceAlong(up, sky, span);
    World* stored = &graph.skies.worlds.ptr[sky - 1];
    stored.ground = ground;
    stored.below = below;
    stored.balance = balance;
    stored.isMeasured = true;
}

ref const(World) measuredWorld(ref Graph graph, uint sky) {
    if (!graph.worldAt(sky).isMeasured) {
        graph.measureSky(sky);
    }
    return graph.worldAt(sky);
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.fromStructure(StructureWorld.fromName("test")));
    graph.skies.kinds.append(SkyKind(0, SkyGround.flat));
    SiteFrame world = rootSite(graph.anchorSlot);
    assert(graph.openSky(world, SkyChoice(1, LOWEST_SKY_EDGES)));
    assert(!graph.openSky(forwarded(world, 1), SkyChoice(1, LOWEST_SKY_EDGES)));
    uint sky = graph.skyOver(graph.anchorSlot, world.vertex, PLANET);
    assert(sky != PLANET);
    NearbyScratch scratch;
    NearbyNode[] nearby = scratch.collectAll(graph, Position(graph.idAt(graph.worldAt(sky).footNode), MIsometry!float.identity()), TEST_RADIUS);
    foreach (node; nearby) {
        const(WorldRef)[] worlds = graph.ensureWorldsAt(node.slot);
        foreach (found; worlds) {
            assert(fabsf(graph.planeOfWorldIn(found.world, node.slot).distanceTo(MPoint!float.origin()) - found.plane.distanceTo(MPoint!float.origin())) < TEST_PLANE_TOLERANCE);
        }
        bool isNear = fabsf(graph.planeOfWorldIn(sky, node.slot).distanceTo(MPoint!float.origin())) <= GROUND_REACH;
        assert(!isNear || worlds.length == 1);
    }
    float footAltitude = graph.planeOfWorldIn(sky, graph.worldAt(sky).footNode).distanceTo(MPoint!float.origin());
    float anchorAltitude = graph.ensureNodeStateAt(graph.anchorSlot).surface.distanceTo(MPoint!float.origin());
    assert(fabsf(footAltitude - anchorAltitude) < TEST_PLANE_TOLERANCE);
    uint[GROUND_RING] ring = graph.groundRing(graph.anchorSlot, Side.a);
    SiteFrame high = graph.atLevel(forwarded(graph.turned(world, Turn.pitchUp), TEST_RISE_EDGES), 0);
    uint below = graph.worldGroundNodeOf(high.node, PLANET);
    uint index = 0;
    while (index < GROUND_RING && ring[index] != below) {
        index += 1;
    }
    assert(index < GROUND_RING);
    assert(graph.worldGroundNodeOf(graph.worldAt(sky).footNode, sky) == graph.worldAt(sky).footNode);
    foreach (node; nearby) {
        uint[2] worlds = [PLANET, sky];
        foreach (over; worlds) {
            float ground = graph.planeOfWorldIn(over, graph.worldGroundNodeOf(node.slot, over)).distanceTo(MPoint!float.origin());
            assert(fabsf(ground - faceDistance()) < TEST_PLANE_TOLERANCE);
        }
    }
    assert(graph.isOnFootLine(graph.worldAt(sky).footNode, sky));
    assert(!graph.isOnFootLine(graph.atLevel(forwarded(graph.worldAt(sky).foot, TEST_FAR_EDGES), 0).node, sky));
    SiteFrame quarter = graph.worldAt(sky).foot;
    foreach (_; 0 .. GROUND_EDGES) {
        SiteFrame tower = graph.turned(graph.turned(quarter, Turn.pitchUp), Turn.rollRight);
        assert(graph.isCanonicalMatch(tower));
        assert(graph.isCanonicalMatch(graph.turned(graph.turned(graph.turned(forwarded(tower, LOWEST_SKY_EDGES), Turn.pitchUp), Turn.pitchUp), Turn.rollRight)));
        quarter = graph.turned(quarter, Turn.right);
    }
    SiteFrame skyTower = graph.turned(graph.turned(graph.worldAt(sky).foot, Turn.pitchUp), Turn.rollRight);
    SiteFrame planetTower = graph.turned(graph.turned(graph.turned(forwarded(skyTower, LOWEST_SKY_EDGES), Turn.pitchUp), Turn.pitchUp), Turn.rollRight);
    float length = LOWEST_SKY_EDGES * edgeCells(graph.layout.dimension);
    foreach (cell; TEST_PAINTED_CELLS) {
        MPoint!float fromSky = graph.siteToNode(skyTower, skyTower.node) * columnPoint(graph.layout, ColumnSpot(cell[0] + 0.5f, cell[1] + 0.5f, cell[2] + 0.5f));
        MPoint!float fromPlanet = graph.siteToNode(planetTower, skyTower.node) * columnPoint(graph.layout, ColumnSpot(cell[1] + 0.5f, cell[0] + 0.5f, length - cell[2] - 0.5f));
        assert(isSamePoint(fromSky, fromPlanet));
    }
    BlueprintBuilder builder = BlueprintBuilder.make(graph);
    foreach (cell; TEST_PAINTED_CELLS) {
        assert(builder.paint(skyTower, CellBox.make(cell[0], cell[0], cell[1], cell[1], cell[2], cell[2]), EVERY_HEIGHT, Material.granite, false) == PaintResult.painted);
    }
    foreach (cell; TEST_PAINTED_CELLS) {
        MPoint!float center = sitePlacement(skyTower, graph.layout) * columnPoint(graph.layout, ColumnSpot(cell[0] + 0.5f, cell[1] + 0.5f, cell[2] + 0.5f));
        Position at = graph.ensureNormalized(Position(graph.idAt(skyTower.node), MIsometry!float.fromTranslation(MPoint!float.origin(), center)));
        ChunkPoint inChunk = chunkPointOf(at.local * MPoint!float.origin());
        int[3] voxel = void;
        foreach (axis; 0 .. 3) {
            voxel[axis] = cast(int) floorf(graph.layout.chunkToGrid(inChunk.coords[axis]));
        }
        assert(graph.ensureBuildingAt(graph.slotOf(at.node)).materialAt(inChunk.vertex, voxel, Material.none) == Material.granite);
    }
    builder.release();
    Plane over = skyPlaneOver(world.vertex, Side.a, LOWEST_SKY_EDGES, graph.edgeOf());
    Plane stored = graph.planeOfWorldIn(sky, graph.anchorSlot);
    assert(fabsf(over.distanceTo(MPoint!float.origin()) - stored.distanceTo(MPoint!float.origin())) < TEST_PLANE_TOLERANCE);
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
    uint sky = graph.skyOver(graph.anchorSlot, root.vertex, PLANET);
    assert(sky != PLANET);
    World world = graph.worldAt(sky);
    uint solid = graph.ensureNeighborSlot(world.footNode, world.label);
    GeneratedVoxels generated = ChunkParams.make(graph, solid, world.foot.vertex).generateVoxels();
    assert(generated.voxels.isSolid() && generated.voxels.get(0) != Material.none);
    generated.voxels.release();
    graph.release();
}
