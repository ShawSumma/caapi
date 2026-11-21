module app.scripts.walk;

import core.stdc.math : atan2, ceil, cosf, sinf, sinh;
import base.maybe : Maybe;
import base.numbers : PI, RADIANS_PER_DEGREE, higherOf, lowerOf;
import base.units : Length, Time;
import base.vector3 : Vec3, ZERO_VECTOR, cross, magnitude, plus, rejectAlong, scaled;
import client.structures : ensureRisingTag, probeWorldPort;
import common.character.controller : Footing, MovementMode, movedBy, perpendicularTo;
import common.character.features : CellRange, LocalFrame, visitCells;
import common.graph : Graph;
import common.material : materialNames;
import common.node : Chunk, ChunkSlot, ChunkState, cellIndex;
import common.position : Position;
import common.worldgen.horospheres : HorosphereId, ROOT, edgeOf, ensureGravityAt, ensureHorosphereOver, ensurePlaneHeight, ensureUndersideAt;
import common.worldgen.structure : ColumnSpot, SiteFrame, columnPoint, edgeCells, forwarded, moveToLevel, rootSite, siteOf, sitePlacement, turnSite;
import geometry.honeycomb : Face;
import geometry.lorentz : Point, Shift = Motion;
import plugins.api.api : KindTag, Material, Turn, tagNamed;
import plugins.game.game : Key;
import app.script : Script, StepHook, degrees, materialNamed;
import app.scripts.claims : Measure, Topic, claim;

enum float SPEED = 0.225f;
enum float SPEED_TOLERANCE = 0.0025f;
enum float BLOCKED_SPEED = SPEED / 2;
enum float HALF_HEIGHT = 0.045f;
enum float CONTACT_SKIN = 0.0005f;
enum float STANDING_ALTITUDE = HALF_HEIGHT + CONTACT_SKIN;
enum float ALTITUDE_TOLERANCE = 0.0001f;
enum float FLY_SPEED = 0.4f;
enum float NOCLIP_SPEED = 0.6f;
enum double STRAIGHT_DOWN_DEGREES = 89;
enum float WALL_HOVER_PER_BLOCK = 0.1f;
enum float WALL_DISTANCE = 0.15f;
enum float WALL_HALF_WIDTH = 0.075f;
enum float ROW_STEP = 0.0125f;
enum float STEP_DEPTH = 0.075f;
enum string GROUND = "base:dirt";
immutable BuildLayer[3] BUILD_LAYERS = [BuildLayer(1, "base:wood-planks"), BuildLayer(4, "base:grey-brick"), BuildLayer(5, "base:white-brick")];
enum double TURN_SECONDS = 0.96;
enum double SETTLE_SECONDS = 0.48;
enum double LANDING_SECONDS = 2;
enum float LEAST_BLOCK_EDGE = 0.035f;
enum float MOST_BLOCK_EDGE = 0.077f;
enum size_t MOST_PORT_SITES = 4096;
enum float SEARCH_REACH = 0.6f;
enum float HOP_DISTANCE = 0.6f;
enum int BENEATH_EDGES = 3;
enum float BENEATH_MARGIN_EDGES = 0.5f;
enum int SHAFT_HALF = 4;
enum int TREAD_REACH_CELLS = SHAFT_HALF + 2;
enum float SIDED_REACH = 0.5f;
enum string POLE_STEP = "base:wood-planks";
enum int POLE_LINE_EDGES = 4;
enum string SUBWAY_RAILING = "base:steel";
enum string SUBWAY_RIM = "base:pollen";
enum string SUBWAY_MEZZANINE = "base:ceiling-tile";
enum string SUBWAY_TRANSFER = "base:acacia-wood";
enum int SUBWAY_RAILING_X = 4;
enum int SUBWAY_RAILING_Z = 6;
enum int SUBWAY_RIM_X = 2;
enum int SUBWAY_MIDDLE = 12;
enum int SUBWAY_MEZZANINE_X = -3;
enum int SUBWAY_MEZZANINE_Y = -6;
enum int SUBWAY_MEZZANINE_Z = 9;
enum int SUBWAY_TRANSFER_X = 3;
enum int SUBWAY_TRANSFER_Y = -8;
enum uint MAZE_GROUND = tagNamed("lattice:maze");
enum int MAZE_EDGES_AWAY = 5;
enum float MAZE_ASIDE = 0.5f;
enum float MAZE_ALONG = 8;
enum string MAZE_DECK = "base:wood-planks";
enum string SUBWAY_BALLAST = "base:gravel";
enum int LOWEST_BORE = -12;
enum int SHALLOW_BALLAST = -8;
enum int HIGHEST_DOOR = -4;
enum int DOOR_Z = 4;
enum int DOOR_RUN = 5;
enum int DEEP_RIM = -11;
enum int SHALLOW_RIM = -6;
enum string SUBWAY_ABANDONED_WALL = "base:wet-concrete";
enum string SUBWAY_WINDOW = "base:glass";
enum int SUBWAY_WALL_X = 5;
enum int SUBWAY_WALL_Y = -2;
enum int SUBWAY_WINDOW_X = -2;
enum int SUBWAY_WINDOW_RISE = 3;
immutable string[2] STREET_MATERIALS =["base:basalt", "base:white-brick"];
immutable string[7] TOWER_MATERIALS = ["base:concrete", "base:white-brick", "base:grey-brick", "base:sandstone", "base:wood-planks", "base:steel", "base:marble"];
immutable string[5] BACKROOMS_FLOORS = ["base:carpet", "base:damp-carpet", "base:red-carpet", "base:concrete", "base:marble"];
immutable string[6] BACKROOMS_CEILINGS = ["base:ceiling-tile", "base:light-panel", "base:concrete", "base:plaster", "base:white-brick", "base:sunlight"];

