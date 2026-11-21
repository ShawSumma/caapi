module plugins.library.plugin;

import core.stdc.math : ceil;
import plugins.api.api : Api, HorosphereForm, KindId, KindTag, Material, MaybeIndex, Registry, Rhythm, Risen, RisingKind, Site, SitePart, Span, Spot, entryOf, tagNamed;
import plugins.api.binding : List, bound, settingsOf;
import plugins.api.content : BASE, Content, Dependency, FIRST_VERSION, Manifest, dependencyOn;
import blocks = plugins.blocks.blocks;
import plugins.connector.connector : Connection, HALF_WIDTH, Routing, Style, footTile, resolveConnector;
import plugins.turtle.turtle : Along, Cell, EVERY_HEIGHT, Offset, Rows, STAIR_HEADROOM, TURN_TREADS, Turtle, boxOf, cornersOf, floorDiv, floorMod, higherOf, line, lowerOf, mixed, negated, onWedge, ringRows, roll, treadSpan, upright, wedgeRows;

enum string LOOK = "library:look";

enum int STORY = 6;
enum int CEILING_AT = STORY - 1;
enum int HALL_STORY = 2 * STORY;
enum int BOTTOM = -12;
enum int ROOF = 11;
enum int LOWEST_FLIGHT = -2;
enum int HIGHEST_FLIGHT = 0;
enum int PIER = 3;
enum int DOOR = 2;
enum int CLEAR = 6;
enum Cell LAMP = Cell(10, 4);
enum Span TABLE_X = Span(3, 8);
enum Span TABLE_Y = Span(5, 6);
enum int BALCONY = 3;
enum int DESK = 8;
enum int PARTITION = 6;
enum int STUDY_DOOR = 3;
enum Span LOUNGE_SHELF = Span(3, 8);
enum Span LOUNGE_TABLE_X = Span(4, 5);
enum Span LOUNGE_TABLE_Y = Span(9, 10);
enum Span LOCKERS_X = Span(3, 8);
enum int LOCKERS_Y = 1;
enum int LOCKER_HEIGHT = 2;
enum int COUNTER_X = 1;
enum Span COUNTER_Y = Span(4, 8);
enum int SINK_Y = 6;
enum ulong STUDY_SALT = 0x452821E6;
enum ulong LOOP_SALT = 0x38D01377;
enum ulong STATION_SALT = 0x5851F42D;
enum ulong BENCH_SALT = 0x2545F491;
enum int STORIES = (ROOF - BOTTOM + 1) / STORY;
enum int HALL_STORIES = (ROOF - BOTTOM + 1) / HALL_STORY;
immutable Cell[4] STUDY_DOORS = [Cell(PARTITION, 3), Cell(PARTITION, 9), Cell(3, PARTITION), Cell(9, PARTITION)];
immutable Cell[4] STUDY_DESKS = [Cell(2, 2), Cell(8, 2), Cell(2, 8), Cell(8, 8)];
immutable Cell[3] STUDY_LAMPS = [Cell(3, 3), Cell(3, 9), Cell(9, 9)];
immutable int[2] LOUNGE_ROWS = [3, 6];
enum double SHAFT_SHARE = 2;
enum ulong KIND_SALT = 0x3B9ACA07;
enum ulong FLOOR_SALT = 0x7F4A7C15;
enum ulong WALL_SALT = 0x1B873593;
enum uint LIBRARY_TAG = tagNamed("library:library");
enum uint STACKS_TAG = tagNamed("library:stacks");
enum size_t MOST_CHOICES = 16;
immutable Rhythm[2] WALL_BOOKS = [Rhythm(2 * STORY, 2, 2), Rhythm(2 * STORY, STORY + 2, 2)];
immutable Connection ROLLED = Connection.rolled();

enum double WELL = 4.5;
enum double STAIR_OUT = 8.5;
enum double SHELF = 10.5;
enum double RIM = 12;
enum double EVERYWHERE = 100;
enum double ROUTE_RADIUS = 7;
enum int TOP_TREAD = STORY;
enum int ROUTE_TREADS = 20 * TURN_TREADS;
enum int LAMP_SPOT = 6;
enum double WALLED_PAST_CRUST = 0.5;
immutable Spot SPAWN = Spot(10, 7, 1);

