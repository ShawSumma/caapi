module plugins.rooms.rooms;

import plugins.api.api : Box, Material, MaybeIndex, Span, Spot;
import plugins.api.flags : Flags;
import plugins.buildings.building : SIDES, Side, middle, width;
import plugins.connector.connector : Routing;
import plugins.rooms.levels : Biome, Hall, Level, Vents, rooms, tuning;
import plugins.turtle.turtle : Cell, PERCENT, Turtle, boxOf, floorDiv, higherOf, lowerOf;

enum int SEPARATION = 3;
enum uint MAZE_CELLS = 4;
enum int MAZE_PITCH = 3;
enum int MAZE_WIDTH = 2;
enum int DOOR_WIDTH = 2;
enum int MOST_DOOR_HEIGHT = 3;
enum int MIN_ROOM = 3;
enum int LOBBY = 5;
enum int SHAFT = 3;
enum int LIGHT_FROM = 2;
enum int LIGHT_EVERY = 4;
enum int ROOF = 1;
immutable int[2] RINGS = [1, 3];
enum int LEAST_ATTACHED_WALL = 4;
enum int NOWHERE_STEPS = 2;
enum int CHAPEL_RISE = 3;
enum int PODIUMS = 5;
enum int HANGING = 2;
enum int PODIUM_SIZE = 2;
enum int MURAL_HALF_WIDTH = 2;
enum int STAIR_ROWS = 4;
enum int STAIR_DEPTH = STAIR_ROWS + 1;
enum int GRID_OFFSET = 8;
enum int GRID_SIZE = 32;
enum size_t MOST_ROOMS = 64;
enum size_t MOST_STOPS = 32;

alias MaybeLayer = MaybeIndex!Level;

enum Axis : ubyte {
    x,
    y,
}

enum WallForm : ubyte {
    standing,
    missing,
}

enum QuarterKind : ubyte {
    plain,
    lobby,
    lobbyWithShaft,
}

enum FrameMark : ubyte {
    lobby,
    shaft,
    top,
    skirting,
}

alias Halls = Flags!Axis;
alias Owns = Flags!Side;

immutable Axis[2] AXES = [Axis.x, Axis.y];
immutable Cell[4] MOVES = [Cell(1, 0), Cell(-1, 0), Cell(0, 1), Cell(0, -1)];

enum Plan : ubyte {
    maze,
    lobby,
    rooms,
    solid,
    rings,
    chapel,
}

struct Region {
    Span x;
    Span y;

    Span span(Axis axis) const {
        if (axis == Axis.x) {
            return x;
        } else {
            return y;
        }
    }

    void setSpan(Axis axis, Span value) {
        if (axis == Axis.x) {
            x = value;
        } else {
            y = value;
        }
    }
}

struct Doors {
    int[2] at;
    uint count;
    WallForm form;

    static Doors one(int door) {
        return Doors([door, 0], 1);
    }

    const(int)[] slice() const return {
        return at[0 .. count];
    }
}

struct Grid {
    uint[GRID_SIZE] rows;

    bool opIndex(int x, int y) const {
        return (rows[x + GRID_OFFSET] & (1u << (y + GRID_OFFSET))) != 0;
    }

    void mark(int x, int y) {
        rows[x + GRID_OFFSET] |= 1u << (y + GRID_OFFSET);
    }
}

struct Forbid {
    uint[2] cells;

    bool has(Axis axis, int at) const {
        return (cells[axis] & (1u << (at + GRID_OFFSET))) != 0;
    }

    void mark(Axis axis, int at) {
        cells[axis] |= 1u << (at + GRID_OFFSET);
    }
}

struct Found {
    Region[MOST_ROOMS] rooms;
    size_t count;

    void add(Region region) {
        rooms[count] = region;
        count += 1;
    }

    const(Region)[] slice() const return {
        return rooms[0 .. count];
    }
}

struct Floor {
    uint layer;
    int base;

    ref const(Level) level() const {
        return rooms.levels.items[layer];
    }

    bool isTop() const {
        return layer == 0;
    }
}

struct Quarter {
    Turtle tower;
    QuarterKind kind;

    bool isLobby() const {
        return kind != QuarterKind.plain;
    }

