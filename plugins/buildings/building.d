module plugins.buildings.building;

import plugins.api.api : Box, Material, Rhythm;
import plugins.turtle.turtle : Turtle, boxOf, floorDiv;

enum int STORY = 4;
enum size_t MOST_PARTS = 5;
enum size_t MOST_TIERS = 8;
enum size_t MOST_BOXES = 32;
enum Rhythm FLOORS = Rhythm(STORY, 0, 1);
enum Rhythm WINDOW_ROWS = Rhythm(STORY, 1, 2);
enum Rhythm ROOMS = Rhythm(STORY, 1, STORY - 1);
enum int DOOR_TOP = STORY - 1;
enum int DOOR_WIDTH = 2;
enum int PIER_SPACING = 3;
enum int ANTENNA = 6;
enum int MAST_SPACING = 3;
enum int CHIMNEY = 3;
enum int LEAST_PAD = 5;
enum int CORE_LENGTH = STORY + 1;
enum int CORE_WIDTH = 5;
enum int CORE_ROOM = CORE_WIDTH + 2;
enum int WALKWAY = 2;
enum int SECOND_LANE = 3;
enum int ROAD_STOP = 3;
enum int SIDEWALK_STOP = 2;

enum Bound : ubyte {
    street,
    joined,
    lot,
}

enum Side : ubyte {
    xLow,
    yLow,
    xHigh,
    yHigh,
}

immutable Side[4] SIDES = [Side.xLow, Side.yLow, Side.xHigh, Side.yHigh];

struct Palette {
    Material wall;
    Material trim;
    Material floor;
    Material band;
    Material roof;
}

struct Spec {
    int stories;
    Palette palette;
    int front;
    int gap;
    int routeStories;
}

struct Join {
    uint lot;
    Side side;
    bool isPresent;
}

struct Lot {
    Turtle site;
    Bound[4] bounds;
    Join[4] joins;
    Side front;
    bool hasFront;
}

struct Lots {
    Lot[MOST_PARTS] items;
    size_t count;

    void add(Lot lot) {
        items[count] = lot;
        count += 1;
    }

    inout(Lot)[] slice() inout return {
        return items[0 .. count];
    }
}

struct Tier {
    int low;
    int high;
    int shrink;
    bool isBelowSplit;
    bool isRoofed;
    bool hasAbove;
    int aboveShrink;
    bool isAboveBelowSplit;
}

struct PartJoin {
    const(Part)* part;
    Side side;
}

struct Part {
    Turtle tower;
    Turtle site;
    int[2] x;
    int[2] y;
    Bound[4] kinds;
    PartJoin[4] joins;
    Side front;
    bool hasFront;
    int split;
    Tier top;
    Tier stand;
}

struct Parts {
    Part[MOST_PARTS] items;
    size_t count;

    inout(Part)[] slice() inout return {
        return items[0 .. count];
    }
}

struct Tiers {
    Tier[MOST_TIERS] items;
    size_t count;

    inout(Tier)[] slice() inout return {
        return items[0 .. count];
    }
}

struct Boxes {
    Box[MOST_BOXES] items;
    size_t count;

    void add(Box box) {
        items[count] = box;
        count += 1;
    }

    inout(Box)[] slice() inout return {
        return items[0 .. count];
    }
}

alias Crown = void function(ref const Part part, Palette palette, Tier tier);

Turtle upright(Turtle site) {
    return site.pitchUp().rollRight();
}

int boundLow(Bound kind, Spec spec) {
    if (kind == Bound.street) {
        return spec.front;
    } else if (kind == Bound.joined) {
        return 0;
    } else {
        return spec.gap;
    }
}

int boundHigh(Bound kind, Spec spec, int far) {
    if (kind == Bound.joined) {
        return far;
    } else {
        return far - spec.gap;
    }
}

bool isOpen(ref const Part part, Side side, bool isBelowSplit) {
    bool isJoined = part.kinds[side] == Bound.joined;
    if (side == Side.xLow || side == Side.yLow) {
        return isJoined;
    } else {
        return isJoined && isBelowSplit;
    }
}

