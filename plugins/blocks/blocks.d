module plugins.blocks.blocks;

import plugins.api.api : Api, Material, MaybeIndex, Rhythm, Risen, Site, SitePart, Span;
import plugins.api.binding : List, bound, settingsOf;
import plugins.api.content : Content;
import plugins.api.flags : Flags;
import plugins.buildings.building : Bound, Join, Lot, Lots, Palette, STORY, Side, Spec, Traits;
import types = plugins.buildings.types;
import plugins.connector.connector : Connection, connect, probeOwnsFoot, resolveConnector;
import plugins.turtle.turtle : Cell, FACE_CORNERS, Flight, PORT, Tread, Turtle, WELL_TREADS, boxOf, cornersOf, flightAt, floorDiv, floorMod, higherOf, lowerOf, mixed, ownerAround, roll, strongestAround, upright, wellTreadAt, wound;

enum ulong ISLAND_SALT = 0x51ED270B;
enum ulong DROPPED_SALT = 0x2C1B3C6D;
enum ulong TREES_SALT = 0x297A2D39;
enum ulong DISTRICT_SALT = 0x7B1D0F29;
enum ulong DEPTH_SALT = 0x44455054;
enum ulong STATION_SALT = 0x53544154;
enum ulong BAND_SALT = 0x42414E44;
enum ulong CORNER_SALT = 0x434F524E;
enum ulong STAFF_SALT = 0x53544146;
enum ulong SHORT_SALT = 0x53484F52;
enum Span SHORT_STATION = Span(9, 14);
enum Span STAFF_ROOM = Span(7, 10);
enum Span STAFF_ALONG = Span(9, 14);
enum Span STAFF_DOOR = Span(11, 12);
enum int STAFF_HEADROOM = 3;
enum Span LOCKERS = Span(10, 13);
enum Span STAFF_TABLE = Span(10, 11);
enum int STAFF_LAMP = 12;
immutable int[2] BENCH_ROWS = [4, -5];
enum Rhythm BENCHES = Rhythm(4, 1, 2);
enum double CORNER_ODDS = 0.5;
enum int DEEP_BED = -12;
enum int SHALLOW_BED = -8;
enum int CROSSED_TOP = SHALLOW_BED - 1;
enum int LEVEL = 6;
enum int DEEP_PLATFORM = 1;
enum int SHALLOW_PLATFORM = 2;
enum int UNDER_STREET = -2;
enum int MEZZANINE_FLOOR = -6;
enum int SHELL_END = PORT + 1;
enum int DOOR_Z = SHELL_END - 1;
enum Span DOOR = Span(-1, 0);
enum int DOOR_HEIGHT = 4;
enum Span TRACK = Span(-2, 1);
enum Span BORE = Span(-3, 2);
enum Span BORE_SHELL = Span(-4, 3);
enum Span STATION_WALLS = Span(-6, 5);
enum Span HALL = Span(-5, 4);
enum Span STATION_ALONG = Span(6, 17);
enum Span MEZZANINE_ALONG = Span(8, 15);
enum Span MEZZANINE_LAMPS = Span(11, 12);
enum Span TRACK_LAMPS = Span(-1, 0);
enum Span ENTRANCE = Span(2, 3);
enum int ENTRANCE_TOP = 3;
enum int POST_TOP = 3;
enum Span MEZZANINE_STAIR = Span(3, 4);
enum int MEZZANINE_STEPS = 4;
enum int MEZZANINE_STAIR_TOP = 11;
immutable int[2] PILLARS = [7, 10];
immutable Span[2] PLATFORMS = [Span(2, 4), Span(-5, -3)];
immutable Span[2] RIMS = [Span(2, 2), Span(-3, -3)];
immutable Span[2] WALLS = [Span(5, 5), Span(-6, -6)];
enum int PILLAR = 3;
enum int LAMP_EVERY = 3;
enum Span BORE_LAMP = Span(11, 12);
enum Span TRANSFER = Span(3, 4);
enum int TRANSFER_TOP = 3;
enum int TRANSFER_STEPS = SHALLOW_BED - DEEP_BED;
enum int TRANSFER_LANDING = 2;
enum int HEADROOM = 4;
enum size_t MOST_BANDS = 8;
enum uint AROUND = 4;
enum uint MOST_INSET = 1;
enum Span ROAD = Span(-2, 1);
enum Span SIDEWALK = Span(2, 3);
enum Span FAR_SIDEWALK = Span(-4, -3);
enum int FRONT = 4;
enum int CROSSING = 1;
enum int TREE_SPACING = 8;
enum int CROWN_PHASE = 4;
enum int CURB = SIDEWALK.low;
enum int PARKING_SPACING = 3;
enum int CROWN_ROOM = 10;
enum int PORT_FRAME = 6;
enum int ROUTE_STORIES = 2;
enum int ROUTE_BUILDING_STORIES = 4;
enum size_t MOST_TYPES = 16;
enum size_t MOST_LOT_RULES = 8;
enum size_t MOST_DISTRICTS = 8;
immutable Bound[4] RUN_BOUNDS = [Side.xLow: Bound.joined, Side.yLow: Bound.joined, Side.xHigh: Bound.lot, Side.yHigh: Bound.lot];
immutable Bound[4] ISLAND_BOUNDS = [Side.xLow: Bound.street, Side.yLow: Bound.street, Side.xHigh: Bound.joined, Side.yHigh: Bound.joined];

enum LotShape : ubyte {
    corner,
    run,
}

enum LotMark : ubyte {
    streetBefore,
    streetAfter,
    first,
}

struct LotRule {
    uint lots;
    LotShape shape;
    int mostStories;
    List!(Traits, MOST_TYPES) types;
}

struct District {
    double streetTrees;
    double ports;
    uint parkPercent;
    uint plazaPercent;
    uint parkingPercent;
    List!(LotRule, MOST_LOT_RULES) rules;
    LotRule island;
}