enum int MAIN_STORY = -BOTTOM / STORY;
enum int ROOM_WALL = 8;
enum Span ROOM = Span(1, ROOM_WALL - 1);
enum Span ROOM_DOOR = Span(4, 5);
enum int ROOM_DOOR_TOP = 3;
enum int ROOM_HEADROOM = STORY - 2;
enum Cell ROOM_LAMP = Cell(4, 4);
enum int DESCENT_FROM = 2;
enum Span DESCENT_Y = Span(2, 3);
enum Span BASEMENT_ROW = Span(3, 4);
enum int PIPE_BELOW_CEILING = 1;
immutable int[2] PIPE_ROWS = [2, 7];
enum size_t MOST_ROOMS = 24;
enum size_t MOST_PIECES = 12;
enum uint PICK_STEPS = 1000;
enum ulong ROOM_SALT = 0x6C62272E;
enum ulong ROOM_PICK_SALT = 0x07BB0142;
enum ulong ROOM_LOOP_SALT = 0x62B82175;
enum ulong ROOM_DOOR_SALT = 0x6A5D39EA;
enum ulong SIDE_SALT = 0x51DE0000;
enum int SIDE_WALL = 7;
enum int SIDE_EDGE = 11;
enum Span SIDE = Span(SIDE_WALL + 1, SIDE_EDGE - 1);
immutable Cell[4] SIDE_SIGNS = [Cell(1, 1), Cell(1, -1), Cell(-1, 1), Cell(-1, -1)];
immutable Rhythm LOCULI = Rhythm(STORY, 2, 2);

enum Level : ubyte {
    main,
    basement,
    niche,
    crypt,
}

enum Zone : ubyte {
    stacks,
    catacombs,
}

enum Descent : ubyte {
    none,
    down,
}

struct Piece {
    Material material;
    int x;
    int y;
    int z;
    int wide;
    int deep;
    int tall;
}

struct Room {
    double weight;
    Level level;
    Material wall;
    Material floor;
    Material light;
    Descent stair;
    List!(Piece, MOST_PIECES) pieces;
}

struct Materials {
    Material frame;
    Material ceiling;
    Material lamp;
    Material table;
    Material stair;
    Material well;
    Material partition;
    Material lounge;
    Material press;
    Material lab;
    Material bench;
    Material locker;
    Material sink;
    Material workbench;
    Material staffFloor;
    Material staffCeiling;
    Material staffWall;
    Material catalog;
    Material pipe;
    Material crypt;
    List!(Material, MOST_CHOICES) floors;
    List!(Material, MOST_CHOICES) books;
    List!(Material, MOST_CHOICES) loculi;
    List!(Room, MOST_ROOMS) rooms;
}

__gshared Materials materials;

struct Tuning {
    double riseOdds;
    double shaftOdds;
    double hallOdds;
    double stairOdds;
    double atriumOdds;
    double studyOdds;
    double loungeOdds;
    double staffOdds;
    double loopOdds;
    double arcadeOdds;
    double solidOdds;
    double stationLots;
    double pressLots;
    double labLots;
    double benchLots;
    double fog;
    int spiralBelow;
    double roomOdds;
    double basementRoomOdds;
    double roomLoopOdds;
    double nicheOdds;
    int stackEdges;
}

__gshared Tuning tuning;

void resolve(const(Content)* content) {
    resolveConnector(content);
    materials = content.bound!Materials("library:materials");
    tuning = content.settingsOf!Tuning("library");
}

Material floorOf(ulong hash) {
    return materials.floors.items[cast(size_t)(roll(hash, FLOOR_SALT) * materials.floors.count)];
}

Material bookOf(Turtle tower) {
    return materials.books.items[tower.pick(materials.books.count)];
}

enum Kind : ubyte {
    gallery,
    hall,
    stair,
    atrium,
    studies,
    lounge,
    staff,
}

enum Wall : ubyte {
    door,
    arcade,
    solid,
}

enum Clearing : ubyte {
    built,
    clear,
}

struct Quarter {
    Turtle tower;
    Clearing clearing;

    bool isClear() const {
        return clearing == Clearing.clear;
    }
}

Clearing clearingAt(Turtle corner, ref const Risen risen) {
    bool clear = blocks.probeTaken(corner, risen);
    if (clear) {
        return Clearing.clear;
    } else {
        return Clearing.built;
    }
}

Kind kindOf(ulong face) {
    double chance = roll(face, KIND_SALT);
    if (chance < tuning.hallOdds) {
        return Kind.hall;
    } else if (chance < tuning.hallOdds + tuning.stairOdds) {
        return Kind.stair;
    } else if (chance < tuning.hallOdds + tuning.stairOdds + tuning.atriumOdds) {
        return Kind.atrium;
    } else if (chance < tuning.hallOdds + tuning.stairOdds + tuning.atriumOdds + tuning.studyOdds) {
        return Kind.studies;
    } else if (chance < tuning.hallOdds + tuning.stairOdds + tuning.atriumOdds + tuning.studyOdds + tuning.loungeOdds) {
        return Kind.lounge;
    } else if (chance < tuning.hallOdds + tuning.stairOdds + tuning.atriumOdds + tuning.studyOdds + tuning.loungeOdds + tuning.staffOdds) {
        return Kind.staff;
    } else {
        return Kind.gallery;
    }
}