    bool hasShaft() const {
        return kind == QuarterKind.lobbyWithShaft;
    }
}

struct Stair {
    MaybeLayer upper;
    uint lower;
    int x;
    int y;

    bool isPresent() const {
        return upper.exists;
    }

    bool isOn(uint layer) const {
        return isPresent() && (upper.value == layer || lower == layer);
    }
}

struct Frame {
    Turtle tower;
    int base;
    int room;
    int doorHeight;
    int hallWidth;
    int far;
    const(Biome)* biome;
    Hall hall;
    Halls halls;
    Flags!FrameMark marks;
    int x0;
    int y0;
    Region region;
    Grid nearDoors;
    Owns owns;

    bool isLobby() const {
        return marks.has(FrameMark.lobby);
    }

    bool hasShaft() const {
        return marks.has(FrameMark.shaft);
    }

    bool isTop() const {
        return marks.has(FrameMark.top);
    }

    bool hasSkirting() const {
        return marks.has(FrameMark.skirting);
    }
}

bool rollChance(ref const Frame f, double odds) {
    return f.tower.pick(PERCENT) + 1 <= odds * PERCENT;
}

Box line(Axis axis, int at, Span span, Span z) {
    if (axis == Axis.x) {
        return boxOf(Span(at, at), span, z);
    } else {
        return boxOf(span, Span(at, at), z);
    }
}

Axis other(Axis axis) {
    if (axis == Axis.x) {
        return Axis.y;
    } else {
        return Axis.x;
    }
}

Axis axisOf(Side side) {
    if (side == Side.xLow || side == Side.xHigh) {
        return Axis.x;
    } else {
        return Axis.y;
    }
}

bool isLow(Side side) {
    return side == Side.xLow || side == Side.yLow;
}

int edgeOn(Span span, Side side) {
    if (isLow(side)) {
        return span.low;
    } else {
        return span.high;
    }
}

Span roomZ(ref const Frame f) {
    return Span(f.base + 1, f.base + f.room);
}

int ceilingZ(ref const Frame f) {
    return f.base + f.room + 1;
}

int origin(Halls halls, Axis axis, ref const Level level) {
    if (halls.has(axis)) {
        return level.hallWidth + 1;
    } else {
        return 1;
    }
}

struct Pieces {
    Region[2] items;
    size_t count;

    void add(Region region) {
        items[count] = region;
        count += 1;
    }

    const(Region)[] slice() const return {
        return items[0 .. count];
    }
}

Pieces outsideShaft(ref const Frame f, Region area) {
    Pieces pieces;
    if (!f.hasShaft()) {
        pieces.add(area);
    } else {
        if (area.x.high > SHAFT) {
            pieces.add(Region(Span(higherOf(area.x.low, SHAFT + 1), area.x.high), area.y));
        }
        if (area.x.low <= SHAFT && area.y.high > SHAFT) {
            pieces.add(Region(Span(area.x.low, lowerOf(area.x.high, SHAFT)), Span(higherOf(area.y.low, SHAFT + 1), area.y.high)));
        }
    }
    return pieces;
}

struct Spans {
    Span[1] items;
    size_t count;

    const(Span)[] slice() const return {
        return items[0 .. count];
    }
}

Spans outsideLobby(ref const Frame f, int at, Span span) {
    Spans spans;
    if (!f.isLobby() || at > LOBBY) {
        spans.items[0] = span;
        spans.count = 1;
    } else if (span.high > LOBBY) {
        spans.items[0] = Span(higherOf(span.low, LOBBY + 1), span.high);
        spans.count = 1;
    }
    return spans;
}

void doorway(ref Frame f, Axis axis, int at, int door) {
    f.tower.paint(Material.none, line(axis, at, Span(door, door + DOOR_WIDTH - 1), Span(f.base + 1, f.base + f.doorHeight)));
    foreach (along; door .. door + DOOR_WIDTH) {
        foreach (across; at - 1 .. at + 2) {
            if (axis == Axis.x) {
                f.nearDoors.mark(across, along);
            } else {
                f.nearDoors.mark(along, across);
            }
        }
    }
}