struct Zoning {
    List!(District, MOST_DISTRICTS) districts;
    Traits route;
}

__gshared Zoning zoning;

struct Tuning {
    double droppedStreet;
    double island;
    uint pondPercent;
    uint fountainPercent;
    uint alleyPercent;
    double stationOdds;
    double deepOdds;
    double staffOdds;
    double shortOdds;
}

__gshared Tuning tuning;

const(District)* districtAt(Turtle corner) {
    return &zoning.districts.items[mixed(strongestAround(corner), DISTRICT_SALT) % zoning.districts.count];
}

MaybeIndex!LotRule ruleFor(ref const District district, uint lots) {
    uint index = 0;
    while (index < district.rules.count && district.rules.items[index].lots != lots) {
        index += 1;
    }
    if (index < district.rules.count) {
        return MaybeIndex!LotRule.of(index);
    } else {
        return MaybeIndex!LotRule.init;
    }
}

struct Materials {
    Material road;
    Material sidewalk;
    Material marking;
    Material leaves;
    Material trunk;
    Material basin;
    Material water;
    Material pondBed;
    Material lot;
    Material plaza;
    Material park;
    Material kerb;
    Material frame;
    Material tunnel;
    Material tunnelLight;
    Material boreLight;
    Material ballast;
    Material rail;
    Material platform;
    Material platformEdge;
    Material stationWall;
    Material stationCeiling;
    Material pillar;
    Material mezzanine;
    Material railing;
    Material entrance;
    Material transfer;
    Material bench;
    Material staffWall;
    Material staffFloor;
    Material locker;
    Material table;
    List!(Material, MOST_BANDS) bands;
}

__gshared Materials materials;

void resolveBlocks(const(Content)* content) {
    types.resolveBuildings(content);
    resolveConnector(content);
    materials = content.bound!Materials("blocks:materials");
    zoning = content.bound!Zoning("blocks:zoning");
    resolveStreets(content);
}

void resolveStreets(const(Content)* content) {
    tuning = content.settingsOf!Tuning("blocks");
}

struct Root {
    ulong vertex;
    ulong face;
    Risen risen;
    Connection connection;
    uint tag;

    bool isRisen() const {
        return risen.hasRisen;
    }
}

struct Area {
    Turtle tower;
    Span x;
    Span y;
}

Turtle[AROUND] quartersOf(Turtle corner) {
    Turtle[AROUND] quarters;
    Turtle turtle = corner;
    foreach (index; 0 .. AROUND) {
        quarters[index] = turtle;
        turtle = turtle.right();
    }
    return quarters;
}

bool probeOwner(ref const Turtle[AROUND] quarters) {
    ulong mine = quarters[0].probeHash(SitePart.face);
    foreach (quarter; quarters[1 .. $]) {
        ulong theirs = quarter.probeHash(SitePart.face);
        if (!(theirs < mine)) {
            return false;
        }
    }
    return true;
}

double mostPortShare() {
    double most = 0;
    foreach (ref district; zoning.districts.items[0 .. zoning.districts.count]) {
        most = higherOf(most, district.ports);
    }
    return most;
}

bool portAt(const(Api)* api, Site vertex, double rolled, const(void)* data) {
    return rolled < districtAt(ownerAround(Turtle(api, vertex))).ports;
}

bool probeFoot(Turtle corner, ref const Risen risen) {
    ulong own = corner.probeHash(SitePart.vertex);
    ulong foot = Turtle(corner.api, risen.foot).probeHash(SitePart.vertex);
    return own == foot;
}

bool probeTaken(Turtle corner, ref const Risen risen) {
    bool taken = corner.probeRising().exists;
    if (!taken && risen.hasRisen) {
        taken = probeFoot(corner, risen);
    }
    return taken;
}

bool probeRootVertex(Turtle site, ref const Root root) {
    ulong own = site.probeHash(SitePart.vertex);
    return own == root.vertex;
}

bool probeIsland(Turtle face, ref const Root root) {
    double rolled = roll(face.probeHash(SitePart.face), ISLAND_SALT);
    if (rolled >= tuning.island) {
        return false;
    } else {
        foreach (corner; cornersOf(face)) {
            bool rooted = probeRootVertex(corner, root);
            if (!rooted) {
                rooted = corner.probePort();
            }
            if (rooted) {
                return false;
            }
        }
        return true;
    }
}

bool probePlannedStreet(Turtle edge, ref const Root root) {
    bool planned = probeRootVertex(edge, root);
    if (!planned) {
        planned = probeRootVertex(edge.forward(1), root);
    }
    if (!planned) {
        planned = probeIsland(edge, root);
    }
    if (!planned) {
        planned = probeIsland(edge.left(), root);
    }
    if (!planned) {
        double rolled = roll(edge.probeHash(SitePart.edge), DROPPED_SALT);
        planned = rolled >= tuning.droppedStreet;
    }
    return planned;
}

bool probeKeptForAccess(Turtle edge, ref const Root root) {
    ulong mine = edge.probeHash(SitePart.edge);
    Turtle turtle = edge.right();
    foreach (index; 1 .. AROUND) {
        bool planned = probePlannedStreet(turtle, root);
        if (planned) {
            return false;
        }
        ulong theirs = turtle.probeHash(SitePart.edge);
        if (!(theirs < mine)) {
            return false;
        }
        turtle = turtle.right();
    }
    return true;
}

bool probeStreet(Turtle edge, ref const Root root) {
    bool paved = probePlannedStreet(edge, root);
    if (!paved) {
        paved = probeKeptForAccess(edge, root);
    }
    if (!paved) {
        paved = probeKeptForAccess(edge.forward(1).right().right(), root);
    }
    return paved;
}

bool probeTrees(Turtle edge) {
    double rolled = roll(edge.probeHash(SitePart.edge), TREES_SALT);
    return rolled < districtAt(edge).streetTrees;
}

