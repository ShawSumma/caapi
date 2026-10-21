module plugins.rooms.layout;

import plugins.api.api : Api, Risen, Site, SitePart;
import blocks = plugins.blocks.blocks;
import plugins.buildings.building : SIDES, Side;
import plugins.rooms.levels : Biome, HallLayout, LAYERS, Level;
import plugins.rooms.rooms : Doors, Floor, Frame, Halls, MAZE_CELLS, Owns, Plan, Quarter, SEPARATION, Stair, frameOf, origin, paintFloor, stairs;
import plugins.turtle.turtle : FACE_CORNERS, Turtle, cornersOf, higherOf, upright;

enum int TOP_FLOOR = -2;
enum int GROUND = TOP_FLOOR + 1;
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

struct ForcedStair {
    ulong vertex;
    ulong face;
    uint upper;
    bool isPresent;
}

struct Root {
    ulong vertex;
    bool hasShaft;
    bool isRouted;
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
        floors[index] = Floor(cast(uint) index, base, index == 0);
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
        return blocks.roll(turtle.hash(SitePart.edge), HALL_SALT + index) >= GRID_DROPPED;
    }
}

bool isSolid(ulong face, ref const Level level, size_t index) {
    return blocks.roll(face, SOLID_SALT + index) < level.solid;
}

Doors lineDoors(ulong hash, size_t index, ref const Level level, bool isClosed) {
    if (level.isMaze) {
        int first = cast(int)(blocks.mixed(hash, SLOT_SALT + index) % MAZE_CELLS);
        Doors slots = Doors.one(first);
        if (blocks.roll(hash, SECOND_SALT + index) < SECOND_PASSAGE_ODDS) {
            slots.at[1] = cast(int)((first + 1 + blocks.mixed(hash, OFFSET_SALT + index) % (MAZE_CELLS - 1)) % MAZE_CELLS);
            slots.count = 2;
        }
        return slots;
    } else if (isClosed) {
        return Doors.init;
    } else if (blocks.roll(hash, MISSING_SALT + index) < level.missing) {
        return Doors([0, 0], 0, true);
    } else {
        return Doors.one(DOOR_LOW + cast(int)(blocks.mixed(hash, DOOR_SALT + index) % (DOOR_HIGH - DOOR_LOW + 1)));
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

bool stairOf(Turtle corner, ref const Root root, ref const Halls[FLOOR_COUNT] halls, bool isLobby, ref Stair stair) {
    ulong vertex = corner.hash(SitePart.vertex);
    ulong face = corner.hash(SitePart.face);
    ulong hash = vertex ^ face;
    uint upper = cast(uint)(blocks.mixed(hash, STAIR_SALT) % (FLOOR_COUNT - 1));
    bool isForced = root.forced.isPresent && vertex == root.forced.vertex && face == root.forced.face;
    if (isForced) {
        upper = root.forced.upper;
    }
    if (isLobby || (!isForced && blocks.roll(hash, STAIR_ODDS_SALT) >= FLOORS[upper].level.stairs)) {
        return false;
    } else {
        uint lower = upper + 1;
        int x = origin(halls[upper].x, FLOORS[upper].level);
        int otherX = origin(halls[lower].x, FLOORS[lower].level);
        int y = origin(halls[upper].y, FLOORS[upper].level);
        int otherY = origin(halls[lower].y, FLOORS[lower].level);
        stair = Stair(upper, lower, higherOf(x, otherX), higherOf(y, otherY), isForced);
        return true;
    }
}

Plan planOf(Turtle corner, ref const Quarter q, ref const Floor floor, size_t index, bool isSolidBlock, bool hasStair, Halls halls) {
    immutable(Level)* level = &floor.level();
    double chance = blocks.roll(corner.hash(SitePart.vertex) ^ corner.hash(SitePart.face), PLAN_SALT + index);
    if (level.isMaze) {
        return Plan.maze;
    } else if (q.isLobby && (floor.isTop || q.hasShaft)) {
        return Plan.lobby;
    } else if (hasStair) {
        return Plan.rooms;
    } else if (isSolidBlock) {
        return Plan.solid;
    } else if (chance < level.rings) {
        return Plan.rings;
    } else if (!halls.x && !halls.y && chance < level.rings + level.chapel) {
        return Plan.chapel;
    } else {
        return Plan.rooms;
    }
}

void quarter(Turtle corner, ref const Root root, ref const(Biome)*[FLOOR_COUNT] biomes) {
    ulong vertex = corner.hash(SitePart.vertex);
    ulong face = corner.hash(SitePart.face);
    bool isRoot = vertex == root.vertex;
    bool isLobby = isRoot || blocks.isRisingFrom(corner);
    Quarter q = Quarter(upright(corner), isLobby, isRoot && root.hasShaft);
    Owns owns = Owns(vertex > corner.forward(1).hash(SitePart.vertex), vertex > corner.right().forward(1).hash(SitePart.vertex));
    Halls[FLOOR_COUNT] halls;
    foreach (index; 0 .. FLOOR_COUNT) {
        halls[index] = Halls(isHall(corner.right(), root, FLOORS[index].level, index + 1), isHall(corner, root, FLOORS[index].level, index + 1));
    }
    Line[4] lines = linesOf(corner);
    Stair stair;
    bool hasStairAnywhere = stairOf(corner, root, halls, q.isLobby, stair);
    if (hasStairAnywhere && !stair.isForced && (isSolid(face, FLOORS[stair.upper].level, stair.upper + 1) || isSolid(face, FLOORS[stair.lower].level, stair.lower + 1))) {
        hasStairAnywhere = false;
    }
    Frame[FLOOR_COUNT] frames;
    foreach_reverse (index; 0 .. FLOOR_COUNT) {
        Floor floor = FLOORS[index];
        immutable(Level)* level = &floor.level();
        bool isMineSolid = isSolid(face, *level, index + 1);
        Doors[4] doors;
        foreach (side; SIDES) {
            doors[side] = lineDoors(lines[side].hash, index + 1, *level, isMineSolid || isSolid(lines[side].beyond, *level, index + 1));
        }
        bool hasStair = hasStairAnywhere && (stair.upper == index || stair.lower == index);
        Plan plan = planOf(corner, q, floor, index + 1, isMineSolid, hasStair, halls[index]);
        const(Stair)* floorStair = null;
        if (hasStair) {
            floorStair = &stair;
        }
        frames[index] = frameOf(q, halls[index], floor, biomes[index], floorStair, plan == Plan.lobby, owns);
        paintFloor(frames[index], doors, plan);
    }
    if (hasStairAnywhere) {
        stairs(frames[stair.lower], frames[stair.upper], stair, root.isRouted && stair.isForced);
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
        biomes[index] = &level.biomes[blocks.mixed(strongest, BIOME_SALT + index + 1) % level.biomes.length];
    }
    foreach (corner; corners) {
        quarter(corner, root, biomes);
    }
}