struct BuildLayer {
    uint slot;
    string material;
}

struct Sought {
    Material wanted;
    Maybe!(Vec3!float) nearest;

    void visitMissingNode(uint, Face) {
    }

    void visitChunk(ref const Graph graph, LocalFrame frame, ChunkSlot slot, CellRange range) {
        if (graph.chunks.at(slot).state == ChunkState.populated) {
            foreach (x; range.low.x .. range.high.x + 1) {
                foreach (y; range.low.y .. range.high.y + 1) {
                    foreach (z; range.low.z .. range.high.z + 1) {
                        if (graph.chunks.at(slot).voxels.at(cellIndex(graph.layout.dimension, x, y, z)) == wanted) {
                            Vec3!float center = frame.cell(graph.layout, slot.corner, Vec3!int(x, y, z)).center();
                            if (!nearest.exists || center.magnitude < nearest.value.magnitude) {
                                nearest = Maybe!(Vec3!float).of(center);
                            }
                        }
                    }
                }
            }
        }
    }
}

Maybe!Position nearestAround(ref Script world, Position from, Material wanted) {
    world.game.generateWithin(from, Length(SEARCH_REACH));
    Sought sought = Sought(wanted);
    visitCells(world.game.world.graph, from, Length(SEARCH_REACH), sought);
    if (sought.nearest.exists) {
        return Maybe!Position.of(world.game.world.graph.movedBy(from, sought.nearest.value));
    } else {
        return Maybe!Position.init;
    }
}

Position hopped(ref Script world, Position from, float angle, float distance) {
    Vec3!float up = world.game.world.graph.ensureGravityAt(from).up;
    Vec3!float side = perpendicularTo(up).rejectAlong(up);
    Vec3!float first = side.scaled(1 / side.magnitude);
    Vec3!float second = up.cross(first);
    Vec3!float along = first.scaled(cosf(angle)).plus(second.scaled(sinf(angle)));
    return world.game.world.graph.ensureNormalized(Position(from.node, (from.local * Shift!float.shift(along.scaled(distance))).orthonormalized()));
}

Maybe!Position ensureNearest(ref Script world, Position from, Material wanted, uint rings) {
    Maybe!Position found = nearestAround(world, from, wanted);
    uint ring = 1;
    while (!found.exists && ring <= rings) {
        float radius = ring * HOP_DISTANCE;
        uint count = cast(uint) ceil(2 * PI * sinh(radius) / HOP_DISTANCE);
        uint index = 0;
        while (!found.exists && index < count) {
            found = nearestAround(world, hopped(world, from, index * 2 * PI / count, radius), wanted);
            index += 1;
        }
        ring += 1;
    }
    return found;
}

enum Beneath : ubyte {
    open,
    rock,
}

enum ClimbGoal : ubyte {
    timed,
    ontoStep,
}

struct Motion {
    float excess = 0;
    float excessAt = 0;
    float cap = SPEED;
    float rise = 0;
    float lowest = 0;
    float highest = 0;
    uint offGround;
    Footing lastFooting;
}

struct Across {
    float walked = 0;
    float climbed = 0;
}

const(char)[] nameOf(Maybe!Material target) {
    if (target.exists) {
        return materialNames.ptr[target.value.id];
    } else {
        return "nothing";
    }
}

bool isMaterial(Maybe!Material target, const(char)[] name) {
    return target.exists && materialNames.ptr[target.value.id] == name;
}