int[2] range(int low, int high, bool isLowOpen, bool isHighOpen, int shrink) {
    int[2] span = [low + shrink, high - shrink];
    if (isLowOpen) {
        span[0] = low;
    }
    if (isHighOpen) {
        span[1] = high;
    }
    return span;
}

Box footprint(ref const Part part, int shrink, bool isBelowSplit, int low, int high) {
    return boxOf(
        range(part.x[0], part.x[1], isOpen(part, Side.xLow, isBelowSplit), isOpen(part, Side.xHigh, isBelowSplit), shrink),
        range(part.y[0], part.y[1], isOpen(part, Side.yLow, isBelowSplit), isOpen(part, Side.yHigh, isBelowSplit), shrink),
        [low, high],
    );
}

int middle(int low, int high) {
    return floorDiv(low + high, 2);
}

int width(int low, int high) {
    return high - low + 1;
}

int area(Box box) {
    return width(box.low[0], box.high[0]) * width(box.low[1], box.high[1]);
}

bool isEmpty(Box box) {
    return box.low[0] > box.high[0] || box.low[1] > box.high[1];
}

Box faceOf(Box box, Side side) {
    Box face = box;
    if (side == Side.xLow) {
        face.high[0] = box.low[0];
    } else if (side == Side.xHigh) {
        face.low[0] = box.high[0];
    } else if (side == Side.yLow) {
        face.high[1] = box.low[1];
    } else {
        face.low[1] = box.high[1];
    }
    return face;
}

bool isAlongY(Side side) {
    return side == Side.xLow || side == Side.xHigh;
}

size_t alongAxis(Side side) {
    if (isAlongY(side)) {
        return 1;
    } else {
        return 0;
    }
}

int[2] along(Box box, Side side) {
    size_t axis = alongAxis(side);
    return [box.low[axis], box.high[axis]];
}

Box withAlong(Box face, Side side, int[2] span) {
    Box piece = face;
    size_t axis = alongAxis(side);
    piece.low[axis] = span[0];
    piece.high[axis] = span[1];
    return piece;
}

Box movedOut(Box face, Side side, int cells) {
    int sign = cells;
    if (side == Side.xLow || side == Side.yLow) {
        sign = -cells;
    }
    Box moved = face;
    size_t axis = 1 - alongAxis(side);
    moved.low[axis] += sign;
    moved.high[axis] += sign;
    return moved;
}

Boxes uncovered(ref const Part part, Box box, Side side, Tier tier) {
    Boxes pieces;
    PartJoin join = part.joins[side];
    if (join.part !is null) {
        int[2] theirs = along(footprint(*join.part, tier.shrink, tier.isBelowSplit, tier.low, tier.high), join.side);
        int[2] mine = along(box, side);
        Box face = faceOf(box, side);
        if (mine[0] < theirs[0]) {
            int high = mine[1] < theirs[0] - 1 ? mine[1] : theirs[0] - 1;
            pieces.add(withAlong(face, side, [mine[0], high]));
        }
        if (mine[1] > theirs[1]) {
            int low = mine[0] > theirs[1] + 1 ? mine[0] : theirs[1] + 1;
            pieces.add(withAlong(face, side, [low, mine[1]]));
        }
    }
    return pieces;
}

Boxes walls(ref const Part part, Box box, Tier tier) {
    Boxes list;
    foreach (side; SIDES) {
        if (!isOpen(part, side, tier.isBelowSplit)) {
            list.add(faceOf(box, side));
        } else {
            foreach (piece; uncovered(part, box, side, tier).slice()) {
                list.add(piece);
            }
        }
    }
    return list;
}

