module plugins.rooms.rooms;

import plugins.api.api : Box, Material;
import plugins.api.flags : Flags;
import plugins.buildings.building : SIDES, Side;
import plugins.rooms.levels : Biome, Hall, LAYERS, Level, Vents;
import plugins.turtle.turtle : PERCENT, Turtle, boxOf, floorDiv, higherOf, lowerOf;

enum int SEPARATION = 3;
enum uint MAZE_CELLS = 4;
enum int MAZE_PITCH = 3;
enum int MAZE_WIDTH = 2;
enum double MAZE_LOOP_ODDS = 0.1;
enum double MAZE_ROOM_ODDS = 0.25;
enum double MAZE_LIGHT_ODDS = 0.15;
enum int DOOR_WIDTH = 2;
enum int MOST_DOOR_HEIGHT = 3;
enum int MIN_ROOM = 3;
enum int LOBBY = 5;
enum int SHAFT = 3;
enum int LIGHT_FROM = 2;
enum int LIGHT_EVERY = 4;
enum double SKIRTING_ODDS = 0.5;
enum double DAMP_ODDS = 0.3;
enum double VENT_ODDS = 0.15;
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
enum uint NO_STAIR = uint.max;

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
immutable int[2][4] MOVES = [[1, 0], [-1, 0], [0, 1], [0, -1]];

enum Plan : ubyte {
    maze,
    lobby,
    rooms,
    solid,
    rings,
    chapel,
}

struct Region {
    int[2] x;
    int[2] y;

    int[2] span(Axis axis) const {
        if (axis == Axis.x) {
            return x;
        } else {
            return y;
        }
    }