void wall(ref Frame f, Axis axis, int at, Span span, const(int)[] doors) {
    foreach (piece; outsideLobby(f, at, span).slice()) {
        f.tower.paint(f.biome.wall, line(axis, at, piece, roomZ(f)));
        if (f.hasSkirting()) {
            f.tower.paint(f.biome.trim, line(axis, at, piece, Span(f.base + 1, f.base + 1)));
        }
        if (f.biome.vents == Vents.some) {
            bool vented = rollChance(f, tuning.ventOdds);
            if (vented) {
                int vent = f.tower.pickBetween(piece.low, piece.high);
                f.tower.paint(rooms.vent, line(axis, at, Span(vent, vent), Span(f.base + f.room, f.base + f.room)));
            }
        }
    }
    foreach (door; doors) {
        doorway(f, axis, at, door);
    }
}

void slab(ref const Frame f, Material material, Region area, int z) {
    foreach (piece; outsideShaft(f, area).slice()) {
        f.tower.paint(material, boxOf(piece.x, piece.y, Span(z, z)));
    }
}

Pieces bands(ref const Frame f) {
    Pieces list;
    if (f.halls.has(Axis.y)) {
        list.add(Region(Span(0, f.far), Span(0, f.hallWidth - 1)));
    }
    if (f.halls.has(Axis.x)) {
        list.add(Region(Span(0, f.hallWidth - 1), Span(0, f.far)));
    }
    return list;
}

void shell(ref const Frame f) {
    Region whole = Region(Span(0, f.far), Span(0, f.far));
    slab(f, f.biome.floor, whole, f.base);
    foreach (piece; outsideShaft(f, whole).slice()) {
        f.tower.paint(Material.none, boxOf(piece.x, piece.y, roomZ(f)));
    }
    slab(f, f.biome.ceiling, whole, ceilingZ(f));
    foreach (band; bands(f).slice()) {
        slab(f, f.hall.floor, band, f.base);
        slab(f, f.hall.ceiling, band, ceilingZ(f));
    }
    if (f.isTop()) {
        slab(f, rooms.roof, whole, ceilingZ(f) + ROOF);
    } else if (f.hasShaft()) {
        f.tower.paint(Material.none, boxOf(Span(0, SHAFT), Span(0, SHAFT), Span(f.base, ceilingZ(f) + SEPARATION)));
    }
}

int hallEdge(ref const Frame f, Axis axis) {
    if (f.halls.has(axis)) {
        return f.hallWidth;
    } else {
        return 0;
    }
}

struct PlannedWall {
    Axis axis;
    int at;
    Span span;
    Doors doors;
}

Doors wallDoors(ref const Frame f, Axis axis, Doors doors) {
    if (f.halls.has(axis)) {
        return Doors.init;
    } else {
        return doors;
    }
}

Forbid walls(ref Frame f, ref const Doors[4] lines) {
    int fromX = hallEdge(f, Axis.x);
    int fromY = hallEdge(f, Axis.y);
    PlannedWall[4] sides;
    sides[Side.yLow] = PlannedWall(Axis.y, fromY, Span(fromX, f.far), wallDoors(f, Axis.y, lines[Side.yLow]));
    sides[Side.xLow] = PlannedWall(Axis.x, fromX, Span(fromY, f.far), wallDoors(f, Axis.x, lines[Side.xLow]));
    sides[Side.xHigh] = PlannedWall(Axis.x, f.far, Span(fromY, f.far), lines[Side.xHigh]);
    sides[Side.yHigh] = PlannedWall(Axis.y, f.far, Span(fromX, f.far), lines[Side.yHigh]);
    Forbid forbid;
    foreach (side; SIDES) {
        PlannedWall planned = sides[side];
        if (planned.doors.form == WallForm.standing) {
            wall(f, planned.axis, planned.at, planned.span, planned.doors.slice());
            foreach (door; planned.doors.slice()) {
                forbid.mark(other(planned.axis), door);
                forbid.mark(other(planned.axis), door + 1);
            }
        }
    }
    return forbid;
}