Boxes strips(Box face, int spacing) {
    bool isAlongX = face.low[0] != face.high[0];
    size_t axis = isAlongX ? 0 : 1;
    int first = face.low[axis];
    int last = face.high[axis];
    Boxes list;
    int cell = first;
    while (cell <= last) {
        Box strip = face;
        strip.low[axis] = cell;
        strip.high[axis] = cell;
        list.add(strip);
        cell += spacing;
    }
    if (list.items[list.count - 1].low[axis] != last) {
        Box strip = face;
        strip.low[axis] = last;
        strip.high[axis] = last;
        list.add(strip);
    }
    return list;
}

int narrowing(int[2] x, int[2] y, int wanted, int least) {
    int narrowest = width(x[0], x[1]);
    if (width(y[0], y[1]) < narrowest) {
        narrowest = width(y[0], y[1]);
    }
    int room = floorDiv(narrowest - least, 2);
    int chosen = wanted < room ? wanted : room;
    return chosen > 0 ? chosen : 0;
}

Part partOf(ref const Lot lot, Spec spec) {
    Turtle tower = upright(lot.site);
    int far = tower.column().high;
    Part part;
    part.tower = tower;
    part.site = lot.site;
    part.x = [boundLow(lot.bounds[Side.xLow], spec), boundHigh(lot.bounds[Side.xHigh], spec, far)];
    part.y = [boundLow(lot.bounds[Side.yLow], spec), boundHigh(lot.bounds[Side.yHigh], spec, far)];
    part.kinds = lot.bounds;
    part.front = lot.front;
    part.hasFront = lot.hasFront;
    part.split = far + 1;
    return part;
}

void makeParts(ref Parts parts, ref const Lots lots, Spec spec) {
    parts.count = lots.count;
    foreach (index, ref lot; lots.slice()) {
        parts.items[index] = partOf(lot, spec);
    }
    foreach (index, ref lot; lots.slice()) {
        foreach (side; SIDES) {
            if (lot.joins[side].isPresent) {
                parts.items[index].joins[side] = PartJoin(&parts.items[lot.joins[side].lot], lot.joins[side].side);
            }
        }
    }
}

int setbacks(ref const Parts parts, int wanted) {
    int chosen = wanted;
    foreach (ref part; parts.slice()) {
        int room = narrowing(part.x, part.y, wanted, CORE_ROOM);
        if (room < chosen) {
            chosen = room;
        }
    }
    return chosen;
}

Tiers tiers(ref Part part, Spec spec, int setbacks) {
    int top = spec.stories * STORY;
    Tiers found;
    int belowTop = top < part.split - 1 ? top : part.split - 1;
    found.items[0] = Tier(0, belowTop, 0, true);
    found.count = 1;
    int low = part.split;
    foreach (tier; 0 .. setbacks + 1) {
        int high = top;
        if (tier < setbacks) {
            high = part.split + floorDiv(floorDiv((top - part.split) * (tier + 1), setbacks + 1), STORY) * STORY;
        }
        if (high >= low) {
            found.items[found.count] = Tier(low, high, tier, false);
            found.count += 1;
            low = high + 1;
        }
    }
    foreach (index; 0 .. found.count) {
        Tier* tier = &found.items[index];
        if (index + 1 < found.count) {
            Tier above = found.items[index + 1];
            tier.hasAbove = true;
            tier.aboveShrink = above.shrink;
            tier.isAboveBelowSplit = above.isBelowSplit;
            tier.isRoofed = above.shrink > tier.shrink;
        } else {
            tier.isRoofed = true;
        }
    }
    part.top = found.items[found.count - 1];
    part.stand = part.top;
    return found;
}

Box shell(ref const Part part, Palette palette, Tier tier) {
    Box box = footprint(part, tier.shrink, tier.isBelowSplit, tier.low, tier.high);
    Box inside = footprint(part, tier.shrink + 1, tier.isBelowSplit, tier.low, tier.high);
    part.tower.paint(palette.wall, box);
    if (palette.band != Material.none) {
        part.tower.paint(palette.band, box, FLOORS);
    }
    part.tower.paint(palette.floor, inside, FLOORS);
    part.tower.paint(Material.none, inside, ROOMS);
    foreach (side; SIDES) {
        if (isOpen(part, side, tier.isBelowSplit)) {
            foreach (piece; uncovered(part, box, side, tier).slice()) {
                part.tower.paint(palette.wall, piece);
                if (palette.band != Material.none) {
                    part.tower.paint(palette.band, piece, FLOORS);
                }
            }
        }
    }
    return box;
}

