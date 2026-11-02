module plugins.rooms.layout;

import plugins.api.api : Api, Risen, Site, SitePart;
import blocks = plugins.blocks.blocks;
import plugins.buildings.building : SIDES, Side;
import plugins.connector.connector : BACKROOMS_GROUND, Routing;
import plugins.rooms.levels : Biome, HallLayout, LAYERS, Level;
import plugins.rooms.rooms : Axis, Doors, Floor, Frame, Halls, MAZE_CELLS, NO_STAIR, Owns, Plan, Quarter, QuarterKind, SEPARATION, Stair, WallForm, frameOf, origin, paintFloor, stairs;
import plugins.turtle.turtle : FACE_CORNERS, Turtle, cornersOf, higherOf, mixed, roll, upright;

enum int TOP_FLOOR = BACKROOMS_GROUND - 1;
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
enum double GRID_DROPPED = 0.12;
enum double SECOND_PASSAGE_ODDS = 0.5;
enum size_t FLOOR_COUNT = LAYERS.length;

enum Shaft : ubyte {
    none,
    open,
}

struct ForcedStair {
    ulong vertex;
    ulong face;
    uint upper = NO_STAIR;
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

Floor[FLOOR_COUNT] floorsOf() {
    Floor[FLOOR_COUNT] floors;
    int base = TOP_FLOOR;
    foreach (index; 0 .. FLOOR_COUNT) {
        if (index > 0) {
            base = base - LAYERS[index].room - SEPARATION - 2;
        }
        floors[index] = Floor(cast(uint) index, base);
    }
    return floors;
}

immutable Floor[FLOOR_COUNT] FLOORS = floorsOf();

bool isHall(Turtle turtle, ref const Root root, ref const Level level, size_t index) {
    if (level.halls == HallLayout.none) {
        return false;
    } else if (level.halls == HallLayout.streets) {
        blocks.Root streets = blocks.Root(root.vertex);
        return blocks.isStreet(turtle, streets);
    } else if (turtle.hash(SitePart.vertex) == root.vertex || turtle.forward(1).hash(SitePart.vertex) == root.vertex) {
        return true;
    } else {
        return roll(turtle.hash(SitePart.edge), HALL_SALT + index) >= GRID_DROPPED;
    }
}

bool isSolid(ulong face, ref const Level level, size_t index) {
    return roll(face, SOLID_SALT + index) < level.solid;
}

Doors lineDoors(ulong hash, size_t index, ref const Level level, bool isClosed) {
    if (level.isMaze()) {
        int first = cast(int)(mixed(hash, SLOT_SALT + index) % MAZE_CELLS);
        Doors slots = Doors.one(first);
        if (roll(hash, SECOND_SALT + index) < SECOND_PASSAGE_ODDS) {
            slots.at[1] = cast(int)((first + 1 + mixed(hash, OFFSET_SALT + index) % (MAZE_CELLS - 1)) % MAZE_CELLS);
            slots.count = 2;
        }
        return slots;
    } else if (isClosed) {
        return Doors.init;
    } else if (roll(hash, MISSING_SALT + index) < level.missing) {
        return Doors([0, 0], 0, WallForm.missing);
    } else {
        return Doors.one(DOOR_LOW + cast(int)(mixed(hash, DOOR_SALT + index) % (DOOR_HIGH - DOOR_LOW + 1)));
    }
}

Line[4] linesOf(Turtle corner) {
    ulong vertex = corner.hash(SitePart.vertex);
    ulong face = corner.hash(SitePart.face);
    ulong edgeY = corner.hash(SitePart.edge);
    ulong edgeX = corner.right().hash(SitePart.edge);
    Line[4] lines;
    lines[Side.yLow] = Line(edgeY ^ vertex, corner.left().hash(SitePart.face));
    lines[Side.xLow] = Line(edgeX ^ vertex, corner.right().hash(SitePart.face));
    lines[Side.xHigh] = Line(edgeY ^ face, face);
    lines[Side.yHigh] = Line(edgeX ^ face, face);
    return lines;
}

bool isForcedStair(Turtle corner, ref const Root root) {
    return root.forced.upper != NO_STAIR && corner.hash(SitePart.vertex) == root.forced.vertex && corner.hash(SitePart.face) == root.forced.face;
}

Stair stairOf(Turtle corner, ref const Root root, ref const Halls[FLOOR_COUNT] halls, ref const Quarter q) {
    ulong hash = corner.hash(SitePart.vertex) ^ corner.hash(SitePart.face);
    uint upper = cast(uint)(mixed(hash, STAIR_SALT) % (FLOOR_COUNT - 1));
    if (isForcedStair(corner, root)) {
        upper = root.forced.upper;
    }
    if (q.isLobby() || (!isForcedStair(corner, root) && roll(hash, STAIR_ODDS_SALT) >= FLOORS[upper].level.stairs)) {
        return Stair.init;
    } else {
        uint lower = upper + 1;
        int x = origin(halls[upper], Axis.x, FLOORS[upper].level);
        int otherX = origin(halls[lower], Axis.x, FLOORS[lower].level);
        int y = origin(halls[upper], Axis.y, FLOORS[upper].level);
        int otherY = origin(halls[lower], Axis.y, FLOORS[lower].level);
        return Stair(upper, lower, higherOf(x, otherX), higherOf(y, otherY));
    }
}

Plan planOf(Turtle corner, ref const Quarter q, ref const Stair stair, ref const Floor floor, size_t index, Halls halls) {
    immutable(Level)* level = &floor.level();
    double chance = roll(corner.hash(SitePart.vertex) ^ corner.hash(SitePart.face), PLAN_SALT + index);
    if (level.isMaze()) {
        return Plan.maze;
    } else if (q.isLobby() && (floor.isTop() || q.hasShaft())) {
        return Plan.lobby;
    } else if (stair.isOn(floor.layer)) {
        return Plan.rooms;
    } else if (isSolid(corner.hash(SitePart.face), *level, index)) {
        return Plan.solid;
    } else if (chance < level.rings) {
        return Plan.rings;
    } else if (!halls.has(Axis.x) && !halls.has(Axis.y) && chance < level.rings + level.chapel) {
        return Plan.chapel;
    } else {
        return Plan.rooms;
    }
}

void quarter(Turtle corner, ref const Root root, ref const(Biome)*[FLOOR_COUNT] biomes) {
    ulong vertex = corner.hash(SitePart.vertex);
    ulong face = corner.hash(SitePart.face);
    QuarterKind kind = QuarterKind.plain;
    if (vertex == root.vertex && root.shaft == Shaft.open) {
        kind = QuarterKind.lobbyWithShaft;
    } else if (vertex == root.vertex || blocks.isRisingFrom(corner)) {
        kind = QuarterKind.lobby;
    }
    Quarter q = Quarter(upright(corner), kind);
    Owns owns;
    owns.put(Side.xHigh, vertex > corner.forward(1).hash(SitePart.vertex));
    owns.put(Side.yHigh, vertex > corner.right().forward(1).hash(SitePart.vertex));
    Halls[FLOOR_COUNT] halls;
    foreach (index; 0 .. FLOOR_COUNT) {
        halls[index].put(Axis.x, isHall(corner.right(), root, FLOORS[index].level, index + 1));
        halls[index].put(Axis.y, isHall(corner, root, FLOORS[index].level, index + 1));
    }
    Line[4] lines = linesOf(corner);
    Stair stair = stairOf(corner, root, halls, q);
    if (stair.isPresent() && !isForcedStair(corner, root) && (isSolid(face, FLOORS[stair.upper].level, stair.upper + 1) || isSolid(face, FLOORS[stair.lower].level, stair.lower + 1))) {
        stair = Stair.init;
    }
    Frame[FLOOR_COUNT] frames;
    foreach_reverse (index; 0 .. FLOOR_COUNT) {
        Floor floor = FLOORS[index];
        immutable(Level)* level = &floor.level();
        Doors[4] doors;
        foreach (side; SIDES) {
            doors[side] = lineDoors(lines[side].hash, index + 1, *level, isSolid(face, *level, index + 1) || isSolid(lines[side].beyond, *level, index + 1));
        }
        Plan plan = planOf(corner, q, stair, floor, index + 1, halls[index]);
        frames[index] = frameOf(q, halls[index], floor, biomes[index], stair, plan, owns);
        paintFloor(frames[index], doors, plan);
    }
    if (stair.isPresent()) {
        stairs(frames[stair.lower], frames[stair.upper], stair, root.routing == Routing.routed && isForcedStair(corner, root));
    }
}

void tile(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    tileAt(Turtle(api, site), *cast(const(Root)*) data);
}

void tileAt(Turtle face, ref const Root root) {
    Turtle[FACE_CORNERS] corners = cornersOf(face);
    ulong strongest = face.hash(SitePart.face);
    foreach (corner; corners) {
        strongest = higherOf(corner.left().hash(SitePart.face), strongest);
    }
    const(Biome)*[FLOOR_COUNT] biomes;
    foreach (index; 0 .. FLOOR_COUNT) {
        immutable(Level)* level = &FLOORS[index].level();
        biomes[index] = &level.biomes[mixed(strongest, BIOME_SALT + index + 1) % level.biomes.length];
    }
    foreach (corner; corners) {
        quarter(corner, root, biomes);
    }
}