void sidewalk(Turtle edge, Span x, int startGap, int endGap) {
    edge.paint(materials.sidewalk, boxOf(x, Span(-1, 0), Span(startGap, edge.edgeCells() - 1 - endGap)));
}

void streetTrees(Turtle edge, int clear) {
    int last = edge.edgeCells() - 1;
    Span planted = Span(higherOf(CROSSING + 4, clear + floorMod(CROWN_PHASE - clear, TREE_SPACING)), last - CROSSING - 4);
    Rhythm trunk = Rhythm(TREE_SPACING, 6, 1);
    edge.paint(materials.leaves, boxOf(Span(CURB - 1, CURB + 1), Span(5, 6), planted), Rhythm(TREE_SPACING, 4, 5));
    edge.paint(materials.leaves, boxOf(Span(CURB - 1, CURB + 1), Span(7, 7), planted), Rhythm(TREE_SPACING, 5, 3));
    edge.paint(materials.leaves, boxOf(Span(CURB, CURB), Span(8, 8), planted), trunk);
    edge.paint(materials.trunk, boxOf(Span(CURB, CURB), Span(1, 5), planted), trunk);
}

enum Depth : ubyte {
    deep,
    shallow,
}

enum Stop : ubyte {
    passing,
    station,
}

enum EndMark : ubyte {
    port,
    taken,
    right,
    left,
    onward,
}

struct End {
    Turtle frame;
    Flags!EndMark marks;
    Depth across;

    bool isCrossed() const {
        return marks.has(EndMark.right) || marks.has(EndMark.left);
    }

    bool isClosed() const {
        return marks.has(EndMark.port) || marks.has(EndMark.taken);
    }

    bool isTransfer(Depth depth) const {
        return !isClosed() && isCrossed() && across != depth;
    }
}

End endAt(Turtle frame, ref const Root root) {
    End end;
    end.frame = frame;
    end.marks.put(EndMark.port, frame.probePort());
    end.marks.put(EndMark.taken, probeTaken(frame, root.risen));
    end.marks.put(EndMark.right, probeStreet(frame.right(), root));
    end.marks.put(EndMark.left, probeStreet(frame.left(), root));
    end.marks.put(EndMark.onward, probeStreet(frame.forward(-1), root));
    end.across = depthOf(frame.right());
    return end;
}

int gapAt(ref const End end, EndMark mark, int gap) {
    if (end.marks.has(mark)) {
        return gap;
    } else {
        return 0;
    }
}

Turtle reversed(Turtle edge) {
    return edge.forward(1).right().right();
}

void street(Turtle edge, ref const Root root) {
    End start = endAt(edge, root);
    End finish = endAt(reversed(edge), root);
    int last = edge.edgeCells() - 1;
    int startPort = gapAt(start, EndMark.port, PORT);
    int endPort = gapAt(finish, EndMark.port, PORT);
    edge.paint(materials.road, boxOf(ROAD, Span(-1, -1), Span(startPort, last - endPort)));
    sidewalk(edge, SIDEWALK, higherOf(startPort, gapAt(start, EndMark.right, CROSSING + 1)), higherOf(endPort, gapAt(finish, EndMark.left, CROSSING + 1)));
    sidewalk(edge, FAR_SIDEWALK, higherOf(startPort, gapAt(start, EndMark.left, CROSSING + 1)), higherOf(endPort, gapAt(finish, EndMark.right, CROSSING + 1)));
    if (start.isCrossed() && startPort == 0) {
        edge.paint(materials.marking, boxOf(ROAD, Span(-1, -1), Span(CROSSING + 1, CROSSING + 2)));
    }
    if (finish.isCrossed() && endPort == 0) {
        edge.paint(materials.marking, boxOf(ROAD, Span(-1, -1), Span(last - CROSSING - 2, last - CROSSING - 1)));
    }
    bool trees = probeTrees(edge);
    if (trees) {
        int clear = 0;
        if (hasEntrance(edge, start)) {
            clear = entranceBeyond(depthOf(edge)) + 1;
        }
        streetTrees(edge, clear);
    }
    subway(edge, start, finish);
}

Depth depthOf(Turtle edge) {
    if (roll(edge.probeHash(SitePart.line), DEPTH_SALT) < tuning.deepOdds) {
        return Depth.deep;
    } else {
        return Depth.shallow;
    }
}

Stop stopOf(Turtle edge) {
    if (roll(edge.probeHash(SitePart.edge), STATION_SALT) < tuning.stationOdds) {
        return Stop.station;
    } else {
        return Stop.passing;
    }
}

int bedOf(Depth depth) {
    final switch (depth) {
        case Depth.deep:
            return DEEP_BED;
        case Depth.shallow:
            return SHALLOW_BED;
    }
}

int hallTopOf(Depth depth) {
    final switch (depth) {
        case Depth.deep:
            return UNDER_STREET - 1;
        case Depth.shallow:
            return UNDER_STREET;
    }
}

int pillarTopOf(Depth depth, int z) {
    final switch (depth) {
        case Depth.deep:
            if (z >= MEZZANINE_ALONG.low && z <= MEZZANINE_ALONG.high) {
                return MEZZANINE_FLOOR - 1;
            } else {
                return hallTopOf(depth);
            }
        case Depth.shallow:
            return hallTopOf(depth);
    }
}

int platformRiseOf(Depth depth) {
    final switch (depth) {
        case Depth.deep:
            return DEEP_PLATFORM;
        case Depth.shallow:
            return SHALLOW_PLATFORM;
    }
}

int arrivalOf(Depth depth) {
    final switch (depth) {
        case Depth.deep:
            return MEZZANINE_FLOOR + 1;
        case Depth.shallow:
            return SHALLOW_BED + SHALLOW_PLATFORM + 1;
    }
}

