module plugins.rooms.layout;

import plugins.api.api : Api, Risen, Site, SitePart;
import plugins.api.binding : bound, settingsOf;
import plugins.api.content : Content;
import blocks = plugins.blocks.blocks;
import plugins.buildings.building : SIDES, Side;
import plugins.connector.connector : Routing;
import plugins.rooms.levels : Biome, HallLayout, Level, MOST_LEVELS, Rooms, Tuning, rooms, tuning;
import plugins.rooms.rooms : Axis, Doors, Floor, Frame, Halls, MAZE_CELLS, MaybeLayer, Owns, Plan, Quarter, QuarterKind, SEPARATION, Stair, WallForm, frameOf, origin, paintFloor, stairs;
import plugins.turtle.turtle : FACE_CORNERS, Turtle, cornersOf, higherOf, mixed, roll, upright;

enum int DOOR_LOW = 3;
enum int DOOR_HIGH = 8;
enum ulong SLOT_SALT = 0x2F4A7C15;
enum ulong SECOND_SALT = 0x4F1BBCDD;
enum ulong OFFSET_SALT = 0x6B43A9B5;
enum ulong MISSING_SALT = 0x1F83D9AB;
enum ulong DOOR_SALT = 0x5BE0CD19;
enum ulong STAIR_SALT = 0x6A09E667;
enum ulong STAIR_ODDS_SALT = 0x510E527F;
enum ulong BIOME_SALT = 0x3C6EF372;
enum ulong HALL_SALT = 0x7F4A7C15;
enum ulong SOLID_SALT = 0x1B873593;
enum ulong PLAN_SALT = 0x5BD1E995;

enum Shaft : ubyte {
    none,
    open,
}

enum Passage : ubyte {
    open,
    closed,
}

struct ForcedStair {
    ulong vertex;
    ulong face;
    MaybeLayer upper;
}

struct Root {
    ulong vertex;
    Shaft shaft;
    Routing routing;
    ForcedStair forced;
}

struct Line {
    ulong hash;
    ulong beyond;
}

__gshared Floor[MOST_LEVELS] floors;

void resolveRooms(const(Content)* content) {
    blocks.resolveStreets(content);
    rooms = content.bound!Rooms("rooms:materials");
    tuning = content.settingsOf!Tuning("rooms");
    int base = rooms.ground.level - 1;
    foreach (index; 0 .. rooms.levels.count) {
        if (index > 0) {
            base = base - rooms.levels.items[index].room - SEPARATION - 2;
        }
        floors[index] = Floor(index, base);
    }
}

uint floorCount() {
    return rooms.levels.count;
}

bool probeHall(Turtle turtle, ref const Root root, ref const Level level, size_t index) {
    if (level.halls == HallLayout.none) {
        return false;
    } else if (level.halls == HallLayout.streets) {
        blocks.Root streets = blocks.Root(root.vertex);
        return blocks.probeStreet(turtle, streets);
    } else {
        ulong start = turtle.probeHash(SitePart.vertex);
        bool rooted = start == root.vertex;
        if (!rooted) {
            ulong end = turtle.forward(1).probeHash(SitePart.vertex);
            rooted = end == root.vertex;
        }
        if (!rooted) {
            double rolled = roll(turtle.probeHash(SitePart.edge), HALL_SALT + index);
            rooted = rolled >= tuning.gridDropped;
        }
        return rooted;
    }
}

bool isSolid(ulong face, ref const Level level, size_t index) {
    return roll(face, SOLID_SALT + index) < level.solid;
}

Doors lineDoors(ulong hash, size_t index, ref const Level level, Passage passage) {
    if (level.isMaze()) {
        int first = cast(int)(mixed(hash, SLOT_SALT + index) % MAZE_CELLS);
        Doors slots = Doors.one(first);
        if (roll(hash, SECOND_SALT + index) < tuning.secondPassageOdds) {
            slots.at[1] = cast(int)((first + 1 + mixed(hash, OFFSET_SALT + index) % (MAZE_CELLS - 1)) % MAZE_CELLS);
            slots.count = 2;
        }
        return slots;
    } else if (passage == Passage.closed) {
        return Doors.init;
    } else if (roll(hash, MISSING_SALT + index) < level.missing) {
        return Doors([0, 0], 0, WallForm.missing);
    } else {
        return Doors.one(DOOR_LOW + cast(int)(mixed(hash, DOOR_SALT + index) % (DOOR_HIGH - DOOR_LOW + 1)));
    }
}

Line[4] linesOf(Turtle corner) {
    ulong vertex = corner.probeHash(SitePart.vertex);
    ulong face = corner.probeHash(SitePart.face);
    ulong edgeY = corner.probeHash(SitePart.edge);
    ulong edgeX = corner.right().probeHash(SitePart.edge);
    Line[4] lines;
    lines[Side.yLow] = Line(edgeY ^ vertex, corner.left().probeHash(SitePart.face));
    lines[Side.xLow] = Line(edgeX ^ vertex, corner.right().probeHash(SitePart.face));
    lines[Side.xHigh] = Line(edgeY ^ face, face);
    lines[Side.yHigh] = Line(edgeX ^ face, face);
    return lines;
}

bool probeForcedStair(Turtle corner, ref const Root root) {
    if (root.forced.upper.exists) {
        ulong vertex = corner.probeHash(SitePart.vertex);
        ulong face = corner.probeHash(SitePart.face);
        return vertex == root.forced.vertex && face == root.forced.face;
    } else {
        return false;
    }
}