Wall wallOf(ulong edge) {
    double chance = roll(edge, WALL_SALT);
    if (chance < tuning.arcadeOdds) {
        return Wall.arcade;
    } else if (chance < tuning.arcadeOdds + tuning.solidOdds) {
        return Wall.solid;
    } else {
        return Wall.door;
    }
}

void spread(ref const Quarter q, Material material, Span z, Rhythm rhythm) {
    int far = q.tower.column().high;
    if (!q.isClear()) {
        q.tower.paint(material, boxOf(Span(0, far), Span(0, far), z), rhythm);
    } else {
        if (z.low <= 0) {
            q.tower.paint(material, boxOf(Span(0, far), Span(0, far), Span(z.low, lowerOf(z.high, 0))), rhythm);
        }
        if (z.high > 0) {
            Span open = Span(higherOf(z.low, 1), z.high);
            q.tower.paint(material, boxOf(Span(HALF_WIDTH, far), Span(0, far), open), rhythm);
            q.tower.paint(material, boxOf(Span(0, HALF_WIDTH - 1), Span(HALF_WIDTH, far), open), rhythm);
        }
    }
}

void shelves(Turtle tower, Along direction, Span span, Span z) {
    tower.paint(materials.frame, line(direction, span, z));
    foreach (along; span.low .. span.high + 1) {
        foreach (row; WALL_BOOKS) {
            tower.paint(bookOf(tower), line(direction, Span(along, along), z), row);
        }
    }
}

void wall(Turtle tower, Along direction, ulong edge) {
    int far = tower.column().high;
    Span rooms = Span(BOTTOM + 1, ROOF - 1);
    final switch (wallOf(edge)) {
        case Wall.door:
            shelves(tower, direction, Span(0, far - DOOR), rooms);
            break;
        case Wall.arcade:
            shelves(tower, direction, Span(0, PIER - 1), rooms);
            break;
        case Wall.solid:
            shelves(tower, direction, Span(0, far), rooms);
            break;
    }
}

void closeEdge(Turtle tower, Along direction, ulong edge, Span z) {
    if (wallOf(edge) == Wall.arcade) {
        shelves(tower, direction, Span(PIER, ROOM_WALL), z);
    }
}

void stack(Turtle tower, Span x, Span y, Span z) {
    tower.paint(materials.frame, boxOf(x, y, z), Rhythm(STORY, 1, 3));
    tower.paint(bookOf(tower), boxOf(x, y, z), Rhythm(STORY, 2, 1));
}

bool isEligible(ref const Room room, Level level, int story) {
    return room.level == level && (room.stair == Descent.none || story > 0);
}

Level levelOf(int story) {
    if (story < MAIN_STORY) {
        return Level.basement;
    } else {
        return Level.main;
    }
}

double roomOddsOf(Level level) {
    final switch (level) {
        case Level.main:
            return tuning.roomOdds;
        case Level.basement:
            return tuning.basementRoomOdds;
        case Level.niche:
        case Level.crypt:
            return tuning.nicheOdds;
    }
}

MaybeIndex!Room roomAt(ulong hash, int story) {
    return roomIn(hash, levelOf(story), story);
}

MaybeIndex!Room roomIn(ulong hash, Level level, int story) {
    const(Room)[] rooms = materials.rooms.slice();
    double total = 0;
    foreach (ref room; rooms) {
        if (isEligible(room, level, story)) {
            total += room.weight;
        }
    }
    if (!(roll(hash, ROOM_SALT) < roomOddsOf(level)) || !(total > 0)) {
        return MaybeIndex!Room.init;
    } else {
        double left = (mixed(hash, ROOM_PICK_SALT) % PICK_STEPS) / cast(double) PICK_STEPS * total;
        uint index = 0;
        while (index < rooms.length && !(isEligible(rooms[index], level, story) && left < rooms[index].weight)) {
            if (isEligible(rooms[index], level, story)) {
                left -= rooms[index].weight;
            }
            index += 1;
        }
        if (index < rooms.length) {
            return MaybeIndex!Room.of(index);
        } else {
            return MaybeIndex!Room.init;
        }
    }
}

void descend(Turtle tower, int floor) {
    int below = floor - STORY;
    foreach (step; 0 .. STORY - 1) {
        int x = DESCENT_FROM + step;
        int top = floor - 1 - step;
        tower.paint(Material.none, boxOf(Span(x, x), DESCENT_Y, Span(top + 1, top + ROOM_HEADROOM)));
        tower.paint(materials.stair, boxOf(Span(x, x), DESCENT_Y, Span(below + 1, top)));
    }
    int landing = DESCENT_FROM + STORY - 1;
    tower.paint(Material.none, boxOf(Span(landing, landing), DESCENT_Y, Span(below + 1, below + ROOM_HEADROOM)));
}

