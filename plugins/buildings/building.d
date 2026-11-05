module plugins.buildings.building;

import plugins.api.api : Box, Material, MaybeIndex, Rhythm, Span;
import plugins.turtle.turtle : Along, Turtle, boxOf, floorDiv, higherOf, lowerOf, upright;

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
    none,
}

enum Split : ubyte {
    above,
    below,
}

enum Roofing : ubyte {
    open,
    roofed,
}

enum Stacking : ubyte {
    topmost,
    covered,
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
    MaybeIndex!Lot lot;
    Side side;
}

struct Lot {
    Turtle site;
    Bound[4] bounds;
    Join[4] joins;
    Side front = Side.none;
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
    Split split;
    Roofing roofing;
    Stacking stacking;
    int aboveShrink;
    Split aboveSplit;

    bool isRoofed() const {
        return roofing == Roofing.roofed;
    }

    bool hasAbove() const {
        return stacking == Stacking.covered;
    }
}

struct PartJoin {
    const(Part)* part;
    Side side;
}

struct Part {
    Turtle tower;
    Turtle site;
    Span x;
    Span y;
    Bound[4] kinds;
    PartJoin[4] joins;
    Side front = Side.none;
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

bool isOpen(ref const Part part, Side side, Split split) {
    return part.kinds[side] == Bound.joined && (side == Side.xLow || side == Side.yLow || split == Split.below);
}

int shrinkAt(ref const Part part, Side side, Split split, int shrink) {
    if (isOpen(part, side, split)) {
        return 0;
    } else {
        return shrink;
    }
}

Box footprint(ref const Part part, int shrink, Split split, int low, int high) {
    return boxOf(
        Span(part.x.low + shrinkAt(part, Side.xLow, split, shrink), part.x.high - shrinkAt(part, Side.xHigh, split, shrink)),
        Span(part.y.low + shrinkAt(part, Side.yLow, split, shrink), part.y.high - shrinkAt(part, Side.yHigh, split, shrink)),
        Span(low, high),
    );
}

int middle(Span span) {
    return floorDiv(span.low + span.high, 2);
}

int width(Span span) {
    return span.high - span.low + 1;
}

Span xSpan(Box box) {
    return Span(box.low.x, box.high.x);
}

Span ySpan(Box box) {
    return Span(box.low.y, box.high.y);
}

int area(Box box) {
    return width(xSpan(box)) * width(ySpan(box));
}

bool isEmpty(Box box) {
    return box.low.x > box.high.x || box.low.y > box.high.y;
}

Box faceOf(Box box, Side side) {
    Box face = box;
    if (side == Side.xLow) {
        face.high.x = box.low.x;
    } else if (side == Side.xHigh) {
        face.low.x = box.high.x;
    } else if (side == Side.yLow) {
        face.high.y = box.low.y;
    } else {
        face.low.y = box.high.y;
    }
    return face;
}

bool isAlongY(Side side) {
    return side == Side.xLow || side == Side.xHigh;
}

size_t axisIndex(Along along) {
    if (along == Along.x) {
        return 0;
    } else {
        return 1;
    }
}

size_t alongAxis(Side side) {
    if (isAlongY(side)) {
        return 1;
    } else {
        return 0;
    }
}

Span along(Box box, Side side) {
    size_t axis = alongAxis(side);
    return Span(box.low[axis], box.high[axis]);
}

Box withAlong(Box face, Side side, Span span) {
    Box piece = face;
    size_t axis = alongAxis(side);
    piece.low[axis] = span.low;
    piece.high[axis] = span.high;
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
        Span theirs = along(footprint(*join.part, tier.shrink, tier.split, tier.low, tier.high), join.side);
        Span mine = along(box, side);
        Box face = faceOf(box, side);
        if (mine.low < theirs.low) {
            pieces.add(withAlong(face, side, Span(mine.low, lowerOf(mine.high, theirs.low - 1))));
        }
        if (mine.high > theirs.high) {
            pieces.add(withAlong(face, side, Span(higherOf(mine.low, theirs.high + 1), mine.high)));
        }
    }
    return pieces;
}