bool isOneOf(Maybe!Material target, const(string)[] names) {
    size_t index = 0;
    while (index < names.length && !isMaterial(target, names[index])) {
        index += 1;
    }
    return index < names.length;
}

Maybe!Material lookBelow(ref Script world) {
    world.look(degrees(0), degrees(STRAIGHT_DOWN_DEGREES));
    Maybe!Material below = world.targetMaterial();
    world.look(degrees(0), degrees(-STRAIGHT_DOWN_DEGREES));
    return below;
}

void spawn(ref Script world) {
    world.check(world.mode() == MovementMode.walk, "spawned walking");
    world.check(world.isOnGround(), "spawned standing on the ground");
}

Position ensureVertex(ref Graph graph, SiteFrame site) {
    Point!float vertex = sitePlacement(site, graph.layout) * Point!float.origin();
    return graph.ensureNormalized(Position(graph.idAt(site.node), Shift!float.shiftTo(vertex)));
}

Maybe!Position ensureLastFlat(ref Script world) {
    Graph* graph = &world.game.world.graph;
    const(SiteFrame)[] flats = graph.structures.blueprint.flats.slice();
    if (flats.length == 0) {
        return Maybe!Position.init;
    } else {
        return Maybe!Position.of((*graph).ensureVertex(flats[$ - 1]));
    }
}

Position ensureBelowVertex(ref Graph graph, SiteFrame site, int edges) {
    SiteFrame up = graph.view.turnSite(site, Turn.pitchUp);
    float center = graph.layout.dimension;
    Point!float spot = sitePlacement(up, graph.layout) * columnPoint(graph.layout, ColumnSpot(center, center, -edges * edgeCells(graph.layout.dimension) - center));
    return graph.ensureNormalized(Position(graph.idAt(up.node), Shift!float.shiftTo(spot)));
}

bool isBeneath(Beneath wanted, float depth, float underside, float margin) {
    final switch (wanted) {
        case Beneath.open:
            return depth > underside + margin;
        case Beneath.rock:
            return depth < underside - margin;
    }
}

Maybe!Position ensureUnderGround(ref Script world, Beneath wanted) {
    Graph* graph = &world.game.world.graph;
    float margin = BENEATH_MARGIN_EDGES * graph.view.edgeOf();
    SiteFrame[MOST_PORT_SITES] sites;
    sites[0] = rootSite(graph.anchorSlot);
    size_t count = 1;
    size_t next = 0;
    Maybe!Position found;
    while (!found.exists && next < count) {
        SiteFrame site = graph.view.moveToLevel(sites[next], 0);
        next += 1;
        Position below = (*graph).ensureBelowVertex(site, BENEATH_EDGES);
        float depth = -graph.view.ensurePlaneHeight(ROOT, below);
        float underside = graph.view.ensureUndersideAt(ROOT, below);
        if (isBeneath(wanted, depth, underside, margin)) {
            found = Maybe!Position.of(below);
        } else if (count + 3 <= MOST_PORT_SITES) {
            SiteFrame ahead = forwarded(site, 1);
            sites[count] = ahead;
            sites[count + 1] = graph.view.turnSite(ahead, Turn.left);
            sites[count + 2] = graph.view.turnSite(ahead, Turn.right);
            count += 3;
        }
    }
    return found;
}

SiteFrame ensureStart(ref Script world) {
    Graph* graph = &world.game.world.graph;
    return graph.view.moveToLevel(rootSite(graph.anchorSlot), 0);
}

bool probeStartPort(ref Script world) {
    return world.game.world.graph.probeWorldPort(siteOf(ensureStart(world)));
}

Position ensureStartVertex(ref Script world) {
    return world.game.world.graph.ensureVertex(ensureStart(world));
}

struct PortCensus {
    uint asked;
    uint agreeing;
    uint ports;
}

PortCensus censusPorts(ref Script world, uint most) {
    Graph* graph = &world.game.world.graph;
    SiteFrame[MOST_PORT_SITES] sites;
    sites[0] = rootSite(graph.anchorSlot);
    size_t count = 1;
    PortCensus census;
    while (census.asked < most && census.asked < count) {
        SiteFrame site = graph.view.moveToLevel(sites[census.asked], 0);
        bool lying = (*graph).probeWorldPort(siteOf(site));
        bool upright = (*graph).probeWorldPort(siteOf(graph.view.turnSite(site, Turn.pitchUp)));
        if (lying == upright) {
            census.agreeing += 1;
        }
        if (lying) {
            census.ports += 1;
        }
        if (count + 3 <= MOST_PORT_SITES) {
            SiteFrame ahead = forwarded(site, 1);
            sites[count] = ahead;
            sites[count + 1] = graph.view.turnSite(ahead, Turn.left);
            sites[count + 2] = graph.view.turnSite(ahead, Turn.right);
            count += 3;
        }
        census.asked += 1;
    }
    return census;
}