void room(Turtle tower, ref const Room made, int story, ulong hash, ulong edgeX, ulong edgeY) {
    int floor = BOTTOM + story * STORY;
    Span inside = Span(floor + 1, floor + ROOM_HEADROOM);
    Span inner = Span(ROOM_WALL, ROOM_WALL);
    tower.paint(Material.none, boxOf(ROOM, ROOM, inside));
    if (made.floor != Material.none) {
        tower.paint(made.floor, boxOf(ROOM, ROOM, Span(floor, floor)));
    }
    tower.paint(made.wall, boxOf(inner, Span(0, ROOM_WALL), inside));
    tower.paint(made.wall, boxOf(Span(0, ROOM_WALL - 1), inner, inside));
    closeEdge(tower, Along.x, edgeX, inside);
    closeEdge(tower, Along.y, edgeY, inside);
    Span door = Span(floor + 1, floor + ROOM_DOOR_TOP);
    ulong first = mixed(hash, ROOM_DOOR_SALT) % 2;
    bool looped = roll(hash, ROOM_LOOP_SALT) < tuning.roomLoopOdds;
    if (looped || first == 0) {
        tower.paint(Material.none, boxOf(inner, ROOM_DOOR, door));
    }
    if (looped || first == 1) {
        tower.paint(Material.none, boxOf(ROOM_DOOR, inner, door));
    }
    foreach (ref piece; made.pieces.slice()) {
        Material material = piece.material;
        if (material == Material.none) {
            material = bookOf(tower);
        }
        Span x = Span(piece.x, lowerOf(piece.x + piece.wide - 1, ROOM.high));
        Span y = Span(piece.y, lowerOf(piece.y + piece.deep - 1, ROOM.high));
        Span z = Span(floor + piece.z, lowerOf(floor + piece.z + piece.tall - 1, floor + ROOM_HEADROOM));
        tower.paint(material, boxOf(x, y, z));
    }
    if (made.light != Material.none) {
        tower.paint(made.light, boxOf(Span(ROOM_LAMP.x, ROOM_LAMP.x), Span(ROOM_LAMP.y, ROOM_LAMP.y), Span(floor + CEILING_AT, floor + CEILING_AT)));
    }
    if (made.stair == Descent.down) {
        descend(tower, floor);
    }
}

void divide(Turtle tower, Turtle corner) {
    ulong hash = quarterHash(corner);
    ulong edgeX = corner.probeHash(SitePart.edge);
    ulong edgeY = corner.right().probeHash(SitePart.edge);
    foreach (story; 0 .. STORIES) {
        ulong own = mixed(hash, ROOM_SALT + story);
        MaybeIndex!Room chosen = roomAt(own, story);
        if (chosen.exists) {
            room(tower, materials.rooms.items[chosen.value], story, own, edgeX, edgeY);
        }
    }
}

void basement(Turtle tower) {
    int far = tower.column().high;
    Span below = Span(BOTTOM, BOTTOM + MAIN_STORY * STORY - 1);
    stack(tower, Span(3, 7), BASEMENT_ROW, below);
    foreach (row; PIPE_ROWS) {
        tower.paint(materials.pipe, boxOf(Span(1, far), Span(row, row), below), Rhythm(STORY, CEILING_AT - PIPE_BELOW_CEILING, 1));
    }
}

bool hasRooms(Kind kind, size_t index) {
    return kind == Kind.gallery || (kind == Kind.stair && index != 0);
}

ulong quarterHash(Turtle corner) {
    return corner.probeHash(SitePart.vertex) ^ corner.probeHash(SitePart.face);
}

void floors(ref const Quarter q, Kind kind, Material material, Turtle corner) {
    Span whole = Span(BOTTOM, ROOF);
    int story = STORY;
    if (kind == Kind.hall) {
        story = HALL_STORY;
    }
    Material ceiling = materials.ceiling;
    if (kind == Kind.staff) {
        ceiling = materials.staffCeiling;
    }
    spread(q, Material.none, Span(BOTTOM + 1, ROOF - 1), EVERY_HEIGHT);
    spread(q, material, whole, Rhythm(story, 0, 1));
    spread(q, ceiling, whole, Rhythm(story, story - 1, 1));
    q.tower.paint(materials.lamp, boxOf(Span(LAMP.x, LAMP.x), Span(LAMP.y, LAMP.y), whole), Rhythm(story, story - 1, 1));
    if (kind == Kind.hall) {
        q.tower.paint(materials.table, boxOf(TABLE_X, TABLE_Y, whole), Rhythm(HALL_STORY, 1, 1));
        ulong hash = quarterHash(corner);
        foreach (floor; 0 .. HALL_STORIES) {
            if (mixed(mixed(hash, BENCH_SALT), floor) % cast(ulong) tuning.stationLots < tuning.benchLots) {
                int level = BOTTOM + floor * HALL_STORY + 1;
                q.tower.paint(materials.bench, boxOf(Span(TABLE_X.high, TABLE_X.high), Span(TABLE_Y.low, TABLE_Y.low), Span(level, level)));
            }
        }
    }
}