void ring(ref const Part part, Palette palette, Tier tier) {
    int z = tier.high + 1;
    Tier level = Tier(z, z, tier.shrink, false);
    Box box = footprint(part, tier.shrink, false, z, z);
    part.tower.paint(palette.trim, box);
    part.tower.paint(Material.none, footprint(part, tier.shrink + 1, false, z, z));
    foreach (side; SIDES) {
        if (isOpen(part, side, false)) {
            foreach (piece; uncovered(part, box, side, level).slice()) {
                part.tower.paint(palette.trim, piece);
            }
        }
    }
}

void roof(ref const Part part, Palette palette, Material material, Tier tier) {
    part.tower.paint(material, footprint(part, tier.shrink, tier.isBelowSplit, tier.high, tier.high));
    if (tier.hasAbove) {
        part.tower.paint(palette.floor, footprint(part, tier.aboveShrink + 1, tier.isAboveBelowSplit, tier.high, tier.high));
    }
    ring(part, palette, tier);
}

void punched(ref const Part part, Palette palette, Box box, Tier tier, int spacing) {
    foreach (face; walls(part, box, tier).slice()) {
        part.tower.paint(Material.glass, face, WINDOW_ROWS);
        foreach (pier; strips(face, spacing).slice()) {
            part.tower.paint(palette.wall, pier);
        }
    }
}

void masonry(ref const Part part, Palette palette, Box box, Tier tier) {
    punched(part, palette, box, tier, PIER_SPACING);
}

void banded(ref const Part part, Box box, Tier tier, Rhythm rows) {
    foreach (face; walls(part, box, tier).slice()) {
        part.tower.paint(Material.glass, face, rows);
    }
}

void storefront(ref const Part part) {
    Box box = footprint(part, 0, true, 1, DOOR_TOP);
    foreach (side; SIDES) {
        if (part.kinds[side] == Bound.street) {
            Box face = faceOf(box, side);
            int[2] run = along(face, side);
            part.tower.paint(Material.glass, withAlong(face, side, [run[0] + 1, run[1] - 1]));
        }
    }
}

void masts(ref const Part part, Palette palette, Tier tier) {
    Box roofBox = footprint(part, tier.shrink + 1, false, tier.high, tier.high);
    if (!isEmpty(roofBox)) {
        int x = middle(roofBox.low[0], roofBox.high[0]);
        int y = middle(roofBox.low[1], roofBox.high[1]);
        bool isAlongX = width(roofBox.low[0], roofBox.high[0]) >= width(roofBox.low[1], roofBox.high[1]);
        size_t axis = isAlongX ? 0 : 1;
        int height = ANTENNA + STORY;
        for (int cell = roofBox.low[axis] + 1; cell <= roofBox.high[axis] - 1; cell += MAST_SPACING) {
            Box mast = boxOf([x, x], [cell, cell], [tier.high + 1, tier.high + height]);
            if (isAlongX) {
                mast = boxOf([cell, cell], [y, y], [tier.high + 1, tier.high + height]);
            }
            part.tower.paint(palette.trim, mast);
            height = height - 2 > 2 ? height - 2 : 2;
        }
    }
}

void pyramid(ref const Part part, Palette palette, Tier tier) {
    Box roofBox = footprint(part, tier.shrink + 1, false, tier.high, tier.high);
    int narrowest = width(roofBox.low[0], roofBox.high[0]);
    if (width(roofBox.low[1], roofBox.high[1]) < narrowest) {
        narrowest = width(roofBox.low[1], roofBox.high[1]);
    }
    int reach = floorDiv(narrowest - 1, 2);
    int x = middle(roofBox.low[0], roofBox.high[0]);
    int y = middle(roofBox.low[1], roofBox.high[1]);
    foreach (level; 1 .. reach + 2) {
        int spread = reach + 1 - level;
        part.tower.paint(palette.trim, boxOf([x - spread, x + spread], [y - spread, y + spread], [tier.high + level, tier.high + level]));
    }
}