void split(ref Frame f, Region region, Forbid forbid, ref Found found, int depth) {
    Axis[2] axes;
    uint axisCount = 0;
    foreach (axis; AXES) {
        if (width(region.span(axis)) >= 2 * MIN_ROOM + 1) {
            axes[axisCount] = axis;
            axisCount += 1;
        }
    }
    bool big = rollChance(f,f.biome.big * lowerOf(depth, 1));
    if (big || axisCount == 0) {
        found.add(region);
    } else {
        Axis axis = axes[f.tower.pick(axisCount)];
        if (axisCount == 2 && width(region.x) > width(region.y)) {
            axis = Axis.x;
        } else if (axisCount == 2 && width(region.x) < width(region.y)) {
            axis = Axis.y;
        }
        Span span = region.span(axis);
        int[GRID_SIZE] candidates;
        uint candidateCount = 0;
        foreach (at; span.low + MIN_ROOM .. span.high - MIN_ROOM + 1) {
            if (!forbid.has(axis, at)) {
                candidates[candidateCount] = at;
                candidateCount += 1;
            }
        }
        if (candidateCount == 0) {
            found.add(region);
        } else {
            int at = candidates[f.tower.pick(candidateCount)];
            Span along = region.span(other(axis));
            Forbid inner = forbid;
            bool open = rollChance(f,f.biome.open);
            if (!open) {
                int door = f.tower.pickBetween(along.low, along.high - DOOR_WIDTH + 1);
                int[1] doors = [door];
                wall(f, axis, at, along, doors[]);
                inner.mark(other(axis), door);
                inner.mark(other(axis), door + 1);
            }
            Region low = region;
            Region high = region;
            low.setSpan(axis, Span(span.low, at - 1));
            high.setSpan(axis, Span(at + 1, span.high));
            split(f, low, inner, found, depth + 1);
            split(f, high, inner, found, depth + 1);
        }
    }
}

void hallDoors(ref Frame f, ref const Found found) {
    foreach (room; found.slice()) {
        if (f.halls.has(Axis.y) && room.y.low == f.y0) {
            bool door = rollChance(f,f.biome.hallDoors);
            if (door) {
                doorway(f, Axis.y, f.hallWidth, f.tower.pickBetween(room.x.low, room.x.high - DOOR_WIDTH + 1));
            }
        }
        if (f.halls.has(Axis.x) && room.x.low == f.x0) {
            bool door = rollChance(f,f.biome.hallDoors);
            if (door) {
                doorway(f, Axis.x, f.hallWidth, f.tower.pickBetween(room.y.low, room.y.high - DOOR_WIDTH + 1));
            }
        }
    }
}

bool isShaft(ref const Frame f, int x, int y) {
    return f.hasShaft() && x <= SHAFT && y <= SHAFT;
}

void light(ref const Frame f, Material material, int x, int y) {
    if (material != Material.none && !isShaft(f, x, y)) {
        f.tower.paint(material, boxOf(Span(x, x), Span(y, y), Span(ceilingZ(f), ceilingZ(f))));
    }
}

void skylight(ref const Frame f, int x, int y) {
    if (!isShaft(f, x, y)) {
        f.tower.paint(rooms.window, boxOf(Span(x, x), Span(y, y), Span(ceilingZ(f), ceilingZ(f) + ROOF)));
        f.tower.paint(rooms.sunlight, boxOf(Span(x, x), Span(y, y), Span(f.base, f.base)));
    }
}

void lamp(ref const Frame f, Material material, double odds, int x, int y) {
    bool open = false;
    if (f.isTop()) {
        open = rollChance(f,odds);
    }
    if (open) {
        skylight(f, x, y);
    } else {
        light(f, material, x, y);
    }
}

Span sideSpan(Region room, Side side) {
    if (axisOf(side) == Axis.x) {
        return room.y;
    } else {
        return room.x;
    }
}

void boxes(ref const Frame f, Region room) {
    Side side = SIDES[f.tower.pick(SIDES.length)];
    Span span = sideSpan(room, side);
    if (width(span) >= LEAST_ATTACHED_WALL) {
        int from = f.tower.pickBetween(span.low, span.high - 1);
        Cell[2] cells;
        foreach (step; 0 .. 2) {
            int x = from + step;
            int y = from + step;
            if (axisOf(side) == Axis.x) {
                x = edgeOn(room.x, side);
            } else {
                y = edgeOn(room.y, side);
            }
            cells[step] = Cell(x, y);
        }
        if (!f.nearDoors[cells[0].x, cells[0].y] && !f.nearDoors[cells[1].x, cells[1].y]) {
            int top = f.base + f.tower.pickBetween(2, lowerOf(f.biome.boxHeight, f.room));
            foreach (cell; cells) {
                f.tower.paint(f.biome.boxes, boxOf(Span(cell.x, cell.x), Span(cell.y, cell.y), Span(f.base + 1, top)));
            }
        }
    }
}