void atrium(ref const Quarter q, Material material, size_t index) {
    Span whole = Span(BOTTOM, ROOF);
    int far = q.tower.column().high;
    spread(q, Material.none, Span(BOTTOM + 1, ROOF - 1), EVERY_HEIGHT);
    spread(q, material, Span(BOTTOM, BOTTOM), EVERY_HEIGHT);
    spread(q, materials.ceiling, Span(ROOF, ROOF), EVERY_HEIGHT);
    q.tower.paint(materials.lamp, boxOf(Span(LAMP.x, LAMP.x), Span(LAMP.y, LAMP.y), Span(ROOF, ROOF)));
    q.tower.paint(materials.table, boxOf(Span(DESK, far), Span(DESK, far), Span(BOTTOM + 1, BOTTOM + 1)));
    if (index == 0) {
        q.tower.paint(materials.catalog, boxOf(Span(DESK, DESK), Span(DESK, DESK), Span(BOTTOM + 1, BOTTOM + 1)));
    }
    if (!q.isClear()) {
        q.tower.paint(material, boxOf(Span(0, far), Span(0, BALCONY), whole), Rhythm(STORY, 0, 1));
        q.tower.paint(material, boxOf(Span(0, BALCONY), Span(0, far), whole), Rhythm(STORY, 0, 1));
    }
}

Material stationOf(ulong hash, size_t place) {
    ulong lot = mixed(hash, place) % cast(ulong) tuning.stationLots;
    if (lot < tuning.labLots) {
        return materials.lab;
    } else if (lot < tuning.labLots + tuning.pressLots) {
        return materials.press;
    } else {
        return Material.none;
    }
}

void studies(Turtle tower, ulong hash) {
    Span whole = Span(BOTTOM, ROOF);
    int far = tower.column().high;
    Rhythm walls = Rhythm(STORY, 1, STORY - 2);
    tower.paint(materials.partition, boxOf(Span(PARTITION, PARTITION), Span(1, far), whole), walls);
    tower.paint(materials.partition, boxOf(Span(1, far), Span(PARTITION, PARTITION), whole), walls);
    size_t closed = cast(size_t)(mixed(hash, STUDY_SALT) % STUDY_DOORS.length);
    bool looped = roll(hash, LOOP_SALT) < tuning.loopOdds;
    foreach (index, door; STUDY_DOORS) {
        if (looped || index != closed) {
            tower.paint(Material.none, boxOf(Span(door.x, door.x), Span(door.y, door.y), whole), Rhythm(STORY, 1, STUDY_DOOR));
        }
    }
    foreach (carrel, desk; STUDY_DESKS) {
        tower.paint(materials.table, boxOf(Span(desk.x, desk.x + 1), Span(desk.y, desk.y), whole), Rhythm(STORY, 1, 1));
        foreach (story; 0 .. STORIES) {
            Material station = stationOf(mixed(hash, STATION_SALT), story * STUDY_DESKS.length + carrel);
            if (station != Material.none) {
                int level = BOTTOM + story * STORY + 1;
                tower.paint(station, boxOf(Span(desk.x, desk.x), Span(desk.y, desk.y), Span(level, level)));
            }
        }
    }
    foreach (lamp; STUDY_LAMPS) {
        tower.paint(materials.lamp, boxOf(Span(lamp.x, lamp.x), Span(lamp.y, lamp.y), whole), Rhythm(STORY, CEILING_AT, 1));
    }
}

void lounge(Turtle tower) {
    Span whole = Span(BOTTOM, ROOF);
    foreach (row; LOUNGE_ROWS) {
        tower.paint(materials.frame, boxOf(LOUNGE_SHELF, Span(row, row), whole), Rhythm(STORY, 1, 1));
        tower.paint(bookOf(tower), boxOf(LOUNGE_SHELF, Span(row, row), whole), Rhythm(STORY, 2, 1));
    }
    tower.paint(materials.table, boxOf(LOUNGE_TABLE_X, LOUNGE_TABLE_Y, whole), Rhythm(STORY, 1, 1));
}