void helipad(ref const Part part, Palette palette, Tier tier) {
    Box roofBox = footprint(part, tier.shrink + 1, false, tier.high, tier.high);
    if (width(roofBox.low[0], roofBox.high[0]) >= LEAST_PAD && width(roofBox.low[1], roofBox.high[1]) >= LEAST_PAD) {
        int x = middle(roofBox.low[0], roofBox.high[0]);
        int y = middle(roofBox.low[1], roofBox.high[1]);
        int z = tier.high + 1;
        part.tower.paint(Material.concrete, boxOf([x - 2, x + 2], [y - 2, y + 2], [z, z]));
        part.tower.paint(Material.whiteBrick, boxOf([x - 1, x - 1], [y - 1, y + 1], [z, z]));
        part.tower.paint(Material.whiteBrick, boxOf([x + 1, x + 1], [y - 1, y + 1], [z, z]));
        part.tower.paint(Material.whiteBrick, boxOf([x, x], [y, y], [z, z]));
    }
}

void chimney(ref const Part part, Palette palette, Tier tier) {
    Box roofBox = footprint(part, tier.shrink + 1, false, tier.high, tier.high);
    if (!isEmpty(roofBox)) {
        int x = roofBox.high[0];
        int y = roofBox.high[1];
        part.tower.paint(palette.trim, boxOf([x, x], [y, y], [tier.high + 1, tier.high + CHIMNEY]));
    }
}

void waterTower(ref const Part part, Palette palette, Tier tier) {
    Box roofBox = footprint(part, tier.shrink, false, tier.high, tier.high);
    int x = roofBox.high[0] - 2;
    int y = roofBox.high[1] - 2;
    part.tower.paint(Material.steel, boxOf([x, x], [y, y], [tier.high + 1, tier.high + 1]));
    part.tower.paint(Material.steel, boxOf([x + 1, x + 1], [y + 1, y + 1], [tier.high + 1, tier.high + 1]));
    part.tower.paint(Material.woodPlanks, boxOf([x, x + 1], [y, y + 1], [tier.high + 2, tier.high + 4]));
}

struct Core {
    bool isX;
    int sign;
    int first;
    int across;
    bool isRoomy;
}

Core coreOf(ref const Part part, Box interior) {
    Side side = part.front;
    bool isX = side == Side.xLow || side == Side.xHigh;
    size_t alongIndex = isX ? 0 : 1;
    size_t acrossIndex = 1 - alongIndex;
    int[2] alongSpan = [interior.low[alongIndex], interior.high[alongIndex]];
    int[2] acrossSpan = [interior.low[acrossIndex], interior.high[acrossIndex]];
    int sign = 1;
    int first = alongSpan[0];
    if (side == Side.xHigh || side == Side.yHigh) {
        sign = -1;
        first = alongSpan[1];
    }
    int acrossWidth = width(acrossSpan[0], acrossSpan[1]);
    return Core(isX, sign, first, acrossSpan[0] + floorDiv(acrossWidth - CORE_WIDTH, 2), width(alongSpan[0], alongSpan[1]) >= CORE_LENGTH && acrossWidth >= CORE_WIDTH);
}

Box coreBox(Core core, int alongLow, int alongHigh, int acrossLow, int acrossHigh, int[2] z) {
    int a = core.first + core.sign * alongLow;
    int b = core.first + core.sign * alongHigh;
    int[2] alongSpan = [a < b ? a : b, a < b ? b : a];
    int[2] acrossSpan = [core.across + acrossLow, core.across + acrossHigh];
    if (core.isX) {
        return boxOf(alongSpan, acrossSpan, z);
    } else {
        return boxOf(acrossSpan, alongSpan, z);
    }
}