int clearingAt(ref const End end) {
    if (end.isClosed()) {
        return SHELL_END;
    } else {
        return 0;
    }
}

int topNear(ref const End end, Depth depth, int top) {
    if (depth == Depth.deep && end.isCrossed() && end.across == Depth.shallow) {
        return CROSSED_TOP;
    } else {
        return top;
    }
}

void clearBore(Turtle edge, Span along, int bed, int top) {
    if (along.low <= along.high) {
        edge.paint(Material.none, boxOf(BORE, Span(bed + 1, top), along));
    }
}

bool isContinued(ref const End end) {
    return end.marks.has(EndMark.onward) && !end.isClosed() && !end.isCrossed() && stopOf(end.frame.forward(-1)) == Stop.station;
}

bool isShort(Turtle edge, Depth depth) {
    return depth == Depth.shallow && roll(edge.probeHash(SitePart.edge), SHORT_SALT) < tuning.shortOdds;
}

bool hasStaffRoom(Turtle edge) {
    return roll(edge.probeHash(SitePart.edge), STAFF_SALT) < tuning.staffOdds;
}

Span stationOf(Turtle edge, Depth depth, ref const End start, ref const End finish, int last) {
    Span walls = STATION_ALONG;
    if (isShort(edge, depth)) {
        walls = SHORT_STATION;
    }
    if (isContinued(start)) {
        walls.low = 0;
    }
    if (isContinued(finish)) {
        walls.high = last;
    }
    return walls;
}

Span insideOf(Span walls, int last) {
    Span inside = Span(walls.low + 1, walls.high - 1);
    if (walls.low == 0) {
        inside.low = 0;
    }
    if (walls.high == last) {
        inside.high = last;
    }
    return inside;
}

void subway(Turtle edge, ref const End start, ref const End finish) {
    Depth depth = depthOf(edge);
    Stop stop = stopOf(edge);
    int bed = bedOf(depth);
    int last = edge.edgeCells() - 1;
    Span along = Span(clearingAt(start), last - clearingAt(finish));
    Span walls = Span(higherOf(along.low, SHELL_END), lowerOf(along.high, last - SHELL_END));
    Span station = stationOf(edge, depth, start, finish, last);
    edge.paint(materials.tunnel, boxOf(BORE_SHELL, Span(bed, lowerOf(bed + LEVEL, UNDER_STREET)), walls));
    final switch (stop) {
        case Stop.passing:
            break;
        case Stop.station:
            hall(edge, depth, station, insideOf(station, last));
            break;
    }
    int top = lowerOf(bed + LEVEL - 1, UNDER_STREET);
    clearBore(edge, Span(along.low, SHELL_END - 1), bed, topNear(start, depth, top));
    clearBore(edge, walls, bed, top);
    clearBore(edge, Span(last - SHELL_END + 1, along.high), bed, topNear(finish, depth, top));
    edge.paint(materials.ballast, boxOf(BORE, Span(bed, bed), along));
    edge.paint(materials.rail, boxOf(Span(TRACK.low, TRACK.low), Span(bed + 1, bed + 1), along));
    edge.paint(materials.rail, boxOf(Span(TRACK.high, TRACK.high), Span(bed + 1, bed + 1), along));
    final switch (stop) {
        case Stop.passing:
            edge.paint(materials.boreLight, boxOf(TRACK_LAMPS, Span(top, top), BORE_LAMP));
            lineEnd(start, depth);
            lineEnd(finish, depth);
            break;
        case Stop.station:
            fittings(edge, depth, insideOf(station, last), materials.bands.items[mixed(edge.probeHash(SitePart.line), BAND_SALT) % materials.bands.count]);
            if (hasStaffRoom(edge)) {
                staffRoom(edge, depth);
            }
            stationEnd(start, depth);
            stationEnd(finish, depth);
            break;
    }
}

void hall(Turtle edge, Depth depth, Span walls, Span inside) {
    int bed = bedOf(depth);
    edge.paint(materials.stationWall, boxOf(STATION_WALLS, Span(bed, UNDER_STREET), walls));
    edge.paint(Material.none, boxOf(HALL, Span(bed + 1, hallTopOf(depth)), inside));
}

void fittings(Turtle edge, Depth depth, Span inside, Material band) {
    int bed = bedOf(depth);
    int platform = bed + platformRiseOf(depth);
    foreach (side; PLATFORMS) {
        edge.paint(materials.platform, boxOf(side, Span(bed, platform), inside));
    }
    foreach (rim; RIMS) {
        edge.paint(materials.platformEdge, boxOf(rim, Span(platform, platform), inside));
    }
    foreach (row; BENCH_ROWS) {
        edge.paint(materials.bench, boxOf(Span(row, row), Span(platform + 1, platform + 1), inside), BENCHES);
    }
    final switch (depth) {
        case Depth.deep:
            foreach (wall; WALLS) {
                edge.paint(band, boxOf(wall, Span(bed + 4, bed + 4), inside));
                edge.paint(band, boxOf(wall, Span(MEZZANINE_FLOOR + 2, MEZZANINE_FLOOR + 2), inside));
            }
            edge.paint(materials.stationCeiling, boxOf(HALL, Span(UNDER_STREET, UNDER_STREET), inside));
            edge.paint(materials.tunnelLight, boxOf(TRACK_LAMPS, Span(UNDER_STREET, UNDER_STREET), inside), Rhythm(LAMP_EVERY, inside.low, 1));
            edge.paint(materials.mezzanine, boxOf(HALL, Span(MEZZANINE_FLOOR, MEZZANINE_FLOOR), MEZZANINE_ALONG));
            edge.paint(materials.tunnelLight, boxOf(TRACK_LAMPS, Span(MEZZANINE_FLOOR, MEZZANINE_FLOOR), MEZZANINE_LAMPS));
            break;
        case Depth.shallow:
            foreach (wall; WALLS) {
                edge.paint(band, boxOf(wall, Span(platform + 2, platform + 2), inside));
                edge.paint(materials.tunnelLight, boxOf(wall, Span(UNDER_STREET, UNDER_STREET), inside), Rhythm(LAMP_EVERY, inside.low, 1));
            }
            break;
    }
    int last = edge.edgeCells() - 1;
    stationHalf(edge, depth, inside);
    stationHalf(reversed(edge), depth, Span(last - inside.high, last - inside.low));
}