void staff(Turtle tower) {
    Span whole = Span(BOTTOM, ROOF);
    tower.paint(materials.staffWall, boxOf(LOCKERS_X, Span(LOCKERS_Y, LOCKERS_Y), whole), Rhythm(STORY, 1, STORY - 2));
    tower.paint(materials.locker, boxOf(LOCKERS_X, Span(LOCKERS_Y, LOCKERS_Y), whole), Rhythm(STORY, 1, LOCKER_HEIGHT));
    tower.paint(materials.table, boxOf(Span(COUNTER_X, COUNTER_X), COUNTER_Y, whole), Rhythm(STORY, 1, 1));
    tower.paint(materials.sink, boxOf(Span(COUNTER_X, COUNTER_X), Span(SINK_Y, SINK_Y), whole), Rhythm(STORY, 1, 1));
    tower.paint(materials.workbench, boxOf(Span(COUNTER_X, COUNTER_X), Span(COUNTER_Y.high, COUNTER_Y.high), whole), Rhythm(STORY, 1, 1));
}

void tread(Turtle tower, int x, Span y, int top) {
    tower.paint(materials.stair, boxOf(Span(x, x), y, Span(top - 1, top)));
}

void stairwell(Turtle tower) {
    Span low = Span(1, 3);
    Span high = Span(5, 7);
    foreach (flight; LOWEST_FLIGHT .. HIGHEST_FLIGHT + 1) {
        int level = flight * STORY + 1;
        tower.paint(Material.none, boxOf(Span(3, 8), Span(1, 7), Span(level + STORY - 2, level + STORY - 1)));
        foreach (step; 0 .. 2) {
            tread(tower, 3 + step, low, level + step);
        }
        tower.paint(materials.stair, boxOf(Span(5, 8), Span(1, 7), Span(level + 1, level + 2)));
        foreach (step; 0 .. 3) {
            tread(tower, 4 - step, high, level + 3 + step);
        }
    }
}

void quarter(Turtle corner, size_t index, Kind kind, Material material, ref const Risen risen) {
    KindTag rising = corner.probeRising();
    if (rising != KindTag.of(STACKS_TAG)) {
        Quarter q = Quarter(upright(corner), clearingAt(corner, risen));
        if (kind == Kind.atrium) {
            atrium(q, material, index);
        } else {
            floors(q, kind, material, corner);
        }
        if (!q.isClear()) {
            wall(q.tower, Along.x, corner.probeHash(SitePart.edge));
            wall(q.tower, Along.y, corner.right().probeHash(SitePart.edge));
        }
        if (kind == Kind.stair && index == 0 && !q.isClear()) {
            stairwell(q.tower);
        } else if (kind == Kind.studies && !q.isClear()) {
            studies(q.tower, quarterHash(corner));
        } else if (kind == Kind.lounge && !q.isClear()) {
            lounge(q.tower);
        } else if (kind == Kind.staff && !q.isClear()) {
            staff(q.tower);
        } else if (kind == Kind.gallery) {
            Span stories = Span(BOTTOM + 1, ROOF - 1);
            stack(q.tower, Span(3, 7), Span(CLEAR, CLEAR + 1), stories);
            uint second = q.tower.pick(2);
            if (second == 0) {
                stack(q.tower, Span(3, 7), Span(CLEAR + 3, CLEAR + 4), stories);
            }
        }
        if (hasRooms(kind, index) && !q.isClear()) {
            basement(q.tower);
            divide(q.tower, corner);
        }
    }
}

void tile(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    Turtle face = Turtle(api, site);
    ulong hash = face.probeHash(SitePart.face);
    Kind kind = kindOf(hash);
    Material material = floorOf(hash);
    if (kind == Kind.lounge) {
        material = materials.lounge;
    } else if (kind == Kind.staff) {
        material = materials.staffFloor;
    }
    foreach (index, corner; cornersOf(face)) {
        quarter(corner, index, kind, material, *risen);
    }
}

void stories(Turtle tower, double outer, Span z, Material floor) {
    Rows ring = ringRows(tower.column(), WELL, outer);
    Rows well = ringRows(tower.column(), 0, WELL);
    tower.paintRows(Material.none, ring, z);
    tower.paintRows(Material.none, well, z);
    tower.paintRows(floor, ring, z, Rhythm(STORY, 0, 1));
    tower.paintRows(materials.well, well, z, Rhythm(STORY, 0, 1));
    tower.paintRows(materials.ceiling, ring, z, Rhythm(STORY, CEILING_AT, 1));
    immutable int[2] sides = [-LAMP_SPOT, LAMP_SPOT - 1];
    foreach (x; sides) {
        foreach (y; sides) {
            tower.paint(materials.lamp, boxOf(Span(x, x), Span(y, y), z), Rhythm(STORY, CEILING_AT, 1));
        }
    }
}