struct CellMaterial {
    Maybe!Material found;

    void visitMissingNode(uint, Face) {
    }

    void visitChunk(ref const Graph graph, LocalFrame frame, ChunkSlot slot, CellRange range) {
        const(Chunk)* chunk = graph.chunks.at(slot);
        if (!found.exists && chunk.state == ChunkState.populated) {
            foreach (x; range.low.x .. range.high.x + 1) {
                foreach (y; range.low.y .. range.high.y + 1) {
                    foreach (z; range.low.z .. range.high.z + 1) {
                        if (!found.exists && !(frame.cell(graph.layout, slot.corner, Vec3!int(x, y, z)).distanceTo(ZERO_VECTOR) > 0)) {
                            found = Maybe!Material.of(chunk.voxels.at(cellIndex(graph.layout.dimension, x, y, z)));
                        }
                    }
                }
            }
        }
    }
}

Position columnPosition(ref Script world, SiteFrame site, float x, float y, float z) {
    Graph* graph = &world.game.world.graph;
    Point!float point = sitePlacement(site, graph.layout) * columnPoint(graph.layout, ColumnSpot(x, y, z));
    return (*graph).ensureNormalized(Position(graph.idAt(site.node), Shift!float.shiftTo(point)));
}

Position cellPosition(ref Script world, SiteFrame site, int x, int y, int z) {
    return columnPosition(world, site, x + 0.5f, y + 0.5f, z + 0.5f);
}

Maybe!Material generatedAt(ref Script world, Position at) {
    CellMaterial probe;
    visitCells(world.game.world.graph, at, Length(0), probe);
    return probe.found;
}

bool isNewel(int x, int y) {
    return (x == -1 || x == 0) && (y == -1 || y == 0);
}

struct TreadSeen {
    double degrees = 0;
    uint cells;
    Maybe!Material other;
}

TreadSeen treadIn(ref Script world, SiteFrame up, Material stair, int z) {
    double sumX = 0;
    double sumY = 0;
    uint cells = 0;
    Maybe!Material other;
    world.game.generateWithin(cellPosition(world, up, 0, 0, z), Length(TREAD_REACH_CELLS * world.game.blockLength().value));
    foreach (x; -SHAFT_HALF .. SHAFT_HALF) {
        foreach (y; -SHAFT_HALF .. SHAFT_HALF) {
            if (!isNewel(x, y)) {
                Maybe!Material held = generatedAt(world, cellPosition(world, up, x, y, z));
                if (held.exists && held.value == stair) {
                    sumX += x + 0.5;
                    sumY += y + 0.5;
                    cells += 1;
                } else if (held.exists && held.value != Material.none) {
                    other = held;
                }
            }
        }
    }
    return TreadSeen(atan2(sumY, sumX) / RADIANS_PER_DEGREE, cells, other);
}

Maybe!int stairPairOn(ref Script world, SiteFrame line, Material step, int cells, int first, int last) {
    Maybe!int found;
    uint below = 0;
    int edge = first;
    while (!found.exists && edge <= last) {
        if (treadIn(world, world.game.world.graph.view.moveToLevel(forwarded(line, edge), 0), step, cells / 2).cells > 0) {
            below += 1;
        } else {
            below = 0;
        }
        if (below >= 2) {
            found = Maybe!int.of(edge - 1);
        }
        edge += 1;
    }
    return found;
}

struct PoleStair {
    SiteFrame line;
    int edge;
}

Maybe!PoleStair ensurePoleStair(ref Script world) {
    Graph* graph = &world.game.world.graph;
    Material step = materialNamed(POLE_STEP);
    int cells = edgeCells(graph.layout.dimension);
    SiteFrame[MOST_PORT_SITES] sites;
    sites[0] = rootSite(graph.anchorSlot);
    size_t count = 1;
    size_t next = 0;
    Maybe!PoleStair found;
    while (!found.exists && next < count) {
        SiteFrame site = graph.view.moveToLevel(sites[next], 0);
        next += 1;
        SiteFrame line = graph.view.turnSite(site, Turn.pitchUp);
        Maybe!int pair = stairPairOn(world, line, step, cells, 0, POLE_LINE_EDGES - 1);
        if (pair.exists) {
            found = Maybe!PoleStair.of(PoleStair(line, pair.value));
        } else if (count + 3 <= MOST_PORT_SITES) {
            SiteFrame ahead = forwarded(site, 1);
            sites[count] = ahead;
            sites[count + 1] = graph.view.turnSite(ahead, Turn.left);
            sites[count + 2] = graph.view.turnSite(ahead, Turn.right);
            count += 3;
        }
    }
    return found;
}