void shelves(ref const Frame f, Region room) {
    if (width(room.x) >= 5 && width(room.y) >= 5) {
        for (int y = room.y.low + 1; y <= room.y.high - 1; y += 2) {
            f.tower.paint(f.biome.shelf, boxOf(Span(room.x.low + 1, room.x.high - 1), Span(y, y), Span(f.base + 1, f.base + f.doorHeight)));
        }
    }
}

void furnish(ref Frame f, ref const Found found) {
    hallDoors(f, found);
    foreach (room; found.slice()) {
        if (f.biome.roomFloors.count > 0) {
            f.tower.paint(f.biome.roomFloors.items[f.tower.pick(f.biome.roomFloors.count)], boxOf(room.x, room.y, Span(f.base, f.base)));
        }
        lamp(f, f.biome.light, f.biome.skylight, middle(room.x), middle(room.y));
        if (f.biome.damp != Material.none) {
            bool damp = rollChance(f, tuning.dampOdds);
            if (damp) {
                int x = f.tower.pickBetween(room.x.low, room.x.high - 1);
                int y = f.tower.pickBetween(room.y.low, room.y.high - 1);
                f.tower.paint(f.biome.damp, boxOf(Span(x, x + 1), Span(y, y + 1), Span(f.base, f.base)));
            }
        }
        if (f.biome.shelf != Material.none) {
            shelves(f, room);
        }
        if (f.biome.boxes != Material.none) {
            bool boxed = rollChance(f,f.biome.boxOdds);
            if (boxed) {
                boxes(f, room);
            }
        }
    }
    foreach (band; bands(f).slice()) {
        for (int at = LIGHT_FROM; at <= f.far; at += LIGHT_EVERY) {
            if (band.x.high == f.far) {
                lamp(f, f.hall.light, f.hall.skylight, at, 0);
            } else {
                lamp(f, f.hall.light, f.hall.skylight, 0, at);
            }
        }
    }
}

Span mazeSpan(ref const Frame f, int index) {
    int low = index * MAZE_PITCH + 1;
    int high = low + MAZE_WIDTH - 1;
    return Span(low, lowerOf(high, f.far));
}

Box mazeGap(ref const Frame f, Axis axis, int i, int j) {
    int at = (i + 1) * MAZE_PITCH;
    if (axis == Axis.x) {
        return boxOf(Span(at, at), mazeSpan(f, j), roomZ(f));
    } else {
        return boxOf(mazeSpan(f, j), Span(at, at), roomZ(f));
    }
}

uint mazeKey(int i, int j) {
    return i * MAZE_CELLS + j;
}

struct Maze {
    uint[MAZE_CELLS * MAZE_CELLS] exits;

    void open(ref const Frame f, Cell a, Cell b) {
        exits[mazeKey(a.x, a.y)] += 1;
        exits[mazeKey(b.x, b.y)] += 1;
        if (a.x != b.x) {
            f.tower.paint(Material.none, mazeGap(f, Axis.x, lowerOf(a.x, b.x), a.y));
        } else {
            f.tower.paint(Material.none, mazeGap(f, Axis.y, lowerOf(a.y, b.y), a.x));
        }
    }
}