    void setSpan(Axis axis, int[2] value) {
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

    ref immutable(Level) level() const {
        return LAYERS[layer];
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
    uint upper = NO_STAIR;
    uint lower;
    int x;
    int y;

    bool isPresent() const {
        return upper != NO_STAIR;
    }

    bool isOn(uint layer) const {
        return isPresent() && (upper == layer || lower == layer);
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

bool chance(ref const Frame f, double odds) {
    return f.tower.pick(PERCENT) + 1 <= odds * PERCENT;
}

int between(ref const Frame f, int low, int high) {
    return low + cast(int) f.tower.pick(high - low + 1);
}

int width(int[2] span) {
    return span[1] - span[0] + 1;
}

int middle(int[2] span) {
    return floorDiv(span[0] + span[1], 2);
}

Box line(Axis axis, int at, int[2] span, int[2] z) {
    if (axis == Axis.x) {
        return boxOf([at, at], span, z);
    } else {
        return boxOf(span, [at, at], z);
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

int edgeOn(int[2] span, Side side) {
    if (isLow(side)) {
        return span[0];
    } else {
        return span[1];
    }
}

int[2] roomZ(ref const Frame f) {
    return [f.base + 1, f.base + f.room];
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
        if (area.x[1] > SHAFT) {
            pieces.add(Region([higherOf(area.x[0], SHAFT + 1), area.x[1]], area.y));
        }
        if (area.x[0] <= SHAFT && area.y[1] > SHAFT) {
            pieces.add(Region([area.x[0], lowerOf(area.x[1], SHAFT)], [higherOf(area.y[0], SHAFT + 1), area.y[1]]));
        }
    }
    return pieces;
}

struct Spans {
    int[2][1] items;
    size_t count;

    const(int[2])[] slice() const return {
        return items[0 .. count];
    }
}

Spans outsideLobby(ref const Frame f, int at, int[2] span) {
    Spans spans;
    if (!f.isLobby() || at > LOBBY) {
        spans.items[0] = span;
        spans.count = 1;
    } else if (span[1] > LOBBY) {
        spans.items[0] = [higherOf(span[0], LOBBY + 1), span[1]];
        spans.count = 1;
    }
    return spans;
}

void doorway(ref Frame f, Axis axis, int at, int door) {
    f.tower.paint(Material.none, line(axis, at, [door, door + DOOR_WIDTH - 1], [f.base + 1, f.base + f.doorHeight]));
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

void wall(ref Frame f, Axis axis, int at, int[2] span, const(int)[] doors) {
    foreach (piece; outsideLobby(f, at, span).slice()) {
        f.tower.paint(f.biome.wall, line(axis, at, piece, roomZ(f)));
        if (f.hasSkirting()) {
            f.tower.paint(f.biome.trim, line(axis, at, piece, [f.base + 1, f.base + 1]));
        }
        if (f.biome.vents == Vents.some && chance(f, VENT_ODDS)) {
            int vent = between(f, piece[0], piece[1]);
            f.tower.paint(Material.steel, line(axis, at, [vent, vent], [f.base + f.room, f.base + f.room]));
        }
    }
    foreach (door; doors) {
        doorway(f, axis, at, door);
    }
}

void slab(ref const Frame f, Material material, Region area, int z) {
    foreach (piece; outsideShaft(f, area).slice()) {
        f.tower.paint(material, boxOf(piece.x, piece.y, [z, z]));
    }
}

Pieces bands(ref const Frame f) {
    Pieces list;
    if (f.halls.has(Axis.y)) {
        list.add(Region([0, f.far], [0, f.hallWidth - 1]));
    }
    if (f.halls.has(Axis.x)) {
        list.add(Region([0, f.hallWidth - 1], [0, f.far]));
    }
    return list;
}

void shell(ref const Frame f) {
    Region whole = Region([0, f.far], [0, f.far]);
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
        slab(f, Material.steel, whole, ceilingZ(f) + ROOF);
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
    int[2] span;
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
    sides[Side.yLow] = PlannedWall(Axis.y, fromY, [fromX, f.far], wallDoors(f, Axis.y, lines[Side.yLow]));
    sides[Side.xLow] = PlannedWall(Axis.x, fromX, [fromY, f.far], wallDoors(f, Axis.x, lines[Side.xLow]));
    sides[Side.xHigh] = PlannedWall(Axis.x, f.far, [fromY, f.far], lines[Side.xHigh]);
    sides[Side.yHigh] = PlannedWall(Axis.y, f.far, [fromX, f.far], lines[Side.yHigh]);
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
    if (chance(f, f.biome.big * lowerOf(depth, 1)) || axisCount == 0) {
        found.add(region);
    } else {
        Axis axis = axes[f.tower.pick(axisCount)];
        if (axisCount == 2 && width(region.x) > width(region.y)) {
            axis = Axis.x;
        } else if (axisCount == 2 && width(region.x) < width(region.y)) {
            axis = Axis.y;
        }
        int[2] span = region.span(axis);
        int[GRID_SIZE] candidates;
        uint candidateCount = 0;
        foreach (at; span[0] + MIN_ROOM .. span[1] - MIN_ROOM + 1) {
            if (!forbid.has(axis, at)) {
                candidates[candidateCount] = at;
                candidateCount += 1;
            }
        }
        if (candidateCount == 0) {
            found.add(region);
        } else {
            int at = candidates[f.tower.pick(candidateCount)];
            int[2] along = region.span(other(axis));
            Forbid inner = forbid;
            if (!chance(f, f.biome.open)) {
                int door = between(f, along[0], along[1] - DOOR_WIDTH + 1);
                int[1] doors = [door];
                wall(f, axis, at, along, doors[]);
                inner.mark(other(axis), door);
                inner.mark(other(axis), door + 1);
            }
            Region low = region;
            Region high = region;
            low.setSpan(axis, [span[0], at - 1]);
            high.setSpan(axis, [at + 1, span[1]]);
            split(f, low, inner, found, depth + 1);
            split(f, high, inner, found, depth + 1);
        }
    }
}

void hallDoors(ref Frame f, ref const Found found) {
    foreach (room; found.slice()) {
        if (f.halls.has(Axis.y) && room.y[0] == f.y0 && chance(f, f.biome.hallDoors)) {
            doorway(f, Axis.y, f.hallWidth, between(f, room.x[0], room.x[1] - DOOR_WIDTH + 1));
        }
        if (f.halls.has(Axis.x) && room.x[0] == f.x0 && chance(f, f.biome.hallDoors)) {
            doorway(f, Axis.x, f.hallWidth, between(f, room.y[0], room.y[1] - DOOR_WIDTH + 1));
        }
    }
}

bool isShaft(ref const Frame f, int x, int y) {
    return f.hasShaft() && x <= SHAFT && y <= SHAFT;
}

void light(ref const Frame f, Material material, int x, int y) {
    if (material != Material.none && !isShaft(f, x, y)) {
        f.tower.paint(material, boxOf([x, x], [y, y], [ceilingZ(f), ceilingZ(f)]));
    }
}

void skylight(ref const Frame f, int x, int y) {
    if (!isShaft(f, x, y)) {
        f.tower.paint(Material.glass, boxOf([x, x], [y, y], [ceilingZ(f), ceilingZ(f) + ROOF]));
        f.tower.paint(Material.sunlight, boxOf([x, x], [y, y], [f.base, f.base]));
    }
}

void lamp(ref const Frame f, Material material, double odds, int x, int y) {
    if (f.isTop() && chance(f, odds)) {
        skylight(f, x, y);
    } else {
        light(f, material, x, y);
    }
}

int[2] sideSpan(Region room, Side side) {
    if (axisOf(side) == Axis.x) {
        return room.y;
    } else {
        return room.x;
    }
}

void boxes(ref const Frame f, Region room) {
    Side side = SIDES[f.tower.pick(SIDES.length)];
    int[2] span = sideSpan(room, side);
    if (width(span) >= LEAST_ATTACHED_WALL) {
        int from = between(f, span[0], span[1] - 1);
        int[2][2] cells;
        foreach (step; 0 .. 2) {
            int x = from + step;
            int y = from + step;
            if (axisOf(side) == Axis.x) {
                x = edgeOn(room.x, side);
            } else {
                y = edgeOn(room.y, side);
            }
            cells[step] = [x, y];
        }
        if (!f.nearDoors[cells[0][0], cells[0][1]] && !f.nearDoors[cells[1][0], cells[1][1]]) {
            int top = f.base + between(f, 2, lowerOf(f.biome.boxHeight, f.room));
            foreach (cell; cells) {
                f.tower.paint(f.biome.boxes, boxOf([cell[0], cell[0]], [cell[1], cell[1]], [f.base + 1, top]));
            }
        }
    }
}

void shelves(ref const Frame f, Region room) {
    if (width(room.x) >= 5 && width(room.y) >= 5) {
        for (int y = room.y[0] + 1; y <= room.y[1] - 1; y += 2) {
            f.tower.paint(f.biome.shelf, boxOf([room.x[0] + 1, room.x[1] - 1], [y, y], [f.base + 1, f.base + f.doorHeight]));
        }
    }
}

void furnish(ref Frame f, ref const Found found) {
    hallDoors(f, found);
    foreach (room; found.slice()) {
        if (f.biome.roomFloors.length > 0) {
            f.tower.paint(f.biome.roomFloors[f.tower.pick(cast(uint) f.biome.roomFloors.length)], boxOf(room.x, room.y, [f.base, f.base]));
        }
        lamp(f, f.biome.light, f.biome.skylight, middle(room.x), middle(room.y));
        if (f.biome.damp != Material.none && chance(f, DAMP_ODDS)) {
            int x = between(f, room.x[0], room.x[1] - 1);
            int y = between(f, room.y[0], room.y[1] - 1);
            f.tower.paint(f.biome.damp, boxOf([x, x + 1], [y, y + 1], [f.base, f.base]));
        }
        if (f.biome.shelf != Material.none) {
            shelves(f, room);
        }
        if (f.biome.boxes != Material.none && chance(f, f.biome.boxOdds)) {
            boxes(f, room);
        }
    }
    foreach (band; bands(f).slice()) {
        for (int at = LIGHT_FROM; at <= f.far; at += LIGHT_EVERY) {
            if (band.x[1] == f.far) {
                lamp(f, f.hall.light, f.hall.skylight, at, 0);
            } else {
                lamp(f, f.hall.light, f.hall.skylight, 0, at);
            }
        }
    }
}

int[2] mazeSpan(ref const Frame f, int index) {
    int low = index * MAZE_PITCH + 1;
    int high = low + MAZE_WIDTH - 1;
    return [low, lowerOf(high, f.far)];
}

Box mazeGap(ref const Frame f, Axis axis, int i, int j) {
    int at = (i + 1) * MAZE_PITCH;
    if (axis == Axis.x) {
        return boxOf([at, at], mazeSpan(f, j), roomZ(f));
    } else {
        return boxOf(mazeSpan(f, j), [at, at], roomZ(f));
    }
}

uint mazeKey(int i, int j) {
    return i * MAZE_CELLS + j;
}

struct Maze {
    uint[MAZE_CELLS * MAZE_CELLS] exits;

    void open(ref const Frame f, int[2] a, int[2] b) {
        exits[mazeKey(a[0], a[1])] += 1;
        exits[mazeKey(b[0], b[1])] += 1;
        if (a[0] != b[0]) {
            f.tower.paint(Material.none, mazeGap(f, Axis.x, lowerOf(a[0], b[0]), a[1]));
        } else {
            f.tower.paint(Material.none, mazeGap(f, Axis.y, lowerOf(a[1], b[1]), a[0]));
        }
    }
}

void maze(ref Frame f, ref const Doors[4] lines) {
    int cells = MAZE_CELLS;
    f.tower.paint(f.biome.wall, boxOf([0, f.far], [0, f.far], roomZ(f)));
    foreach (i; 0 .. cells) {
        foreach (j; 0 .. cells) {
            f.tower.paint(Material.none, boxOf(mazeSpan(f, i), mazeSpan(f, j), roomZ(f)));
        }
    }
    Maze carved;
    uint visited = 1u << mazeKey(0, 0);
    int[2][MAZE_CELLS * MAZE_CELLS] trail;
    size_t depth = 1;
    while (depth > 0) {
        int[2] at = trail[depth - 1];
        int[2][4] moves;
        uint moveCount = 0;
        foreach (move; MOVES) {
            int i = at[0] + move[0];
            int j = at[1] + move[1];
            if (i >= 0 && i < cells && j >= 0 && j < cells && (visited & (1u << mazeKey(i, j))) == 0) {
                moves[moveCount] = [i, j];
                moveCount += 1;
            }
        }
        if (moveCount == 0) {
            depth -= 1;
        } else {
            int[2] chosen = moves[f.tower.pick(moveCount)];
            visited |= 1u << mazeKey(chosen[0], chosen[1]);
            carved.open(f, at, chosen);
            trail[depth] = chosen;
            depth += 1;
        }
    }
    foreach (i; 0 .. cells - 1) {
        foreach (j; 0 .. cells) {
            if (chance(f, MAZE_LOOP_ODDS)) {
                carved.open(f, [i, j], [i + 1, j]);
            }
            if (chance(f, MAZE_LOOP_ODDS)) {
                carved.open(f, [j, i], [j, i + 1]);
            }
        }
    }
    if (chance(f, MAZE_ROOM_ODDS)) {
        int i = between(f, 0, cells - 2);
        int j = between(f, 0, cells - 2);
        f.tower.paint(Material.none, boxOf([mazeSpan(f, i)[0], mazeSpan(f, i + 1)[1]], [mazeSpan(f, j)[0], mazeSpan(f, j + 1)[1]], roomZ(f)));
    }
    foreach (side; SIDES) {
        Axis axis = axisOf(side);
        if (isLow(side) || f.owns.has(side)) {
            int at = 0;
            if (!isLow(side)) {
                at = f.far;
                f.tower.paint(f.biome.wall, line(axis, at, [0, f.far], roomZ(f)));
            }
            foreach (slot; lines[side].slice()) {
                f.tower.paint(Material.none, line(axis, at, mazeSpan(f, slot), roomZ(f)));
            }
        }
    }
    foreach (i; 0 .. cells) {
        foreach (j; 0 .. cells) {
            int[2] x = mazeSpan(f, i);
            int[2] y = mazeSpan(f, j);
            if (chance(f, MAZE_LIGHT_ODDS)) {
                light(f, f.biome.light, x[0], y[0]);
            }
            if (carved.exits[mazeKey(i, j)] == 1 && chance(f, f.biome.nowhere)) {
                foreach (step; 1 .. NOWHERE_STEPS + 1) {
                    f.tower.paint(f.biome.stair, boxOf([x[0] + step - 1, x[0] + step - 1], y, [f.base + 1, f.base + step]));
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
    Region around = Region([region.x[0] - 1, region.x[1] + 1], [region.y[0] - 1, region.y[1] + 1]);
    f.tower.paint(f.biome.wall, boxOf(around.x, around.y, [floor, f.base]));
    f.tower.paint(f.biome.wall, boxOf(around.x, around.y, [ceilingZ(f), top]));
    f.tower.paint(Material.none, boxOf(region.x, region.y, [floor + 1, top - 1]));
    f.tower.paint(f.biome.floor, boxOf(region.x, region.y, [floor, floor]));
    f.tower.paint(f.biome.ceiling, boxOf(region.x, region.y, [top, top]));
    f.tower.paint(Material.steel, boxOf(around.x, around.y, [top + ROOF, top + ROOF]));
    int[2] steps = [region.y[0], region.y[0] + 1];
    foreach (step; 1 .. depth) {
        int x = region.x[0] + step - 1;
        f.tower.paint(f.biome.stair, boxOf([x, x], steps, [floor + 1, f.base - step]));
    }
    foreach (_; 0 .. PODIUMS) {
        int x = between(f, region.x[0] + depth, region.x[1] - PODIUM_SIZE + 1);
        int y = between(f, region.y[0] + 2, region.y[1] - PODIUM_SIZE + 1);
        f.tower.paint(f.biome.wall, boxOf([x, x + PODIUM_SIZE - 1], [y, y + PODIUM_SIZE - 1], [floor + 1, floor + between(f, 1, depth + 2)]));
    }
    foreach (_; 0 .. HANGING) {
        int x = between(f, region.x[0] + 1, region.x[1] - PODIUM_SIZE + 1);
        int y = between(f, region.y[0] + 2, region.y[1] - PODIUM_SIZE + 1);
        f.tower.paint(f.biome.wall, boxOf([x, x + PODIUM_SIZE - 1], [y, y + PODIUM_SIZE - 1], [top - between(f, 1, CHAPEL_RISE), top - 1]));
    }
    int x = middle(region.x);
    int y = middle(region.y);
    f.tower.paint(Material.glass, boxOf([x, x + 1], [y, y + 1], [top, top + ROOF]));
    f.tower.paint(Material.sunlight, boxOf([x, x + 1], [y, y + 1], [floor, floor]));
    int farWall = region.y[1] + 1;
    int[2] mural = [middle(region.x) - MURAL_HALF_WIDTH, middle(region.x) + MURAL_HALF_WIDTH];
    f.tower.paint(Material.slate, boxOf(mural, [farWall, farWall], [f.base + 1, f.base + f.room]));
    f.tower.paint(Material.whiteBrick, boxOf(mural, [farWall, farWall], [f.base + 2, f.base + 2]));
    f.tower.paint(Material.whiteBrick, boxOf([middle(region.x), middle(region.x)], [farWall, farWall], [f.base + 1, f.base + f.room]));
}

void rings(ref Frame f) {
    foreach (inset; RINGS) {
        int[2] x = [f.region.x[0] + inset, f.region.x[1] - inset];
        int[2] y = [f.region.y[0] + inset, f.region.y[1] - inset];
        if (width(x) >= 3 && width(y) >= 3) {
            f.tower.paint(f.biome.wall, boxOf(x, y, roomZ(f)));
            f.tower.paint(Material.none, boxOf([x[0] + 1, x[1] - 1], [y[0] + 1, y[1] - 1], roomZ(f)));
            Side side = SIDES[f.tower.pick(SIDES.length)];
            Axis axis = axisOf(side);
            int at = x[0];
            if (side == Side.xHigh) {
                at = x[1];
            } else if (side == Side.yLow) {
                at = y[0];
            } else if (side == Side.yHigh) {
                at = y[1];
            }
            int[2] along = x;
            if (axis == Axis.x) {
                along = y;
            }
            if (width(along) >= DOOR_WIDTH + 2) {
                f.tower.paint(Material.none, line(axis, at, [along[0] + 1, along[0] + DOOR_WIDTH], [f.base + 1, f.base + f.doorHeight]));
            }
        }
    }
}

void stairs(ref const Frame lower, ref const Frame upper, Stair stair, bool isRouted) {
    int rise = upper.base - lower.base;
    int x0 = stair.x;
    int y0 = stair.y;
    int first = floorDiv(rise + 2, 2);
    int[2] lowRows = [y0, y0 + 1];
    int[2] highRows = [y0 + 2, y0 + 3];
    float[3][MOST_STOPS] stops;
    size_t count = 0;
    void stop(float x, float y, float z) {
        stops[count] = [x, y, z];
        count += 1;
    }
    void tread(int[2] x, int[2] rows, int height) {
        lower.tower.paint(lower.biome.stair, boxOf(x, rows, [lower.base + height, lower.base + height]));
    }
    void enclose(int[2] x, int[2] y) {
        upper.tower.paint(upper.biome.wall, boxOf(x, y, [upper.base + 1, upper.base + upper.room]));
    }
    lower.tower.paint(Material.none, boxOf([x0, x0 + first + 1], [y0, y0 + STAIR_ROWS - 1], [lower.base + 1, upper.base]));
    stop(x0 + 0.5f, y0 + 3, lower.base + 1);
    foreach (height; 1 .. first + 1) {
        tread([x0 + height - 1, x0 + height - 1], lowRows, height);
        stop(x0 + height - 0.5f, y0 + 1, lower.base + height + 1);
    }
    tread([x0 + first, x0 + first + 1], [y0, y0 + STAIR_ROWS - 1], first);
    stop(x0 + first + 1, y0 + 1, lower.base + first + 1);
    stop(x0 + first + 1, y0 + 3, lower.base + first + 1);
    foreach (height; first + 1 .. rise + 1) {
        int x = x0 + 2 * first - height;
        tread([x, x], highRows, height);
        stop(x + 0.5f, y0 + 3, lower.base + height + 1);
    }
    int arrival = x0 + 2 * first - rise - 1;
    if (arrival >= x0) {
        upper.tower.paint(upper.biome.floor, boxOf([x0, arrival], highRows, [upper.base, upper.base]));
    }
    enclose([x0, x0], lowRows);
    enclose([x0 + 1, x0 + first + 1], [y0 + STAIR_ROWS, y0 + STAIR_ROWS]);
    enclose([x0 + first + 2, x0 + first + 2], [y0, y0 + STAIR_ROWS - 1]);
    stop(x0 + 0.5f, y0 + 3, upper.base + 1);
    stop(x0 + 0.5f, y0 + STAIR_ROWS + 0.5f, upper.base + 1);
    if (isRouted) {
        foreach (spot; stops[0 .. count]) {
            lower.tower.stop(spot[0], spot[1], spot[2]);
        }
    }
}

Frame frameOf(ref const Quarter q, Halls halls, Floor floor, const(Biome)* biome, ref const Stair stair, Plan plan, Owns owns) {
    immutable(Level)* level = &floor.level();
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
    f.region = Region([x0, far - 1], [regionY, far - 1]);
    f.owns = owns;
    f.marks.put(FrameMark.skirting, biome.trim != Material.none && chance(f, SKIRTING_ODDS));
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