void staffRoom(Turtle edge, Depth depth) {
    int floor = bedOf(depth) + platformRiseOf(depth);
    Span room = Span(floor + 1, floor + STAFF_HEADROOM);
    Span shell = Span(STAFF_ROOM.low - 1, STAFF_ROOM.high + 1);
    edge.paint(materials.staffWall, boxOf(shell, Span(floor, floor + STAFF_HEADROOM + 1), Span(STAFF_ALONG.low - 1, STAFF_ALONG.high + 1)));
    edge.paint(Material.none, boxOf(STAFF_ROOM, room, STAFF_ALONG));
    edge.paint(materials.staffFloor, boxOf(STAFF_ROOM, Span(floor, floor), STAFF_ALONG));
    edge.paint(Material.none, boxOf(Span(STATION_WALLS.high, shell.low), room, STAFF_DOOR));
    edge.paint(materials.locker, boxOf(Span(STAFF_ROOM.high, STAFF_ROOM.high), Span(floor + 1, floor + 2), LOCKERS));
    edge.paint(materials.table, boxOf(Span(STAFF_ROOM.low + 1, STAFF_ROOM.low + 2), Span(floor + 1, floor + 1), STAFF_TABLE));
    edge.paint(materials.tunnelLight, boxOf(Span(STAFF_ROOM.low + 2, STAFF_ROOM.low + 2), Span(floor + STAFF_HEADROOM + 1, floor + STAFF_HEADROOM + 1), Span(STAFF_LAMP, STAFF_LAMP)));
}

void stationHalf(Turtle frame, Depth depth, Span inside) {
    int bed = bedOf(depth);
    foreach (z; PILLARS) {
        if (z >= inside.low && z <= inside.high) {
            frame.paint(materials.pillar, boxOf(Span(PILLAR, PILLAR), Span(bed + platformRiseOf(depth) + 1, pillarTopOf(depth, z)), Span(z, z)));
        }
    }
    final switch (depth) {
        case Depth.deep:
            Span opening = Span(MEZZANINE_STAIR_TOP + 1, MEZZANINE_STAIR_TOP + MEZZANINE_STEPS);
            frame.paint(Material.none, boxOf(MEZZANINE_STAIR, Span(MEZZANINE_FLOOR, MEZZANINE_FLOOR), opening));
            foreach (step; 1 .. MEZZANINE_STEPS + 1) {
                int z = MEZZANINE_STAIR_TOP + step;
                frame.paint(materials.platform, boxOf(MEZZANINE_STAIR, Span(bed + 2, MEZZANINE_FLOOR - step), Span(z, z)));
            }
            frame.paint(materials.railing, boxOf(Span(MEZZANINE_STAIR.low - 1, MEZZANINE_STAIR.low - 1), Span(MEZZANINE_FLOOR + 1, MEZZANINE_FLOOR + 1), opening));
            break;
        case Depth.shallow:
            break;
    }
}

bool isStationBeside(ref const End end) {
    return (end.marks.has(EndMark.right) && stopOf(end.frame.right()) == Stop.station) || (end.marks.has(EndMark.left) && stopOf(end.frame.left()) == Stop.station);
}

bool isCornerYielded(ref const End end, Depth depth) {
    if (!end.isCrossed() || end.across != depth || !isStationBeside(end)) {
        return false;
    } else {
        ulong own = end.frame.probeHash(SitePart.line);
        ulong across = end.frame.right().probeHash(SitePart.line);
        if (roll(end.frame.probeHash(SitePart.vertex), CORNER_SALT) < CORNER_ODDS) {
            return own > across;
        } else {
            return own < across;
        }
    }
}

bool isEntranceAt(ref const End end, Depth depth) {
    return !end.isClosed() && !end.isTransfer(depth) && !isCornerYielded(end, depth);
}

bool hasEntrance(Turtle edge, ref const End end) {
    return stopOf(edge) == Stop.station && isEntranceAt(end, depthOf(edge));
}

void stationEnd(ref const End end, Depth depth) {
    if (isEntranceAt(end, depth)) {
        entrance(end.frame, depth);
    }
}

int entranceBeyond(Depth depth) {
    return ENTRANCE_TOP + 2 - arrivalOf(depth);
}

void entrance(Turtle frame, Depth depth) {
    int arrival = arrivalOf(depth);
    int steps = 1 - arrival;
    foreach (step; 1 .. steps + 1) {
        int z = ENTRANCE_TOP + step;
        frame.paint(materials.platform, boxOf(ENTRANCE, Span(arrival - 1, -step), Span(z, z)));
        frame.paint(Material.none, boxOf(ENTRANCE, Span(1 - step, 0), Span(z, z)));
    }
    int beyond = entranceBeyond(depth);
    frame.paint(materials.entrance, boxOf(Span(ENTRANCE.low - 1, ENTRANCE.low - 1), Span(0, 0), Span(ENTRANCE_TOP + 1, beyond - 1)));
    frame.paint(materials.entrance, boxOf(Span(ENTRANCE.high + 1, ENTRANCE.high + 1), Span(1, 1), Span(ENTRANCE_TOP, beyond)));
    frame.paint(materials.entrance, boxOf(ENTRANCE, Span(1, 1), Span(beyond, beyond)));
    frame.paint(materials.entrance, boxOf(Span(ENTRANCE.high + 1, ENTRANCE.high + 1), Span(1, POST_TOP - 1), Span(ENTRANCE_TOP, ENTRANCE_TOP)));
    frame.paint(materials.tunnelLight, boxOf(Span(ENTRANCE.high + 1, ENTRANCE.high + 1), Span(POST_TOP, POST_TOP), Span(ENTRANCE_TOP, ENTRANCE_TOP)));
}