void shelving(Turtle tower, Span z) {
    Rows wall = ringRows(tower.column(), SHELF, RIM);
    tower.paintRows(materials.frame, wall, z);
    foreach (row; wall.slice()) {
        tower.paint(bookOf(tower), boxOf(row.x, Span(row.y, row.y), z), Rhythm(STORY, 2, 2));
    }
}

void catacomb(Turtle tower, Span z) {
    Rows wall = ringRows(tower.column(), SHELF, RIM);
    tower.paintRows(materials.crypt, wall, z);
    foreach (row; wall.slice()) {
        Material slab = materials.loculi.items[tower.pick(materials.loculi.count)];
        tower.paint(slab, boxOf(row.x, Span(row.y, row.y), z), LOCULI);
    }
}

Zone zoneOf(int segment) {
    if (segment > -tuning.stackEdges) {
        return Zone.stacks;
    } else {
        return Zone.catacombs;
    }
}

Level sideLevelOf(Zone zone) {
    final switch (zone) {
        case Zone.stacks:
            return Level.niche;
        case Zone.catacombs:
            return Level.crypt;
    }
}

Span placed(int sign, Span span) {
    if (sign > 0) {
        return span;
    } else {
        return negated(span);
    }
}

void sideBox(Turtle tower, Material material, Cell sign, Span x, Span y, Span z) {
    tower.paint(material, boxOf(placed(sign.x, x), placed(sign.y, y), z));
}

void sideRoom(Turtle tower, ref const Room made, int floor, Cell sign) {
    Span shell = Span(SIDE_WALL, SIDE_EDGE);
    Span door = Span(floor + 1, floor + ROOM_DOOR_TOP);
    sideBox(tower, made.wall, sign, shell, shell, Span(floor, floor + CEILING_AT));
    sideBox(tower, Material.none, sign, SIDE, SIDE, Span(floor + 1, floor + CEILING_AT - 1));
    if (made.floor != Material.none) {
        sideBox(tower, made.floor, sign, SIDE, SIDE, Span(floor, floor));
    }
    sideBox(tower, Material.none, sign, Span(SIDE_WALL, SIDE_WALL), Span(SIDE_WALL, SIDE.low), door);
    sideBox(tower, Material.none, sign, Span(SIDE.low, SIDE.low), Span(SIDE_WALL, SIDE_WALL), door);
    foreach (ref piece; made.pieces.slice()) {
        int x = SIDE_WALL + piece.x;
        int y = SIDE_WALL + piece.y;
        if (x <= SIDE.high && y <= SIDE.high) {
            Material material = piece.material;
            if (material == Material.none) {
                material = bookOf(tower);
            }
            Span z = Span(floor + piece.z, lowerOf(floor + piece.z + piece.tall - 1, floor + CEILING_AT - 1));
            sideBox(tower, material, sign, Span(x, lowerOf(x + piece.wide - 1, SIDE.high)), Span(y, lowerOf(y + piece.deep - 1, SIDE.high)), z);
        }
    }
    if (made.light != Material.none) {
        int middle = (SIDE.low + SIDE.high) / 2;
        sideBox(tower, made.light, sign, Span(middle, middle), Span(middle, middle), Span(floor + CEILING_AT, floor + CEILING_AT));
    }
}

void sideRooms(Turtle tower, Zone zone, Span z) {
    ulong hash = tower.probeHash(SitePart.vertex);
    foreach (story; 0 .. tower.edgeCells() / STORY) {
        int floor = story * STORY;
        if (floor >= z.low && floor + CEILING_AT <= z.high) {
            foreach (index, sign; SIDE_SIGNS) {
                ulong own = mixed(hash, SIDE_SALT + story * SIDE_SIGNS.length + index);
                MaybeIndex!Room chosen = roomIn(own, sideLevelOf(zone), 0);
                if (chosen.exists) {
                    sideRoom(tower, materials.rooms.items[chosen.value], floor, sign);
                }
            }
        }
    }
}

void descent(Turtle tower, int lastTread) {
    Rows[TURN_TREADS] treads = wedgeRows(tower.column(), WELL, STAIR_OUT);
    foreach (at; -STAIR_HEADROOM .. lastTread + 1) {
        Rows* wedge = &treads[floorMod(at, TURN_TREADS)];
        tower.clearOver(*wedge, at);
        if (at >= 0) {
            tower.paintRows(materials.stair, *wedge, treadSpan(at));
        }
    }
}

struct Ends {
    int walls;
    int landing;
}

Ends endsOf(Turtle foot, int length) {
    double crust = foot.probeCrust();
    if (!(crust < double.infinity)) {
        return Ends(int.min, int.min);
    } else {
        int walls = -cast(int) ceil((crust + WALLED_PAST_CRUST) * length);
        return Ends(walls, (floorDiv(walls, length) - tuning.spiralBelow) * length);
    }
}