enum Mirror : ubyte {
    same,
    mirrored,
}

immutable Mirror[2] MIRRORS = [Mirror.same, Mirror.mirrored];

int mirroredCell(Mirror mirror, int x) {
    final switch (mirror) {
        case Mirror.same:
            return x;
        case Mirror.mirrored:
            return -x - 1;
    }
}

float mirroredAt(Mirror mirror, float x) {
    final switch (mirror) {
        case Mirror.same:
            return x;
        case Mirror.mirrored:
            return -x;
    }
}

struct Sided {
    SiteFrame site;
    Mirror mirror;

    Position spot(ref Script world, float x, float y, float z) const {
        return columnPosition(world, site, mirroredAt(mirror, x), y, z);
    }

    bool holds(ref Script world, int x, int y, int z, string material) const {
        Maybe!Material held = generatedAt(world, cellPosition(world, site, mirroredCell(mirror, x), y, z));
        return held.exists && held.value == materialNamed(material);
    }

    bool isFilled(ref Script world, int x, int y, int z) const {
        Maybe!Material held = generatedAt(world, cellPosition(world, site, mirroredCell(mirror, x), y, z));
        return held.exists && held.value != Material.none;
    }
}

bool isEntrance(ref Script world, Sided end) {
    return end.holds(world, SUBWAY_RAILING_X, 1, SUBWAY_RAILING_Z, SUBWAY_RAILING);
}

bool isStation(ref Script world, Sided end, int rim) {
    return end.holds(world, SUBWAY_RIM_X, rim, SUBWAY_MIDDLE, SUBWAY_RIM);
}

bool isDeepEntrance(ref Script world, Sided end) {
    return isEntrance(world, end) && end.holds(world, SUBWAY_MEZZANINE_X, SUBWAY_MEZZANINE_Y, SUBWAY_MEZZANINE_Z, SUBWAY_MEZZANINE);
}

bool isShallowStation(ref Script world, Sided end) {
    return isStation(world, end, SHALLOW_RIM);
}

bool isAbandonedStation(ref Script world, Sided end) {
    return (isStation(world, end, DEEP_RIM) || isStation(world, end, SHALLOW_RIM)) && end.holds(world, SUBWAY_WALL_X, SUBWAY_WALL_Y, SUBWAY_MIDDLE, SUBWAY_ABANDONED_WALL);
}

bool isDeepParkedCar(ref Script world, Sided end) {
    return end.holds(world, SUBWAY_WINDOW_X, LOWEST_BORE + SUBWAY_WINDOW_RISE, SUBWAY_MIDDLE, SUBWAY_WINDOW);
}

bool isTransfer(ref Script world, Sided end) {
    return end.holds(world, SUBWAY_TRANSFER_X, SUBWAY_TRANSFER_Y, 1, SUBWAY_TRANSFER);
}

bool isContinuedStation(ref Script world, Sided end) {
    return end.holds(world, SUBWAY_RIM_X, DEEP_RIM, 1, SUBWAY_RIM) || end.holds(world, SUBWAY_RIM_X, SHALLOW_RIM, 1, SUBWAY_RIM);
}

int floorUp(ref Script world, Sided end, int z) {
    int y = LOWEST_BORE;
    while (y < HIGHEST_DOOR && end.isFilled(world, 0, y, z)) {
        y += 1;
    }
    return y;
}

bool isWellDoor(ref Script world, Sided end) {
    return world.game.world.graph.probeWorldPort(siteOf(end.site)) && (end.holds(world, 0, LOWEST_BORE, DOOR_Z + DOOR_RUN, SUBWAY_BALLAST) || end.holds(world, 0, SHALLOW_BALLAST, DOOR_Z + DOOR_RUN, SUBWAY_BALLAST)) && !end.isFilled(world, 0, floorUp(world, end, DOOR_Z), DOOR_Z);
}

bool isBesideStation(ref Script world, SiteFrame site, int rim) {
    Graph* graph = &world.game.world.graph;
    SiteFrame[2] beside = [graph.view.turnSite(site, Turn.right), graph.view.turnSite(site, Turn.left)];
    uint found = 0;
    foreach (way; beside) {
        foreach (mirror; MIRRORS) {
            if (isStation(world, Sided(way, mirror), rim)) {
                found += 1;
            }
        }
    }
    return found > 0;
}