Boxes walls(ref const Part part, Box box, Tier tier) {
    Boxes list;
    foreach (side; SIDES) {
        if (!isOpen(part, side, tier.split)) {
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
    size_t axis = 1;
    if (face.low.x != face.high.x) {
        axis = 0;
    }
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

int narrowestOf(Box box) {
    return lowerOf(width(ySpan(box)), width(xSpan(box)));
}

int narrowing(Span x, Span y, int wanted, int least) {
    int room = floorDiv(lowerOf(width(y), width(x)) - least, 2);
    return higherOf(lowerOf(wanted, room), 0);
}

Part partOf(ref const Lot lot, Spec spec) {
    Turtle tower = upright(lot.site);
    int far = tower.column().high;
    Part part;
    part.tower = tower;
    part.site = lot.site;
    part.x = Span(boundLow(lot.bounds[Side.xLow], spec), boundHigh(lot.bounds[Side.xHigh], spec, far));
    part.y = Span(boundLow(lot.bounds[Side.yLow], spec), boundHigh(lot.bounds[Side.yHigh], spec, far));
    part.kinds = lot.bounds;
    part.front = lot.front;
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
            if (lot.joins[side].lot.exists) {
                parts.items[index].joins[side] = PartJoin(&parts.items[lot.joins[side].lot.value], lot.joins[side].side);
            }
        }
    }
}

int setbacks(ref const Parts parts, int wanted) {
    int chosen = wanted;
    foreach (ref part; parts.slice()) {
        chosen = lowerOf(narrowing(part.x, part.y, wanted, CORE_ROOM), chosen);
    }
    return chosen;
}

Tiers tiers(ref Part part, Spec spec, int setbacks) {
    int top = spec.stories * STORY;
    Tiers found;
    int belowTop = lowerOf(top, part.split - 1);
    found.items[0] = Tier(0, belowTop, 0, Split.below);
    found.count = 1;
    int low = part.split;
    foreach (tier; 0 .. setbacks + 1) {
        int high = top;
        if (tier < setbacks) {
            high = part.split + floorDiv(floorDiv((top - part.split) * (tier + 1), setbacks + 1), STORY) * STORY;
        }
        if (high >= low) {
            found.items[found.count] = Tier(low, high, tier, Split.above);
            found.count += 1;
            low = high + 1;
        }
    }
    foreach (index; 0 .. found.count) {
        Tier* tier = &found.items[index];
        if (index + 1 < found.count) {
            Tier above = found.items[index + 1];
            tier.stacking = Stacking.covered;
            tier.aboveShrink = above.shrink;
            tier.aboveSplit = above.split;
            if (above.shrink > tier.shrink) {
                tier.roofing = Roofing.roofed;
            }
        } else {
            tier.roofing = Roofing.roofed;
        }
    }
    part.top = found.items[found.count - 1];
    part.stand = part.top;
    return found;
}

Box shell(ref const Part part, Palette palette, Tier tier) {
    Box box = footprint(part, tier.shrink, tier.split, tier.low, tier.high);
    Box inside = footprint(part, tier.shrink + 1, tier.split, tier.low, tier.high);
    part.tower.paint(palette.wall, box);
    if (palette.band != Material.none) {
        part.tower.paint(palette.band, box, FLOORS);
    }
    part.tower.paint(palette.floor, inside, FLOORS);
    part.tower.paint(Material.none, inside, ROOMS);
    foreach (side; SIDES) {
        if (isOpen(part, side, tier.split)) {
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
    Tier level = Tier(z, z, tier.shrink, Split.above);
    Box box = footprint(part, tier.shrink, Split.above, z, z);
    part.tower.paint(palette.trim, box);
    part.tower.paint(Material.none, footprint(part, tier.shrink + 1, Split.above, z, z));
    foreach (side; SIDES) {
        if (isOpen(part, side, Split.above)) {
            foreach (piece; uncovered(part, box, side, level).slice()) {
                part.tower.paint(palette.trim, piece);
            }
        }
    }
}

void roof(ref const Part part, Palette palette, Material material, Tier tier) {
    part.tower.paint(material, footprint(part, tier.shrink, tier.split, tier.high, tier.high));
    if (tier.hasAbove()) {
        part.tower.paint(palette.floor, footprint(part, tier.aboveShrink + 1, tier.aboveSplit, tier.high, tier.high));
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
    Box box = footprint(part, 0, Split.below, 1, DOOR_TOP);
    foreach (side; SIDES) {
        if (part.kinds[side] == Bound.street) {
            Box face = faceOf(box, side);
            Span run = along(face, side);
            part.tower.paint(Material.glass, withAlong(face, side, Span(run.low + 1, run.high - 1)));
        }
    }
}

void masts(ref const Part part, Palette palette, Tier tier) {
    Box roofBox = footprint(part, tier.shrink + 1, Split.above, tier.high, tier.high);
    if (!isEmpty(roofBox)) {
        int x = middle(xSpan(roofBox));
        int y = middle(ySpan(roofBox));
        size_t axis = 1;
        if (width(xSpan(roofBox)) >= width(ySpan(roofBox))) {
            axis = 0;
        }
        int height = ANTENNA + STORY;
        for (int cell = roofBox.low[axis] + 1; cell <= roofBox.high[axis] - 1; cell += MAST_SPACING) {
            Box mast = boxOf(Span(x, x), Span(cell, cell), Span(tier.high + 1, tier.high + height));
            if (axis == 0) {
                mast = boxOf(Span(cell, cell), Span(y, y), Span(tier.high + 1, tier.high + height));
            }
            part.tower.paint(palette.trim, mast);
            height = higherOf(height - 2, 2);
        }
    }
}

void pyramid(ref const Part part, Palette palette, Tier tier) {
    Box roofBox = footprint(part, tier.shrink + 1, Split.above, tier.high, tier.high);
    int reach = floorDiv(narrowestOf(roofBox) - 1, 2);
    int x = middle(xSpan(roofBox));
    int y = middle(ySpan(roofBox));
    foreach (level; 1 .. reach + 2) {
        int spread = reach + 1 - level;
        part.tower.paint(palette.trim, boxOf(Span(x - spread, x + spread), Span(y - spread, y + spread), Span(tier.high + level, tier.high + level)));
    }
}

void helipad(ref const Part part, Palette palette, Tier tier) {
    Box roofBox = footprint(part, tier.shrink + 1, Split.above, tier.high, tier.high);
    if (width(xSpan(roofBox)) >= LEAST_PAD && width(ySpan(roofBox)) >= LEAST_PAD) {
        int x = middle(xSpan(roofBox));
        int y = middle(ySpan(roofBox));
        int z = tier.high + 1;
        part.tower.paint(Material.concrete, boxOf(Span(x - 2, x + 2), Span(y - 2, y + 2), Span(z, z)));
        part.tower.paint(Material.whiteBrick, boxOf(Span(x - 1, x - 1), Span(y - 1, y + 1), Span(z, z)));
        part.tower.paint(Material.whiteBrick, boxOf(Span(x + 1, x + 1), Span(y - 1, y + 1), Span(z, z)));
        part.tower.paint(Material.whiteBrick, boxOf(Span(x, x), Span(y, y), Span(z, z)));
    }
}

void chimney(ref const Part part, Palette palette, Tier tier) {
    Box roofBox = footprint(part, tier.shrink + 1, Split.above, tier.high, tier.high);
    if (!isEmpty(roofBox)) {
        int x = roofBox.high.x;
        int y = roofBox.high.y;
        part.tower.paint(palette.trim, boxOf(Span(x, x), Span(y, y), Span(tier.high + 1, tier.high + CHIMNEY)));
    }
}

void waterTower(ref const Part part, Palette palette, Tier tier) {
    Box roofBox = footprint(part, tier.shrink, Split.above, tier.high, tier.high);
    int x = roofBox.high.x - 2;
    int y = roofBox.high.y - 2;
    part.tower.paint(Material.steel, boxOf(Span(x, x), Span(y, y), Span(tier.high + 1, tier.high + 1)));
    part.tower.paint(Material.steel, boxOf(Span(x + 1, x + 1), Span(y + 1, y + 1), Span(tier.high + 1, tier.high + 1)));
    part.tower.paint(Material.woodPlanks, boxOf(Span(x, x + 1), Span(y, y + 1), Span(tier.high + 2, tier.high + 4)));
}

struct Core {
    Along along;
    int sign;
    int first;
    int across;
    int lengthRoom;
    int widthRoom;

    bool isRoomy() const {
        return lengthRoom >= CORE_LENGTH && widthRoom >= CORE_WIDTH;
    }
}

Core coreOf(ref const Part part, Box interior) {
    Side side = part.front;
    Along direction = Along.y;
    if (side == Side.xLow || side == Side.xHigh) {
        direction = Along.x;
    }
    size_t alongIndex = axisIndex(direction);
    size_t acrossIndex = 1 - alongIndex;
    Span alongSpan = Span(interior.low[alongIndex], interior.high[alongIndex]);
    Span acrossSpan = Span(interior.low[acrossIndex], interior.high[acrossIndex]);
    int sign = 1;
    int first = alongSpan.low;
    if (side == Side.xHigh || side == Side.yHigh) {
        sign = -1;
        first = alongSpan.high;
    }
    int acrossWidth = width(acrossSpan);
    return Core(direction, sign, first, acrossSpan.low + floorDiv(acrossWidth - CORE_WIDTH, 2), width(alongSpan), acrossWidth);
}

Box coreBox(Core core, int alongLow, int alongHigh, int acrossLow, int acrossHigh, Span z) {
    int a = core.first + core.sign * alongLow;
    int b = core.first + core.sign * alongHigh;
    Span alongSpan = Span(lowerOf(a, b), higherOf(a, b));
    Span acrossSpan = Span(core.across + acrossLow, core.across + acrossHigh);
    if (core.along == Along.x) {
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
            part.tower.paint(material, coreBox(core, tread, tread, lane, lane + 1, Span(1, last - 1)), Rhythm(2 * STORY, floor + 1, tread));
        }
        part.tower.paint(Material.none, coreBox(core, 0, STORY - 1, lane, lane + 1, Span(STORY, last)), Rhythm(2 * STORY, floor + STORY, 1));
    }
}

int wallAlong(Core core, Box ground) {
    size_t axis = axisIndex(core.along);
    if (core.sign > 0) {
        return ground.low[axis];
    } else {
        return ground.high[axis];
    }
}

void coreDoor(ref const Part part, Core core, Box ground) {
    int wall = wallAlong(core, ground);
    Box door = coreBox(core, 0, 0, WALKWAY, WALKWAY + DOOR_WIDTH - 1, Span(1, DOOR_TOP));
    size_t axis = axisIndex(core.along);
    door.low[axis] = lowerOf(wall, wall + core.sign);
    door.high[axis] = higherOf(wall, wall + core.sign);
    part.tower.paint(Material.none, door);
}

void coreStop(ref const Part part, Core core, float alongAt, float across, float z) {
    if (core.along == Along.x) {
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
    while (index < parts.count && parts.items[index].front == Side.none) {
        index += 1;
    }
    if (index < parts.count) {
        const(Part)* entry = &parts.items[index];
        Core core = coreOf(*entry, footprint(*entry, entry.top.shrink + 1, entry.top.split, 0, 0));
        if (core.isRoomy()) {
            Box ground = footprint(*entry, 0, Split.below, 0, 0);
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
        if (area(footprint(part, part.stand.shrink, Split.above, 0, 0)) > area(footprint(*best, best.stand.shrink, Split.above, 0, 0))) {
            main = index;
        }
    }
    chosen(parts.items[main], palette, parts.items[main].stand);
}

uint pick(ref const Parts parts, uint count) {
    return parts.items[0].site.pick(count);
}