void shaft(const(Api)* api, Site base, const(Risen)* risen, const(void)* data) {
    Turtle tower = Turtle(api, base);
    int length = tower.edgeCells();
    int bottom = risen.segment * length;
    Turtle foot = Turtle(api, risen.foot);
    Ends ends = endsOf(foot, length);
    if (bottom >= ends.landing) {
        stacksDown(tower, risen.segment, length, ends, floorOf(foot.probeHash(SitePart.vertex)));
    }
}

void stacksDown(Turtle tower, int segment, int length, Ends ends, Material floor) {
    int bottom = segment * length;
    int top = lowerOf(ROOF, bottom + length - 1);
    Span deep = Span(higherOf(bottom, ends.walls), lowerOf(BOTTOM - 1, top));
    Span slab = Span(higherOf(BOTTOM, bottom), top);
    if (deep.low <= deep.high) {
        Span z = Span(deep.low - bottom, deep.high - bottom);
        Zone zone = zoneOf(segment);
        stories(tower, SHELF, z, floor);
        final switch (zone) {
            case Zone.stacks:
                shelving(tower, z);
                break;
            case Zone.catacombs:
                catacomb(tower, z);
                break;
        }
        sideRooms(tower, zone, z);
    }
    if (slab.low <= slab.high) {
        stories(tower, EVERYWHERE, Span(slab.low - bottom, slab.high - bottom), floor);
    }
    int lastTread = TURN_TREADS - 1;
    if (segment == 0) {
        lastTread = TOP_TREAD;
        Rows cap = ringRows(tower.column(), 0, WELL);
        tower.paintRows(materials.ceiling, cap, Span(ROOF, ROOF));
    }
    descent(tower, lastTread);
    if (bottom == ends.landing) {
        Rows landing = ringRows(tower.column(), 0, STAIR_OUT);
        tower.paintRows(floor, landing, Span(0, 0));
    }
}

void route(Turtle tower) {
    foreach (index; 0 .. ROUTE_TREADS + 1) {
        int segment = floorDiv(-index, TURN_TREADS);
        Offset at = onWedge(-index, ROUTE_RADIUS);
        tower.forward(segment).stop(at.x, at.y, 1 - index - segment * TURN_TREADS);
    }
}

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    KindId kind = api.horosphere(api, tuning.riseOdds, HorosphereForm.solid, LIBRARY_TAG, &tile, null, 0);
    api.rooted(api, kind);
    api.look(api, kind, LOOK);
    api.tileReach(api, KindTag.of(LIBRARY_TAG), ROOF + 1, -BOTTOM);
    KindId stacks = api.sunken(api, tuning.shaftOdds, LIBRARY_TAG, STACKS_TAG, &shaft, null, 0);
    api.openHorosphere(api, site, stacks, 2);
    api.fog(api, tuning.fog);
    Turtle tower = at.columnSite();
    route(tower);
    tower.entrance(SPAWN.x, SPAWN.y, SPAWN.z);
}

immutable Connection RIG = Connection.forced(Style.paired, Routing.routed);
enum uint RIG_EDGES = 2;

void risenLibrary(const(Api)* api, Site site, const(void)* data) {
    KindId kind = api.horosphere(api, 0, HorosphereForm.solid, LIBRARY_TAG, &tile, null, 0);
    api.foot(api, LIBRARY_TAG, &footTile, &RIG, Connection.sizeof);
    api.look(api, kind, LOOK);
    api.tileReach(api, KindTag.of(LIBRARY_TAG), ROOF + 1, -BOTTOM);
    api.openHorosphere(api, site, kind, RIG_EDGES);
}

immutable Dependency[2] NEEDS = [dependencyOn(BASE), dependencyOn("connector")];
immutable Manifest MANIFEST = Manifest("library", FIRST_VERSION, NEEDS[], null, &resolve, null, import("plugins/library/settings.conf"), import("plugins/library/library.decl"), import("plugins/library/library.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.add(registry, "library", &world);
    registry.addDebug(registry, "risenlibrary", &risenLibrary);
    RisingKind rising = RisingKind(1, HorosphereForm.solid, LIBRARY_TAG, &tile, null, 0, LOOK, 0, null, null, ROOF + 1, -BOTTOM, &footTile, &ROLLED, Connection.sizeof);
    registry.addKind(registry, "library", &rising);
    RisingKind stacks = RisingKind(SHAFT_SHARE, HorosphereForm.sunken, STACKS_TAG, &shaft, null, 0, LOOK, LIBRARY_TAG);
    registry.addKind(registry, "librarystacks", &stacks);
}