void maze(ref Frame f, ref const Doors[4] lines) {
    int cells = MAZE_CELLS;
    f.tower.paint(f.biome.wall, boxOf(Span(0, f.far), Span(0, f.far), roomZ(f)));
    foreach (i; 0 .. cells) {
        foreach (j; 0 .. cells) {
            f.tower.paint(Material.none, boxOf(mazeSpan(f, i), mazeSpan(f, j), roomZ(f)));
        }
    }
    Maze carved;
    uint visited = 1u << mazeKey(0, 0);
    Cell[MAZE_CELLS * MAZE_CELLS] trail;
    size_t depth = 1;
    while (depth > 0) {
        Cell at = trail[depth - 1];
        Cell[4] moves;
        uint moveCount = 0;
        foreach (move; MOVES) {
            int i = at.x + move.x;
            int j = at.y + move.y;
            if (i >= 0 && i < cells && j >= 0 && j < cells && (visited & (1u << mazeKey(i, j))) == 0) {
                moves[moveCount] = Cell(i, j);
                moveCount += 1;
            }
        }
        if (moveCount == 0) {
            depth -= 1;
        } else {
            Cell chosen = moves[f.tower.pick(moveCount)];
            visited |= 1u << mazeKey(chosen.x, chosen.y);
            carved.open(f, at, chosen);
            trail[depth] = chosen;
            depth += 1;
        }
    }
    foreach (i; 0 .. cells - 1) {
        foreach (j; 0 .. cells) {
            bool loopAcross = rollChance(f, tuning.mazeLoopOdds);
            if (loopAcross) {
                carved.open(f, Cell(i, j), Cell(i + 1, j));
            }
            bool loopAlong = rollChance(f, tuning.mazeLoopOdds);
            if (loopAlong) {
                carved.open(f, Cell(j, i), Cell(j, i + 1));
            }
        }
    }
    bool roomy = rollChance(f, tuning.mazeRoomOdds);
    if (roomy) {
        int i = f.tower.pickBetween(0, cells - 2);
        int j = f.tower.pickBetween(0, cells - 2);
        f.tower.paint(Material.none, boxOf(Span(mazeSpan(f, i).low, mazeSpan(f, i + 1).high), Span(mazeSpan(f, j).low, mazeSpan(f, j + 1).high), roomZ(f)));
    }
    foreach (side; SIDES) {
        Axis axis = axisOf(side);
        if (isLow(side) || f.owns.has(side)) {
            int at = 0;
            if (!isLow(side)) {
                at = f.far;
                f.tower.paint(f.biome.wall, line(axis, at, Span(0, f.far), roomZ(f)));
            }
            foreach (slot; lines[side].slice()) {
                f.tower.paint(Material.none, line(axis, at, mazeSpan(f, slot), roomZ(f)));
            }
        }
    }
    foreach (i; 0 .. cells) {
        foreach (j; 0 .. cells) {
            Span x = mazeSpan(f, i);
            Span y = mazeSpan(f, j);
            bool lit = rollChance(f, tuning.mazeLightOdds);
            if (lit) {
                light(f, f.biome.light, x.low, y.low);
            }
            if (carved.exits[mazeKey(i, j)] == 1) {
                bool nowhere = rollChance(f,f.biome.nowhere);
                if (nowhere) {
                    foreach (step; 1 .. NOWHERE_STEPS + 1) {
                        f.tower.paint(f.biome.stair, boxOf(Span(x.low + step - 1, x.low + step - 1), y, Span(f.base + 1, f.base + step)));
                    }
                }
            }
        }
    }
}