Cell doorCellOf(Turtle down, ulong street) {
    if (down.right().probeHash(SitePart.edge) == street) {
        return Cell(PORT - 1, 0);
    } else if (down.left().probeHash(SitePart.edge) == street) {
        return Cell(-PORT, -1);
    } else if (down.pitchUp().probeHash(SitePart.edge) == street) {
        return Cell(-1, PORT - 1);
    } else {
        return Cell(0, -PORT);
    }
}

bool isIn(Tread tread, Cell cell) {
    return cell.x >= tread.x.low && cell.x <= tread.x.high && cell.y >= tread.y.low && cell.y <= tread.y.high;
}

int treadFacing(Flight flight, Cell cell) {
    int index = 0;
    while (index < WELL_TREADS && !isIn(wound(wellTreadAt(index), flight.winding), cell)) {
        index += 1;
    }
    return index;
}

int doorFloorOf(int tread, int bore) {
    int below = floorMod(tread + bore, WELL_TREADS);
    if (bore - below >= DEEP_BED) {
        return bore - below;
    } else {
        return bore + WELL_TREADS - below;
    }
}

void wellDoor(Turtle frame, Depth depth) {
    int bore = bedOf(depth) + 1;
    Flight flight = flightAt(frame.pitchDown());
    int door = doorFloorOf(treadFacing(flight, doorCellOf(flight.frame, frame.probeHash(SitePart.edge))), bore);
    frame.paint(Material.none, boxOf(DOOR, Span(door, door + DOOR_HEIGHT - 1), Span(DOOR_Z, DOOR_Z)));
    int step = 1;
    int floor = door;
    while (floor != bore) {
        if (floor > bore) {
            floor -= 1;
        } else {
            floor += 1;
        }
        int z = DOOR_Z + step;
        if (floor > bore) {
            frame.paint(materials.platform, boxOf(DOOR, Span(bore, floor - 1), Span(z, z)));
        }
        frame.paint(Material.none, boxOf(DOOR, Span(floor, floor + DOOR_HEIGHT - 1), Span(z, z)));
        step += 1;
    }
}

void lineEnd(ref const End end, Depth depth) {
    if (end.isTransfer(depth)) {
        final switch (depth) {
            case Depth.deep:
                transfer(end.frame);
                break;
            case Depth.shallow:
                break;
        }
    } else if (end.marks.has(EndMark.port)) {
        wellDoor(end.frame, depth);
    } else if (!end.isClosed() && !end.isCrossed() && !end.marks.has(EndMark.onward)) {
        int bed = bedOf(depth);
        end.frame.paint(materials.pillar, boxOf(TRACK, Span(bed + 1, bed + 2), Span(1, 1)));
    }
}

void transfer(Turtle frame) {
    int bottom = TRANSFER_TOP + TRANSFER_STEPS;
    frame.paint(materials.stationWall, boxOf(Span(TRANSFER.low, TRANSFER.high + 1), Span(DEEP_BED, UNDER_STREET), Span(TRANSFER_TOP, bottom + TRANSFER_LANDING + 1)));
    frame.paint(materials.tunnelLight, boxOf(Span(TRANSFER.high + 1, TRANSFER.high + 1), Span(SHALLOW_BED - 1, SHALLOW_BED - 1), Span(bottom - 2, bottom - 2)));
    frame.paint(materials.transfer, boxOf(TRANSFER, Span(SHALLOW_BED, SHALLOW_BED), Span(0, TRANSFER_TOP)));
    frame.paint(Material.none, boxOf(TRANSFER, Span(SHALLOW_BED + 1, SHALLOW_BED + HEADROOM), Span(0, TRANSFER_TOP)));
    foreach (step; 1 .. TRANSFER_STEPS + 1) {
        int z = TRANSFER_TOP + step;
        int top = SHALLOW_BED - step;
        if (top > DEEP_BED) {
            frame.paint(materials.transfer, boxOf(TRANSFER, Span(DEEP_BED + 1, top), Span(z, z)));
        }
        frame.paint(Material.none, boxOf(TRANSFER, Span(top + 1, top + HEADROOM), Span(z, z)));
    }
    frame.paint(Material.none, boxOf(TRANSFER, Span(DEEP_BED + 1, DEEP_BED + HEADROOM), Span(bottom + 1, bottom + TRANSFER_LANDING)));
}

void tree(Turtle tower, int x, int y) {
    tower.paint(materials.leaves, boxOf(Span(x - 2, x + 2), Span(y - 1, y + 1), Span(5, 7)));
    tower.paint(materials.leaves, boxOf(Span(x - 1, x + 1), Span(y - 2, y + 2), Span(5, 7)));
    tower.paint(materials.leaves, boxOf(Span(x - 1, x + 1), Span(y - 1, y + 1), Span(8, 9)));
    tower.paint(materials.trunk, boxOf(Span(x, x), Span(y, y), Span(1, 7)));
}

Area groundOf(ref const Lot lot) {
    Turtle tower = upright(lot.site);
    int far = tower.column().high;
    int xLow = 0;
    int yLow = 0;
    if (lot.bounds[Side.xLow] == Bound.street) {
        xLow = FRONT;
    }
    if (lot.bounds[Side.yLow] == Bound.street) {
        yLow = FRONT;
    }
    return Area(tower, Span(xLow, far), Span(yLow, far));
}

void pave(ref const Lots lots, Material material) {
    foreach (ref lot; lots.slice()) {
        Area area = groundOf(lot);
        area.tower.paint(material, boxOf(area.x, area.y, Span(-1, 0)));
    }
}