Stair stairOf(Turtle corner, ref const Root root, ref const Halls[MOST_LEVELS] halls, ref const Quarter q) {
    ulong hash = corner.probeHash(SitePart.vertex) ^ corner.probeHash(SitePart.face);
    uint upper = cast(uint)(mixed(hash, STAIR_SALT) % (floorCount() - 1));
    bool forced = probeForcedStair(corner, root);
    if (forced) {
        upper = root.forced.upper.value;
    }
    if (q.isLobby() || (!forced && roll(hash, STAIR_ODDS_SALT) >= floors[upper].level.stairs)) {
        return Stair.init;
    } else {
        uint lower = upper + 1;
        int x = origin(halls[upper], Axis.x, floors[upper].level);
        int otherX = origin(halls[lower], Axis.x, floors[lower].level);
        int y = origin(halls[upper], Axis.y, floors[upper].level);
        int otherY = origin(halls[lower], Axis.y, floors[lower].level);
        return Stair(MaybeLayer.of(upper), lower, higherOf(x, otherX), higherOf(y, otherY));
    }
}

Plan planOf(Turtle corner, ref const Quarter q, ref const Stair stair, ref const Floor floor, size_t index, Halls halls) {
    const(Level)* level = &floor.level();
    double chance = roll(corner.probeHash(SitePart.vertex) ^ corner.probeHash(SitePart.face), PLAN_SALT + index);
    ulong face = corner.probeHash(SitePart.face);
    if (level.isMaze()) {
        return Plan.maze;
    } else if (q.isLobby() && (floor.isTop() || q.hasShaft())) {
        return Plan.lobby;
    } else if (stair.isOn(floor.layer)) {
        return Plan.rooms;
    } else if (isSolid(face, *level, index)) {
        return Plan.solid;
    } else if (chance < level.rings) {
        return Plan.rings;
    } else if (!halls.has(Axis.x) && !halls.has(Axis.y) && chance < level.rings + level.chapel) {
        return Plan.chapel;
    } else {
        return Plan.rooms;
    }
}

void quarter(Turtle corner, ref const Root root, ref const(Biome)*[MOST_LEVELS] biomes) {
    ulong vertex = corner.probeHash(SitePart.vertex);
    ulong face = corner.probeHash(SitePart.face);
    QuarterKind kind = QuarterKind.plain;
    if (vertex == root.vertex && root.shaft == Shaft.open) {
        kind = QuarterKind.lobbyWithShaft;
    } else {
        bool lobby = vertex == root.vertex;
        if (!lobby) {
            lobby = corner.probeRising().exists;
        }
        if (lobby) {
            kind = QuarterKind.lobby;
        }
    }
    Quarter q = Quarter(upright(corner), kind);
    Owns owns;
    owns.put(Side.xHigh, vertex > corner.forward(1).probeHash(SitePart.vertex));
    owns.put(Side.yHigh, vertex > corner.right().forward(1).probeHash(SitePart.vertex));
    Halls[MOST_LEVELS] halls;
    foreach (index; 0 .. floorCount()) {
        bool hallX = probeHall(corner.right(), root, floors[index].level, index + 1);
        bool hallY = probeHall(corner, root, floors[index].level, index + 1);
        halls[index].put(Axis.x, hallX);
        halls[index].put(Axis.y, hallY);
    }
    Line[4] lines = linesOf(corner);
    Stair stair = stairOf(corner, root, halls, q);
    bool forced = probeForcedStair(corner, root);
    if (stair.isPresent() && !forced && (isSolid(face, floors[stair.upper.value].level, stair.upper.value + 1) || isSolid(face, floors[stair.lower].level, stair.lower + 1))) {
        stair = Stair.init;
    }
    Frame[MOST_LEVELS] frames;
    foreach_reverse (index; 0 .. floorCount()) {
        Floor floor = floors[index];
        const(Level)* level = &floor.level();
        Doors[4] doors;
        foreach (side; SIDES) {
            Passage passage = Passage.open;
            if (isSolid(face, *level, index + 1) || isSolid(lines[side].beyond, *level, index + 1)) {
                passage = Passage.closed;
            }
            doors[side] = lineDoors(lines[side].hash, index + 1, *level, passage);
        }
        Plan plan = planOf(corner, q, stair, floor, index + 1, halls[index]);
        frames[index] = frameOf(q, halls[index], floor, biomes[index], stair, plan, owns);
        paintFloor(frames[index], doors, plan);
    }
    if (stair.isPresent()) {
        Routing routing = Routing.unrouted;
        if (root.routing == Routing.routed && forced) {
            routing = Routing.routed;
        }
        stairs(frames[stair.lower], frames[stair.upper.value], stair, routing);
    }
}

void tile(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    tileAt(Turtle(api, site), *cast(const(Root)*) data);
}

void tileAt(Turtle face, ref const Root root) {
    Turtle[FACE_CORNERS] corners = cornersOf(face);
    ulong strongest = face.probeHash(SitePart.face);
    foreach (corner; corners) {
        strongest = higherOf(corner.left().probeHash(SitePart.face), strongest);
    }
    const(Biome)*[MOST_LEVELS] biomes;
    foreach (index; 0 .. floorCount()) {
        const(Level)* level = &floors[index].level();
        biomes[index] = &level.biomes.items[mixed(strongest, BIOME_SALT + index + 1) % level.biomes.count];
    }
    foreach (corner; corners) {
        quarter(corner, root, biomes);
    }
}