void coreStairs(ref const Part part, Core core, int top, Material material) {
    int last = top - STORY;
    foreach (parity; 0 .. 2) {
        int lane = SECOND_LANE * parity;
        int floor = parity * STORY;
        foreach (tread; 1 .. STORY) {
            part.tower.paint(material, coreBox(core, tread, tread, lane, lane + 1, [1, last - 1]), Rhythm(2 * STORY, floor + 1, tread));
        }
        part.tower.paint(Material.none, coreBox(core, 0, STORY - 1, lane, lane + 1, [STORY, last]), Rhythm(2 * STORY, floor + STORY, 1));
    }
}

int wallAlong(Core core, Box ground) {
    size_t axis = core.isX ? 0 : 1;
    if (core.sign > 0) {
        return ground.low[axis];
    } else {
        return ground.high[axis];
    }
}

void coreDoor(ref const Part part, Core core, Box ground) {
    int wall = wallAlong(core, ground);
    Box door = coreBox(core, 0, 0, WALKWAY, WALKWAY + DOOR_WIDTH - 1, [1, DOOR_TOP]);
    size_t axis = core.isX ? 0 : 1;
    door.low[axis] = wall < wall + core.sign ? wall : wall + core.sign;
    door.high[axis] = wall < wall + core.sign ? wall + core.sign : wall;
    part.tower.paint(Material.none, door);
}

void coreStop(ref const Part part, Core core, float alongAt, float across, float z) {
    if (core.isX) {
        part.tower.stop(alongAt, across, z);
    } else {
        part.tower.stop(across, alongAt, z);
    }
}

void coreRoute(ref const Part part, Core core, Box ground, int stories) {
    int wall = wallAlong(core, ground);
    float walkway = core.across + WALKWAY + 0.5f;
    coreStop(part, core, wall - core.sign * ROAD_STOP + 0.5f, walkway, 0);
    coreStop(part, core, wall - core.sign * SIDEWALK_STOP + 0.5f, walkway, 1);
    foreach (story; 0 .. stories) {
        int floor = story * STORY;
        float lane = core.across + SECOND_LANE * (story % 2) + 1;
        coreStop(part, core, core.first + 0.5f, walkway, floor + 1);
        coreStop(part, core, core.first + 0.5f, lane, floor + 1);
        foreach (tread; 1 .. STORY) {
            coreStop(part, core, core.first + core.sign * tread + 0.5f, lane, floor + tread + 1);
        }
        coreStop(part, core, core.first + core.sign * STORY + 0.5f, lane, floor + STORY + 1);
        coreStop(part, core, core.first + core.sign * STORY + 0.5f, walkway, floor + STORY + 1);
    }
}

void enter(ref const Parts parts, Spec spec) {
    size_t index = 0;
    while (index < parts.count && !parts.items[index].hasFront) {
        index += 1;
    }
    if (index < parts.count) {
        const(Part)* entry = &parts.items[index];
        Core core = coreOf(*entry, footprint(*entry, entry.top.shrink + 1, entry.top.isBelowSplit, 0, 0));
        if (core.isRoomy) {
            Box ground = footprint(*entry, 0, true, 0, 0);
            coreDoor(*entry, core, ground);
            if (spec.stories > 1) {
                coreStairs(*entry, core, spec.stories * STORY, spec.palette.floor);
            }
            if (spec.routeStories > 0) {
                coreRoute(*entry, core, ground, spec.routeStories);
            }
        }
    }
}

void crown(ref const Parts parts, Palette palette, Crown chosen) {
    size_t main = 0;
    foreach (index, ref part; parts.slice()) {
        const(Part)* best = &parts.items[main];
        if (area(footprint(part, part.stand.shrink, false, 0, 0)) > area(footprint(*best, best.stand.shrink, false, 0, 0))) {
            main = index;
        }
    }
    chosen(parts.items[main], palette, parts.items[main].stand);
}

uint pick(ref const Parts parts, uint count) {
    return parts.items[0].site.pick(count);
}