void paveAroundPort(ref const Lots lots, Material material) {
    foreach (ref lot; lots.slice()) {
        Area area = groundOf(lot);
        area.tower.paint(material, boxOf(Span(higherOf(area.x.low, PORT), area.x.high), area.y, Span(-1, 0)));
        if (area.x.low < PORT) {
            area.tower.paint(material, boxOf(Span(area.x.low, PORT - 1), Span(higherOf(area.y.low, PORT), area.y.high), Span(-1, 0)));
        }
    }
}

void portFrame(ref const Lots lots) {
    foreach (ref lot; lots.slice()) {
        Turtle tower = upright(lot.site);
        tower.paint(materials.kerb, boxOf(Span(PORT, PORT), Span(0, PORT), Span(1, 1)));
        tower.paint(materials.kerb, boxOf(Span(0, PORT - 1), Span(PORT, PORT), Span(1, 1)));
        tower.paint(materials.frame, boxOf(Span(PORT, PORT), Span(PORT, PORT), Span(1, PORT_FRAME)));
        tower.paint(materials.frame, boxOf(Span(PORT, PORT), Span(0, PORT), Span(PORT_FRAME, PORT_FRAME)));
        tower.paint(materials.frame, boxOf(Span(0, PORT - 1), Span(PORT, PORT), Span(PORT_FRAME, PORT_FRAME)));
    }
}

bool isRoomy(Area area) {
    return area.x.high - area.x.low >= 4 && area.y.high - area.y.low >= 4;
}

int centre(Span span) {
    return floorDiv(span.low + span.high + 1, 2);
}

void plant(ref const Lots lots) {
    foreach (ref lot; lots.slice()) {
        Area area = groundOf(lot);
        if (isRoomy(area)) {
            tree(area.tower, centre(area.x), centre(area.y));
        }
    }
}

void fountain(Turtle tower, int x, int y) {
    tower.paint(materials.basin, boxOf(Span(x - 2, x + 2), Span(y - 2, y + 2), Span(1, 1)));
    tower.paint(materials.water, boxOf(Span(x - 1, x + 1), Span(y - 1, y + 1), Span(1, 1)));
    tower.paint(materials.basin, boxOf(Span(x, x), Span(y, y), Span(1, 2)));
    tower.paint(materials.water, boxOf(Span(x, x), Span(y, y), Span(3, 3)));
}

void fountains(ref const Lots lots) {
    foreach (ref lot; lots.slice()) {
        Area area = groundOf(lot);
        if (isRoomy(area)) {
            fountain(area.tower, centre(area.x), centre(area.y));
        }
    }
}

void ponds(ref const Lots lots) {
    foreach (ref lot; lots.slice()) {
        Area area = groundOf(lot);
        if (isRoomy(area)) {
            Span x = Span(area.x.low + 1, area.x.high - 1);
            Span y = Span(area.y.low + 1, area.y.high - 1);
            area.tower.paint(materials.water, boxOf(x, y, Span(-1, 0)));
            area.tower.paint(materials.pondBed, boxOf(x, y, Span(-2, -2)));
        }
    }
}

void parking(ref const Lots lots) {
    foreach (ref lot; lots.slice()) {
        Area area = groundOf(lot);
        area.tower.paint(materials.road, boxOf(area.x, area.y, Span(0, 0)));
        for (int x = area.x.low + 1; x <= area.x.high; x += PARKING_SPACING) {
            area.tower.paint(materials.marking, boxOf(Span(x, x), Span(area.y.low + 1, area.y.low + 3), Span(0, 0)));
        }
    }
}

struct Chosen {
    const(Traits)* traits;
    Spec spec;
}

Chosen chosenFor(Turtle site, ref const LotRule rule) {
    const(Traits)* traits = &rule.types.items[site.pick(rule.types.count)];
    Span range = traits.stories;
    int most = lowerOf(range.high, rule.mostStories);
    int count = site.pickBetween(range.low, most);
    int gap = 0;
    if (rule.shape == LotShape.run) {
        bool alley = site.rollPercent(tuning.alleyPercent);
        if (alley) {
            gap = 1;
        }
    }
    int front = FRONT;
    if (rule.shape == LotShape.run) {
        front = FRONT + cast(int) site.pick(MOST_INSET + 1);
    }
    const(Palette)[] options = traits.palettes.slice();
    Spec spec = {stories: count, palette: options[site.pick(cast(uint) options.length)], front: front, gap: gap};
    return Chosen(traits, spec);
}

int fit(Turtle site, int stories) {
    int room = CROWN_ROOM + 1;
    int fitting = floorDiv(site.probeBalance(stories * STORY + room) - room, STORY);
    return lowerOf(stories, fitting);
}

Chosen fitted(Chosen chosen, Turtle site, ref const Root root) {
    Chosen result = chosen;
    if (root.isRisen()) {
        result.spec.stories = fit(site, chosen.spec.stories);
    }
    return result;
}

void build(ref const Lots lots, Chosen chosen) {
    pave(lots, materials.lot);
    types.build(*chosen.traits, lots, chosen.spec);
}

bool probePlaza(Turtle corner, ref const Root root) {
    bool plaza = probeRootVertex(corner, root) && root.isRisen();
    if (!plaza) {
        plaza = corner.probeRising().exists;
    }
    return plaza;
}

bool probeRoute(Turtle corner, ref const Lots lots, ref const Root root) {
    bool rooted = probeRootVertex(corner, root);
    if (rooted) {
        foreach (ref lot; lots.slice()) {
            ulong face = lot.site.probeHash(SitePart.face);
            if (face == root.face) {
                return true;
            }
        }
    }
    return false;
}