bool isEntranceCorner(ref Script world, Sided end) {
    if (!isEntrance(world, end)) {
        return false;
    } else if (isStation(world, end, DEEP_RIM)) {
        return isBesideStation(world, end.site, DEEP_RIM);
    } else {
        return isStation(world, end, SHALLOW_RIM) && isBesideStation(world, end.site, SHALLOW_RIM);
    }
}

Maybe!Sided ensureSided(alias matches)(ref Script world) {
    Graph* graph = &world.game.world.graph;
    SiteFrame[MOST_PORT_SITES] sites;
    sites[0] = rootSite(graph.anchorSlot);
    size_t count = 1;
    size_t next = 0;
    Maybe!Sided found;
    while (!found.exists && next < count) {
        SiteFrame site = graph.view.moveToLevel(sites[next], 0);
        next += 1;
        world.game.generateWithin(ensureVertex(*graph, site), Length(SIDED_REACH));
        SiteFrame[4] ways = [site, graph.view.turnSite(site, Turn.right), graph.view.turnSite(graph.view.turnSite(site, Turn.right), Turn.right), graph.view.turnSite(site, Turn.left)];
        foreach (way; ways) {
            foreach (mirror; MIRRORS) {
                if (!found.exists && matches(world, Sided(way, mirror))) {
                    found = Maybe!Sided.of(Sided(way, mirror));
                }
            }
        }
        if (!found.exists && count + 3 <= MOST_PORT_SITES) {
            SiteFrame ahead = forwarded(site, 1);
            sites[count] = ahead;
            sites[count + 1] = graph.view.turnSite(ahead, Turn.left);
            sites[count + 2] = graph.view.turnSite(ahead, Turn.right);
            count += 3;
        }
    }
    return found;
}

Maybe!HorosphereId ensureMaze(ref Script world) {
    Graph* graph = &world.game.world.graph;
    SiteFrame turned = graph.view.turnSite(graph.view.turnSite(rootSite(graph.anchorSlot), Turn.left), Turn.left);
    SiteFrame site = graph.view.moveToLevel(forwarded(turned, MAZE_EDGES_AWAY), 0);
    world.check(graph.view.ensureRisingTag(siteOf(site), ROOT) == KindTag.of(MAZE_GROUND), "the vertex %d edges from spawn where the default world hangs its maze has none", MAZE_EDGES_AWAY);
    if (world.isFailed) {
        return Maybe!HorosphereId.init;
    } else {
        return graph.view.ensureHorosphereOver(site.node, site.corner, ROOT);
    }
}

Position ensureOnMaze(ref Graph graph, SiteFrame site, ColumnSpot spot) {
    Point!float point = sitePlacement(site, graph.layout) * columnPoint(graph.layout, spot);
    return graph.ensureNormalized(Position(graph.idAt(site.node), Shift!float.shiftTo(point)));
}

SiteFrame[4] waysAt(ref Graph graph, SiteFrame foot) {
    return [foot, graph.view.turnSite(foot, Turn.right), graph.view.turnSite(graph.view.turnSite(foot, Turn.right), Turn.right), graph.view.turnSite(foot, Turn.left)];
}

Maybe!Position ensureMazeDeck(ref Script world, HorosphereId maze) {
    Graph* graph = &world.game.world.graph;
    SiteFrame[4] ways = waysAt(*graph, graph.horospheres.horosphere(maze).foot);
    Maybe!Position found;
    size_t index = 0;
    while (!found.exists && index < ways.length) {
        found = nearestAround(world, (*graph).ensureOnMaze(ways[index], ColumnSpot(MAZE_ASIDE, MAZE_ASIDE, MAZE_ALONG)), materialNamed(MAZE_DECK));
        index += 1;
    }
    return found;
}

Maybe!Position ensurePort(ref Script world) {
    Maybe!SiteFrame site = ensurePortSite(world);
    if (site.exists) {
        return Maybe!Position.of(world.game.world.graph.ensureVertex(site.value));
    } else {
        return Maybe!Position.init;
    }
}

Maybe!SiteFrame ensurePortSite(ref Script world) {
    Graph* graph = &world.game.world.graph;
    SiteFrame[MOST_PORT_SITES] sites;
    sites[0] = rootSite(graph.anchorSlot);
    size_t count = 1;
    size_t next = 0;
    Maybe!SiteFrame found;
    while (!found.exists && next < count) {
        SiteFrame site = graph.view.moveToLevel(sites[next], 0);
        next += 1;
        bool port = (*graph).probeWorldPort(siteOf(site));
        if (port) {
            found = Maybe!SiteFrame.of(site);
        } else if (count + 3 <= MOST_PORT_SITES) {
            SiteFrame ahead = forwarded(site, 1);
            sites[count] = ahead;
            sites[count + 1] = graph.view.turnSite(ahead, Turn.left);
            sites[count + 2] = graph.view.turnSite(ahead, Turn.right);
            count += 3;
        }
    }
    return found;
}