void chapel(ref Frame f) {
    Region region = f.region;
    int depth = SEPARATION;
    int floor = f.base - depth;
    int top = ceilingZ(f) + CHAPEL_RISE;
    Region around = Region(Span(region.x.low - 1, region.x.high + 1), Span(region.y.low - 1, region.y.high + 1));
    f.tower.paint(f.biome.wall, boxOf(around.x, around.y, Span(floor, f.base)));
    f.tower.paint(f.biome.wall, boxOf(around.x, around.y, Span(ceilingZ(f), top)));
    f.tower.paint(Material.none, boxOf(region.x, region.y, Span(floor + 1, top - 1)));
    f.tower.paint(f.biome.floor, boxOf(region.x, region.y, Span(floor, floor)));
    f.tower.paint(f.biome.ceiling, boxOf(region.x, region.y, Span(top, top)));
    f.tower.paint(rooms.roof, boxOf(around.x, around.y, Span(top + ROOF, top + ROOF)));
    Span steps = Span(region.y.low, region.y.low + 1);
    foreach (step; 1 .. depth) {
        int x = region.x.low + step - 1;
        f.tower.paint(f.biome.stair, boxOf(Span(x, x), steps, Span(floor + 1, f.base - step)));
    }
    foreach (_; 0 .. PODIUMS) {
        int x = f.tower.pickBetween(region.x.low + depth, region.x.high - PODIUM_SIZE + 1);
        int y = f.tower.pickBetween(region.y.low + 2, region.y.high - PODIUM_SIZE + 1);
        f.tower.paint(f.biome.wall, boxOf(Span(x, x + PODIUM_SIZE - 1), Span(y, y + PODIUM_SIZE - 1), Span(floor + 1, floor + f.tower.pickBetween(1, depth + 2))));
    }
    foreach (_; 0 .. HANGING) {
        int x = f.tower.pickBetween(region.x.low + 1, region.x.high - PODIUM_SIZE + 1);
        int y = f.tower.pickBetween(region.y.low + 2, region.y.high - PODIUM_SIZE + 1);
        f.tower.paint(f.biome.wall, boxOf(Span(x, x + PODIUM_SIZE - 1), Span(y, y + PODIUM_SIZE - 1), Span(top - f.tower.pickBetween(1, CHAPEL_RISE), top - 1)));
    }
    int x = middle(region.x);
    int y = middle(region.y);
    f.tower.paint(rooms.window, boxOf(Span(x, x + 1), Span(y, y + 1), Span(top, top + ROOF)));
    f.tower.paint(rooms.sunlight, boxOf(Span(x, x + 1), Span(y, y + 1), Span(floor, floor)));
    int farWall = region.y.high + 1;
    Span mural = Span(middle(region.x) - MURAL_HALF_WIDTH, middle(region.x) + MURAL_HALF_WIDTH);
    f.tower.paint(rooms.mural, boxOf(mural, Span(farWall, farWall), Span(f.base + 1, f.base + f.room)));
    f.tower.paint(rooms.muralLine, boxOf(mural, Span(farWall, farWall), Span(f.base + 2, f.base + 2)));
    f.tower.paint(rooms.muralLine, boxOf(Span(middle(region.x), middle(region.x)), Span(farWall, farWall), Span(f.base + 1, f.base + f.room)));
}

void rings(ref Frame f) {
    foreach (inset; RINGS) {
        Span x = Span(f.region.x.low + inset, f.region.x.high - inset);
        Span y = Span(f.region.y.low + inset, f.region.y.high - inset);
        if (width(x) >= 3 && width(y) >= 3) {
            f.tower.paint(f.biome.wall, boxOf(x, y, roomZ(f)));
            f.tower.paint(Material.none, boxOf(Span(x.low + 1, x.high - 1), Span(y.low + 1, y.high - 1), roomZ(f)));
            Side side = SIDES[f.tower.pick(SIDES.length)];
            Axis axis = axisOf(side);
            int at = x.low;
            if (side == Side.xHigh) {
                at = x.high;
            } else if (side == Side.yLow) {
                at = y.low;
            } else if (side == Side.yHigh) {
                at = y.high;
            }
            Span along = x;
            if (axis == Axis.x) {
                along = y;
            }
            if (width(along) >= DOOR_WIDTH + 2) {
                f.tower.paint(Material.none, line(axis, at, Span(along.low + 1, along.low + DOOR_WIDTH), Span(f.base + 1, f.base + f.doorHeight)));
            }
        }
    }
}