void lotAt(Turtle corner, ref const Lots lots, ref const Root root) {
    Turtle site = lots.items[0].site;
    bool plaza = probePlaza(corner, root);
    bool port = false;
    if (!plaza) {
        port = corner.probePort();
    }
    if (plaza) {
        pave(lots, materials.plaza);
        plant(lots);
    } else if (port) {
        paveAroundPort(lots, materials.plaza);
        plant(lots);
        portFrame(lots);
    } else {
        bool route = probeRoute(corner, lots, root);
        if (route) {
            Spec spec = {stories: ROUTE_BUILDING_STORIES, palette: zoning.route.palettes.items[0], front: FRONT, routeStories: ROUTE_STORIES};
            build(lots, Chosen(&zoning.route, spec));
        } else {
            rolledLot(site, lots, root);
        }
    }
}

void rolledLot(Turtle site, ref const Lots lots, ref const Root root) {
    const(District)* district = districtAt(site);
    bool park = site.rollPercent(district.parkPercent);
    if (park) {
        pave(lots, materials.park);
        bool pond = site.rollPercent(tuning.pondPercent);
        if (pond) {
            ponds(lots);
        } else {
            plant(lots);
        }
    } else {
        bool plaza = site.rollPercent(district.plazaPercent);
        if (plaza) {
            pave(lots, materials.plaza);
            bool fountain = site.rollPercent(tuning.fountainPercent);
            if (fountain) {
                fountains(lots);
            } else {
                plant(lots);
            }
        } else {
            bool parked = site.rollPercent(district.parkingPercent);
            MaybeIndex!LotRule rule = ruleFor(*district, cast(uint) lots.count);
            if (parked) {
                parking(lots);
            } else if (!rule.exists) {
                pave(lots, materials.plaza);
                plant(lots);
            } else {
                Chosen chosen = fitted(chosenFor(site, district.rules.items[rule.value]), site, root);
                if (chosen.spec.stories >= 1) {
                    build(lots, chosen);
                } else {
                    pave(lots, materials.plaza);
                    plant(lots);
                }
            }
        }
    }
}

Lot lotOf(Turtle quarter, Flags!LotMark marks) {
    Lot lot;
    lot.site = quarter;
    lot.bounds = RUN_BOUNDS;
    if (marks.has(LotMark.streetAfter)) {
        lot.bounds[Side.xLow] = Bound.street;
    }
    if (marks.has(LotMark.streetBefore)) {
        lot.bounds[Side.yLow] = Bound.street;
    }
    if (marks.has(LotMark.first) && marks.has(LotMark.streetBefore)) {
        lot.front = Side.yLow;
    }
    return lot;
}

void join(ref Lots run) {
    foreach (index; 0 .. run.count) {
        if (run.items[index].bounds[Side.xLow] == Bound.joined) {
            uint next = cast(uint)((index + 1) % run.count);
            run.items[index].joins[Side.xLow] = Join(MaybeIndex!Lot.of(next), Side.yLow);
            run.items[next].joins[Side.yLow] = Join(MaybeIndex!Lot.of(cast(uint) index), Side.xLow);
        }
    }
}

void lotsAt(ref const Turtle[AROUND] quarters, ref const Root root) {
    bool foot = probeRootVertex(quarters[0], root);
    if (foot && root.isRisen()) {
        connect(quarters[0], root.risen, root.tag, root.connection);
    }
    uint start = 0;
    bool paved = false;
    while (start < AROUND && !paved) {
        paved = probeStreet(quarters[start], root);
        if (!paved) {
            start += 1;
        }
    }
    Lots run;
    foreach (step; 0 .. AROUND) {
        uint index = (start + step) % AROUND;
        uint after = (index + 1) % AROUND;
        bool isolated = probeIsland(quarters[index], root);
        bool streetAfter = probeStreet(quarters[after], root);
        if (!isolated) {
            bool streetBefore = probeStreet(quarters[index], root);
            Flags!LotMark marks;
            marks.put(LotMark.streetBefore, streetBefore);
            marks.put(LotMark.streetAfter, streetAfter);
            marks.put(LotMark.first, run.count == 0);
            run.add(lotOf(quarters[index], marks));
        }
        if (streetAfter || step == AROUND - 1) {
            if (run.count > 0) {
                join(run);
                lotAt(quarters[0], run, root);
            }
            run = Lots.init;
        }
    }
}

void island(ref const Turtle[FACE_CORNERS] corners, ref const Root root) {
    Lots parts;
    foreach (corner; corners) {
        Lot lot;
        lot.site = corner;
        lot.bounds = ISLAND_BOUNDS;
        parts.add(lot);
    }
    parts.items[0].front = Side.yLow;
    Chosen chosen = fitted(chosenFor(corners[0], districtAt(corners[0]).island), corners[0], root);
    if (chosen.spec.stories >= 1) {
        build(parts, chosen);
    } else {
        pave(parts, materials.plaza);
        plant(parts);
    }
}

Root rootAt(Turtle site) {
    return Root(site.probeHash(SitePart.vertex), site.probeHash(SitePart.face));
}

Root risenRootAt(Turtle foot, ref const Risen risen, uint tag, Connection how) {
    return Root(foot.probeHash(SitePart.vertex), foot.probeHash(SitePart.face), risen, how, tag);
}

void tile(const(Api)* api, Site site, ref const Risen risen, ref const Root root) {
    tileAt(Turtle(api, site), root);
}

void tileAt(Turtle face, ref const Root root) {
    Turtle[FACE_CORNERS] corners = cornersOf(face);
    ulong mine = face.probeHash(SitePart.face);
    foreach (edge; corners) {
        bool paved = probeStreet(edge, root);
        if (paved) {
            ulong beside = edge.left().probeHash(SitePart.face);
            if (mine > beside) {
                street(edge, root);
            }
        }
    }
    foreach (corner; corners) {
        Turtle[AROUND] quarters = quartersOf(corner);
        bool owner = probeOwner(quarters);
        if (owner) {
            lotsAt(quarters, root);
        }
    }
    bool isolated = probeIsland(face, root);
    if (isolated) {
        island(corners, root);
    }
}