void onSlope(ref Script world, double tilt, double heading) {
    world.plane(degrees(tilt));
    spawn(world);
    if (heading != 0) {
        world.turn(degrees(heading), degrees(0), TURN_SECONDS);
    }
    world.wait(SETTLE_SECONDS);
}

float forward(ref Script world, double seconds, float minFraction) {
    float start = world.traveled().value;
    world.press(seconds, Key.forward);
    float walked = world.traveled().value - start;
    float free = SPEED * seconds;
    const(char)[] facing = nameOf(world.targetMaterial());
    world.check(walked >= minFraction * free, "walked %.4f of an unobstructed %.4f, facing %.*s", walked, free, cast(int) facing.length, facing.ptr);
    return walked;
}

bool probeOnStep(ref Script world, float standing) {
    Maybe!Material below = lookBelow(world);
    return world.isOnGround() && world.altitude().value - standing > LEAST_BLOCK_EDGE / 2 && isMaterial(below, BUILD_LAYERS[0].material);
}

bool probeReached(ref Script world, ClimbGoal goal, float standing) {
    if (goal == ClimbGoal.ontoStep) {
        return probeOnStep(world, standing);
    } else {
        return false;
    }
}

void climbForward(ref Script world, double seconds, Time dt, ClimbGoal goal, float standing) {
    double deadline = world.time().value + seconds;
    world.hold(Key.forward);
    world.step(dt);
    bool reached = probeReached(world, goal, standing);
    while (!world.isFailed && world.time().value < deadline && !reached) {
        jumpIfBlocked(world);
        world.step(dt);
        reached = probeReached(world, goal, standing);
    }
    world.release(Key.forward, Key.up);
}

void jumpIfBlocked(ref Script world) {
    world.release(Key.up);
    if (world.isOnGround() && world.horizontalSpeed().value < BLOCKED_SPEED) {
        world.hold(Key.up);
    }
}

Motion motionFrom(ref Script world) {
    Motion motion;
    motion.lowest = world.altitude().value;
    motion.highest = motion.lowest;
    motion.lastFooting = world.footing();
    return motion;
}

void trackMotion(ref Script world, Motion* motion) {
    *motion = motionFrom(world);
    world.onStep(StepHook(&observeHook, motion));
}

void observeHook(ref Script world, void* context) {
    observe(world, *cast(Motion*) context);
}

void observe(ref Script world, ref Motion motion) {
    float speed = world.horizontalSpeed().value;
    float altitude = world.altitude().value;
    if (world.isOnGround()) {
        if (motion.lastFooting == Footing.airborne) {
            motion.cap = higherOf(SPEED, speed);
        }
        if (speed - motion.cap > motion.excess) {
            motion.excess = speed - motion.cap;
            motion.excessAt = world.time().value;
        }
        motion.cap = higherOf(SPEED, lowerOf(motion.cap, speed));
    } else {
        motion.offGround += 1;
    }
    motion.lastFooting = world.footing();
    motion.rise = higherOf(motion.rise, world.verticalSpeed().value);
    motion.lowest = lowerOf(motion.lowest, altitude);
    motion.highest = higherOf(motion.highest, altitude);
}

void checkSpeedLimit(ref Script world, ref const Motion motion) {
    world.claim(Topic.movement, "On the ground the body never moves faster than its walk speed, or than the speed it landed with.", motion.excess <= SPEED_TOLERANCE, Measure.of("largest excess", motion.excess), Measure.of("at second", motion.excessAt));
}

void checkOnStep(ref Script world, float standing, const(char)* what) {
    world.check(world.isOnGround(), "%s: on ground", what);
    float rise = world.altitude().value - standing;
    world.check(rise > LEAST_BLOCK_EDGE / 2, "%s: rose %.4f", what, rise);
    Maybe!Material below = lookBelow(world);
    const(char)[] name = nameOf(below);
    world.check(isMaterial(below, BUILD_LAYERS[0].material), "%s: standing on %.*s", what, cast(int) name.length, name.ptr);
}

void checkStanding(ref Script world, const(char)* what) {
    float altitude = world.altitude().value;
    world.check(world.isOnGround(), "%s: on ground", what);
    world.check(altitude - STANDING_ALTITUDE <= ALTITUDE_TOLERANCE && STANDING_ALTITUDE - altitude <= ALTITUDE_TOLERANCE, "%s: standing at altitude %.5f (expected %.5f)", what, altitude, STANDING_ALTITUDE);
}