void stairs(ref const Frame lower, ref const Frame upper, Stair stair, Routing routing) {
    int rise = upper.base - lower.base;
    int x0 = stair.x;
    int y0 = stair.y;
    int first = floorDiv(rise + 2, 2);
    Span lowRows = Span(y0, y0 + 1);
    Span highRows = Span(y0 + 2, y0 + 3);
    Spot[MOST_STOPS] stops;
    size_t count = 0;
    void stop(float x, float y, float z) {
        stops[count] = Spot(x, y, z);
        count += 1;
    }
    void tread(Span x, Span rows, int height) {
        lower.tower.paint(lower.biome.stair, boxOf(x, rows, Span(lower.base + height, lower.base + height)));
    }
    void enclose(Span x, Span y) {
        upper.tower.paint(upper.biome.wall, boxOf(x, y, Span(upper.base + 1, upper.base + upper.room)));
    }
    lower.tower.paint(Material.none, boxOf(Span(x0, x0 + first + 1), Span(y0, y0 + STAIR_ROWS - 1), Span(lower.base + 1, upper.base)));
    stop(x0 + 0.5f, y0 + 3, lower.base + 1);
    foreach (height; 1 .. first + 1) {
        tread(Span(x0 + height - 1, x0 + height - 1), lowRows, height);
        stop(x0 + height - 0.5f, y0 + 1, lower.base + height + 1);
    }
    tread(Span(x0 + first, x0 + first + 1), Span(y0, y0 + STAIR_ROWS - 1), first);
    stop(x0 + first + 1, y0 + 1, lower.base + first + 1);
    stop(x0 + first + 1, y0 + 3, lower.base + first + 1);
    foreach (height; first + 1 .. rise + 1) {
        int x = x0 + 2 * first - height;
        tread(Span(x, x), highRows, height);
        stop(x + 0.5f, y0 + 3, lower.base + height + 1);
    }
    int arrival = x0 + 2 * first - rise - 1;
    if (arrival >= x0) {
        upper.tower.paint(upper.biome.floor, boxOf(Span(x0, arrival), highRows, Span(upper.base, upper.base)));
    }
    enclose(Span(x0, x0), lowRows);
    enclose(Span(x0 + 1, x0 + first + 1), Span(y0 + STAIR_ROWS, y0 + STAIR_ROWS));
    enclose(Span(x0 + first + 2, x0 + first + 2), Span(y0, y0 + STAIR_ROWS - 1));
    stop(x0 + 0.5f, y0 + 3, upper.base + 1);
    stop(x0 + 0.5f, y0 + STAIR_ROWS + 0.5f, upper.base + 1);
    if (routing == Routing.routed) {
        foreach (spot; stops[0 .. count]) {
            lower.tower.stop(spot.x, spot.y, spot.z);
        }
    }
}

Frame frameOf(ref const Quarter q, Halls halls, Floor floor, const(Biome)* biome, ref const Stair stair, Plan plan, Owns owns) {
    const(Level)* level = &floor.level();
    int far = q.tower.column().high;
    int x0 = origin(halls, Axis.x, *level);
    int y0 = origin(halls, Axis.y, *level);
    int regionY = y0;
    if (stair.isOn(floor.layer)) {
        regionY = stair.y + STAIR_DEPTH;
    }
    Frame f;
    f.tower = q.tower;
    f.base = floor.base;
    f.room = level.room;
    f.doorHeight = lowerOf(MOST_DOOR_HEIGHT, level.room);
    f.hallWidth = level.hallWidth;
    f.far = far;
    f.biome = biome;
    f.hall = level.hall;
    f.halls = halls;
    f.marks.put(FrameMark.lobby, plan == Plan.lobby);
    f.marks.put(FrameMark.shaft, q.hasShaft() && !level.isMaze());
    f.marks.put(FrameMark.top, floor.isTop());
    f.x0 = x0;
    f.y0 = y0;
    f.region = Region(Span(x0, far - 1), Span(regionY, far - 1));
    f.owns = owns;
    if (biome.trim != Material.none) {
        bool skirted = rollChance(f, tuning.skirtingOdds);
        f.marks.put(FrameMark.skirting, skirted);
    }
    return f;
}

void paintFloor(ref Frame f, ref const Doors[4] lines, Plan plan) {
    shell(f);
    if (plan == Plan.maze) {
        maze(f, lines);
    } else {
        Forbid forbid = walls(f, lines);
        if (plan == Plan.lobby) {
            light(f, f.biome.light, f.far - 2, f.far - 2);
        } else if (plan == Plan.solid) {
            f.tower.paint(f.biome.wall, boxOf(f.region.x, f.region.y, roomZ(f)));
        } else if (plan == Plan.rings) {
            rings(f);
            Found whole;
            whole.add(f.region);
            furnish(f, whole);
        } else if (plan == Plan.chapel) {
            chapel(f);
        } else {
            Found found;
            split(f, f.region, forbid, found, 0);
            furnish(f, found);
        }
    }
}