void fly(ref Script world, float distance, Key key) {
    world.press(distance / FLY_SPEED, key);
}

void strafe(ref Script world, float distance) {
    if (distance > 0) {
        fly(world, distance, Key.right);
    } else if (distance < 0) {
        fly(world, -distance, Key.left);
    }
}

Key opposite(Key key) {
    if (key == Key.forward) {
        return Key.back;
    } else if (key == Key.back) {
        return Key.forward;
    } else if (key == Key.left) {
        return Key.right;
    } else {
        return Key.left;
    }
}

void buildLayer(ref Script world, string below, Key key, uint steps) {
    uint step = 0;
    while (step <= steps && !world.isFailed) {
        world.look(degrees(0), degrees(STRAIGHT_DOWN_DEGREES));
        if (isMaterial(world.targetMaterial(), below)) {
            bool placed = world.placeBlock();
            world.check(placed, "placed a block on %.*s %u steps along the row", cast(int) below.length, below.ptr, step);
        }
        world.look(degrees(0), degrees(-STRAIGHT_DOWN_DEGREES));
        if (step < steps) {
            fly(world, ROW_STEP, key);
        }
        step += 1;
    }
}

void buildRow(ref Script world, uint blocks, Key key, float length) {
    uint steps = cast(uint) ceil(length / ROW_STEP);
    string below = GROUND;
    foreach (layer; 0 .. blocks) {
        world.material(BUILD_LAYERS[layer].slot);
        buildLayer(world, below, key, steps);
        below = BUILD_LAYERS[layer].material;
        if (layer + 1 < blocks) {
            fly(world, steps * ROW_STEP, opposite(key));
        }
    }
    world.material(BUILD_LAYERS[0].slot);
}

void hover(ref Script world, uint blocks) {
    world.mode(MovementMode.fly);
    fly(world, WALL_HOVER_PER_BLOCK * blocks, Key.up);
}

void land(ref Script world) {
    world.step();
    world.mode(MovementMode.walk);
    world.wait(LANDING_SECONDS);
}

void buildWall(ref Script world, uint blocks) {
    hover(world, blocks);
    fly(world, WALL_DISTANCE, Key.forward);
    strafe(world, -WALL_HALF_WIDTH);
    buildRow(world, blocks, Key.right, 2 * WALL_HALF_WIDTH);
    strafe(world, -WALL_HALF_WIDTH);
    fly(world, WALL_DISTANCE, Key.back);
    land(world);
}

void buildStep(ref Script world) {
    hover(world, 1);
    fly(world, WALL_DISTANCE, Key.forward);
    strafe(world, -WALL_HALF_WIDTH);
    Key key = Key.right;
    uint rows = cast(uint) ceil(STEP_DEPTH / ROW_STEP);
    foreach (row; 0 .. rows + 1) {
        buildRow(world, 1, key, 2 * WALL_HALF_WIDTH);
        key = opposite(key);
        if (row < rows) {
            fly(world, ROW_STEP, Key.forward);
        }
    }
    if (key == Key.right) {
        strafe(world, WALL_HALF_WIDTH);
    } else {
        strafe(world, -WALL_HALF_WIDTH);
    }
    fly(world, WALL_DISTANCE + rows * ROW_STEP, Key.back);
    land(world);
}

void buildCorner(ref Script world, uint blocks) {
    hover(world, blocks);
    fly(world, WALL_DISTANCE, Key.forward);
    strafe(world, -WALL_HALF_WIDTH);
    buildRow(world, blocks, Key.right, 2 * WALL_HALF_WIDTH);
    buildRow(world, blocks, Key.back, WALL_DISTANCE);
    strafe(world, -WALL_HALF_WIDTH);
    land(world);
}

Across acrossSlope(ref Script world, double tilt, double heading, double seconds, float minFraction) {
    onSlope(world, tilt, heading);
    Motion motion;
    trackMotion(world, &motion);
    float start = world.altitude().value;
    float before = world.traveled().value;
    climbForward(world, seconds, world.timestep, ClimbGoal.timed, 0);
    float walked = world.traveled().value - before;
    float free = SPEED * seconds;
    const(char)[] facing = nameOf(world.targetMaterial());
    world.check(walked >= minFraction * free, "walked %.4f of an unobstructed %.4f, facing %.*s", walked, free, cast(int) facing.length, facing.ptr);
    world.wait(LANDING_SECONDS);
    world.onStep(StepHook.init);
    checkSpeedLimit(world, motion);
    world.check(world.isOnGround(), "on ground at the end");
    return Across(walked, world.altitude().value - start);
}
