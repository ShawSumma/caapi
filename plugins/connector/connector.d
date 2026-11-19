module plugins.connector.connector;

import core.stdc.math : cos, floor, sin, sqrt;
import plugins.api.api : Api, Box, KindTag, Material, Rhythm, Risen, Site, SitePart, Span, dataOf;
import plugins.api.binding : List, Named, bound;
import plugins.api.content : Content;
import plugins.turtle.turtle : Cell, EVERY_HEIGHT, FULL_TURN, GOLDEN_ANGLE, HALF_TURN, PI, Rows, TURN_TREADS, Turtle, boxOf, cornersOf, discRows, floorMod, higherOf, lowerOf, mixed, ringRows, wedgeRows;

enum int STORY = 4;
enum int HALF_WIDTH = 4;
enum int INNER = HALF_WIDTH - 1;
enum int CORE = 2 * INNER;
enum int TURN = 8;
enum int FLIP_SLACK = 2;
enum int DOOR_TOP = 3;
enum int APRON = 2;
enum int OPEN_GROUND = 0;
enum Span DOOR = Span(-1, 0);
enum Span APRON_WIDTH = Span(-2, 1);
immutable Span[2] GLASS = [Span(-3, -2), Span(1, 2)];
enum size_t MOST_PALETTES = 16;
enum size_t MOST_GROUNDS = 16;
enum size_t MOST_PAIRS = 64;
enum Span WELL = Span(2, 3);
enum int WELL_CATCH = 7;
enum ulong STYLE_SALT = 0x3C6EF372;
enum int GALLERY = 12;
enum int DRIFT_EVERY = 11;
enum int STONE_SIDE = 2;
enum int LANTERN_WIDEST = 11;
enum int LANTERN_TIER = 3;
enum int LANTERN_BAND_EVERY = 2;
enum int TRUNK_HALF = HALF_WIDTH + 1;
enum Span TRUNK_COLUMN = Span(-TRUNK_HALF - 1, TRUNK_HALF);
enum double TRUNK_RADIUS = 5.5;
enum double FURROW_DEPTH = 1;
enum int FURROW_EVERY = 9;
enum int FURROW_SPAN = 6;
immutable uint[5] FURROWS = [1, 6, 11, 15, 20];
enum int APPROACH = 6;
enum int BOUGH_FIRST = 12;
enum int BOUGH_EVERY = 6;
enum double BOUGH_OUT = 4.5;
enum int BOUGH_STEPS = 4;
enum double BOUGH_RADIUS = 1.6;
enum double BOUGH_TIP = 1.1;
enum double BOUGH_WANDER = 9;
enum int TWIG_LEAVES = 2;
enum int TIP_LEAVES = 3;
enum int CROWN_LEAST = 14;
enum int CROWN_DEPTH = 7;
enum int CROWN_RADIUS = 9;
enum int CROWN_TALL = 6;
enum uint CROWN_LOBES = 6;
enum double LOBE_OUT = 6;
enum int LOBE_DEPTH = 9;
enum double LOBE_SWAY = 3;
enum int LOBE_LEAST = 4;
enum uint LOBE_CHOICES = 2;
enum int LOBE_TALL = 3;
enum uint ROOT_COUNT = 6;
enum int ROOT_HEIGHT = 3;
enum double ROOT_OUT = 5;
enum double ROOT_STEP = 1.2;
enum int ROOT_STEPS = 3;
enum double ROOT_RADIUS = 1.9;
enum double ROOT_TAPER = 0.4;
enum double ROOT_WANDER = 30;
enum Span KNOT = Span(-1, 0);
immutable Cell[8] STONES = [Cell(-10, -1), Cell(-8, 6), Cell(-1, 8), Cell(6, 6), Cell(8, -1), Cell(6, -8), Cell(-1, -10), Cell(-8, -8)];
immutable Cell[TURN] SEGMENTS = [
    Cell(0, 2),
    Cell(0, 4),
    Cell(2, 4),
    Cell(4, 4),
    Cell(4, 2),
    Cell(4, 0),
    Cell(2, 0),
    Cell(0, 0),
];

enum Style : ubyte {
    tower,
    spiral,
    drift,
    lantern,
    hidden,
    paired,
}

enum Dress : ubyte {
    masonry,
    trunk,
    stairwell,
    shelves,
}

enum End : ubyte {
    lower,
    upper,
}

enum Relief : ubyte {
    flat,
    rough,
}

struct Ends {
    Dress lower;
    Dress upper;
    Relief lowerRelief;
    Relief upperRelief;
}

struct Half {
    Span z;
    int floor;
    End end;
}

enum Routing : ubyte {
    unrouted,
    routed,
    roundTrip,
}

enum StylePick : ubyte {
    rolled,
    forced,
}

struct Connection {
    Routing routing;
    StylePick pick;
    Style style;

    static Connection rolled() {
        return Connection(Routing.unrouted, StylePick.rolled, Style.tower);
    }

    static Connection forced(Style style, Routing routing) {
        return Connection(routing, StylePick.forced, style);
    }
}

enum Bridge : ubyte {
    built,
    hidden,
    none,
}

struct Ground {
    Named tag;
    int level;
    Bridge bridge;
    Dress dress;
    Relief relief;
}

struct Pair {
    Named lower;
    Named upper;
    uint tower;
    uint spiral;
    uint drift;
    uint lantern;
    uint hidden;
    uint paired;

    uint shareOf(Style style) const {
        final switch (style) {
            case Style.tower:
                return tower;
            case Style.spiral:
                return spiral;
            case Style.drift:
                return drift;
            case Style.lantern:
                return lantern;
            case Style.hidden:
                return hidden;
            case Style.paired:
                return paired;
        }
    }

    uint total() const {
        return tower + spiral + drift + lantern + hidden + paired;
    }
}

Style styleOf(KindTag lower, uint upper, ulong vertex) {
    const(Pair)[] pairs = materials.pairs.slice();
    size_t index = 0;
    while (index < pairs.length && !(lower.exists && pairs[index].lower.tag == lower.value && pairs[index].upper.tag == upper)) {
        index += 1;
    }
    if (index == pairs.length || pairs[index].total == 0) {
        return Style.paired;
    } else {
        uint roll = cast(uint)(mixed(vertex, STYLE_SALT) % pairs[index].total);
        uint below = 0;
        uint style = 0;
        while (style < Style.max && roll >= below + pairs[index].shareOf(cast(Style) style)) {
            below += pairs[index].shareOf(cast(Style) style);
            style += 1;
        }
        return cast(Style) style;
    }
}

struct Palette {
    Material wall;
    Material trim;
    Material floor;
}

struct Materials {
    Material landing;
    Material window;
    Material stone;
    Material light;
    Material knot;
    List!(Palette, MOST_PALETTES) palettes;
    Palette drift;
    Palette lantern;
    Palette hidden;
    Palette trunk;
    Palette stairwell;
    Palette shelves;
    List!(Ground, MOST_GROUNDS) grounds;
    List!(Pair, MOST_PAIRS) pairs;
}

__gshared Materials materials;

void resolveConnector(const(Content)* content) {
    materials = content.bound!Materials("connector:materials");
}

struct Layout {
    int base;
    int top;
    int flip;
}

Box cells(Span along, Span across, Span z) {
    return boxOf(Span(along.low - INNER, along.high - INNER), Span(across.low - INNER, across.high - INNER), z);
}

Box square(int half, Span z) {
    return boxOf(Span(-half, half - 1), Span(-half, half - 1), z);
}

void windows(Turtle tower, Span z, Rhythm rows) {
    foreach (run; GLASS) {
        tower.paint(materials.window, boxOf(Span(-HALF_WIDTH, -HALF_WIDTH), run, z), rows);
        tower.paint(materials.window, boxOf(Span(HALF_WIDTH - 1, HALF_WIDTH - 1), run, z), rows);
        tower.paint(materials.window, boxOf(run, Span(-HALF_WIDTH, -HALF_WIDTH), z), rows);
        tower.paint(materials.window, boxOf(run, Span(HALF_WIDTH - 1, HALF_WIDTH - 1), z), rows);
    }
}

void shell(Turtle tower, Palette palette, Layout layout) {
    int base = layout.base;
    int top = layout.top;
    int flip = layout.flip;
    tower.paint(palette.wall, square(HALF_WIDTH, Span(base, base + top)));
    tower.paint(palette.trim, square(HALF_WIDTH, Span(base, base + top)), Rhythm(STORY, floorMod(base, STORY), 1));
    windows(tower, Span(base + 1, base + flip), Rhythm(STORY, floorMod(base + 1, STORY), 2));
    windows(tower, Span(base + flip + 1, base + top - 1), Rhythm(STORY, floorMod(base + top - 2, STORY), 2));
    floors(tower, palette, layout, CORE);
}

void floors(Turtle tower, Palette palette, Layout layout, int span) {
    int low = -INNER;
    int high = low + span - 1;
    tower.paint(palette.floor, boxOf(Span(low, high), Span(low, high), Span(layout.base, layout.base)));
    tower.paint(palette.floor, boxOf(Span(low, high), Span(low, high), Span(layout.base + layout.top, layout.base + layout.top)));
}

void openFloors(Turtle tower, Palette palette, Layout layout) {
    tower.paint(palette.floor, square(HALF_WIDTH, Span(layout.base, layout.base)));
    tower.paint(palette.floor, square(HALF_WIDTH, Span(layout.base + layout.top, layout.base + layout.top)));
}

void posts(Turtle tower, Palette palette, Layout layout) {
    immutable int[2] sides = [-HALF_WIDTH, HALF_WIDTH - 1];
    foreach (x; sides) {
        foreach (y; sides) {
            tower.paint(palette.trim, boxOf(Span(x, x), Span(y, y), Span(layout.base, layout.base + layout.top)));
        }
    }
}

void core(Turtle tower, Material material, Material band, Layout layout) {
    Span rising = Span(layout.base, layout.base + layout.top);
    tower.paint(material, cells(WELL, WELL, rising));
    tower.paint(band, cells(WELL, WELL, rising), Rhythm(TURN, floorMod(layout.base, TURN), 1));
}

void flipGallery(Turtle tower, Material material, Layout layout) {
    ring(tower, material, HALF_WIDTH, Span(layout.base + layout.flip - GALLERY, layout.base + layout.flip + GALLERY));
}

void spiral(Turtle tower, Palette palette, Layout layout) {
    openFloors(tower, palette, layout);
    posts(tower, palette, layout);
    Span rising = Span(layout.base + STORY, layout.base + layout.top - 1);
    ring(tower, palette.trim, HALF_WIDTH, rising, Rhythm(2 * STORY, floorMod(layout.base, 2 * STORY), 1));
    flipGallery(tower, palette.trim, layout);
}

void stones(Turtle tower, Layout layout) {
    Span rising = Span(layout.base + 1, layout.base + layout.top - 1);
    foreach (index, stone; STONES) {
        Span x = Span(stone.x, stone.x + STONE_SIDE - 1);
        Span y = Span(stone.y, stone.y + STONE_SIDE - 1);
        tower.paint(materials.stone, boxOf(x, y, rising), Rhythm(DRIFT_EVERY * cast(int) STONES.length, floorMod(layout.base + cast(int) index * DRIFT_EVERY, DRIFT_EVERY * cast(int) STONES.length), STONE_SIDE));
        tower.paint(materials.light, boxOf(x, y, rising), Rhythm(DRIFT_EVERY * cast(int) STONES.length, floorMod(layout.base + cast(int) index * DRIFT_EVERY + STONE_SIDE, DRIFT_EVERY * cast(int) STONES.length), 1));
    }
}

void drift(Turtle tower, Palette palette, Layout layout) {
    stones(tower, layout);
    openFloors(tower, palette, layout);
    flipGallery(tower, materials.window, layout);
}

int lanternHalf(Layout layout, int z) {
    int widest = layout.base + layout.flip;
    int reach = lowerOf(layout.flip, layout.top - layout.flip);
    int away = higherOf(z - widest, widest - z);
    return HALF_WIDTH + (LANTERN_WIDEST - HALF_WIDTH) * (reach - lowerOf(reach, away)) / higherOf(reach, 1);
}

void ring(Turtle tower, Material material, int half, Span z, Rhythm rows = EVERY_HEIGHT) {
    tower.paint(material, boxOf(Span(-half, half - 1), Span(-half, -half), z), rows);
    tower.paint(material, boxOf(Span(-half, half - 1), Span(half - 1, half - 1), z), rows);
    tower.paint(material, boxOf(Span(-half, -half), Span(-half, half - 1), z), rows);
    tower.paint(material, boxOf(Span(half - 1, half - 1), Span(-half, half - 1), z), rows);
}

Half lowerHalf(Layout layout) {
    return Half(Span(layout.base, layout.base + layout.flip), layout.base, End.lower);
}

Half upperHalf(Layout layout) {
    return Half(Span(layout.base + layout.flip + 1, layout.base + layout.top), layout.base + layout.top, End.upper);
}

Rhythm band(Half half, int row, int span) {
    final switch (half.end) {
        case End.lower:
            return Rhythm(STORY, floorMod(half.floor + row, STORY), span);
        case End.upper:
            return Rhythm(STORY, floorMod(half.floor - row - span + 1, STORY), span);
    }
}

Span roomsOf(Half half) {
    final switch (half.end) {
        case End.lower:
            return Span(half.z.low + 1, half.z.high);
        case End.upper:
            return Span(half.z.low, half.z.high - 1);
    }
}

int lengthOf(Half half) {
    return half.z.high - half.z.low;
}

Span levels(Half half, int from, int to) {
    final switch (half.end) {
        case End.lower:
            return Span(higherOf(half.z.low, half.floor + from), lowerOf(half.z.high, half.floor + to));
        case End.upper:
            return Span(higherOf(half.z.low, half.floor - to), lowerOf(half.z.high, half.floor - from));
    }
}

struct Aside {
    double x = 0;
    double y = 0;
}

Aside asideAt(double around, double reach) {
    double angle = around * PI / HALF_TURN;
    return Aside(reach * cos(angle), reach * sin(angle));
}

void disc(Turtle tower, Material material, Half half, Aside centre, double radius, int from, int to) {
    Span z = levels(half, from, to);
    if (z.low <= z.high) {
        Rows rows = discRows(tower.column(), centre.x, centre.y, radius);
        tower.fillRows(material, rows, z);
    }
}

int widthAt(int radius, int tall, int above) {
    double share = above / (tall + 0.5);
    return cast(int) floor(radius * sqrt(1 - share * share) + 0.5);
}

void blob(Turtle tower, Material material, Half half, Aside centre, int middle, int radius, int tall) {
    int from = -tall;
    while (from <= tall) {
        int wide = widthAt(radius, tall, from);
        int to = from;
        while (to < tall && widthAt(radius, tall, to + 1) == wide) {
            to += 1;
        }
        if (wide > 0) {
            disc(tower, material, half, centre, wide, middle + from, middle + to);
        }
        from = to + 1;
    }
}

void trunk(Turtle tower, Material bark, Half half) {
    Rows body = ringRows(TRUNK_COLUMN, 0, TRUNK_RADIUS);
    tower.paintRows(bark, body, half.z);
    Rows[TURN_TREADS] wedges = wedgeRows(TRUNK_COLUMN, TRUNK_RADIUS - FURROW_DEPTH, TRUNK_RADIUS);
    foreach (index, wedge; FURROWS) {
        tower.paintRows(materials.knot, wedges[wedge], half.z, Rhythm(FURROW_EVERY, floorMod(half.floor + 5 * cast(int) index, FURROW_EVERY), FURROW_SPAN));
    }
}

void roots(Turtle tower, Material bark, Half half) {
    double first = tower.rollUnit() * FULL_TURN;
    foreach (root; 0 .. ROOT_COUNT) {
        double around = first + root * FULL_TURN / ROOT_COUNT + (tower.rollUnit() - 0.5) * ROOT_WANDER;
        foreach (step; 0 .. ROOT_STEPS) {
            disc(tower, bark, half, asideAt(around, ROOT_OUT + step * ROOT_STEP), ROOT_RADIUS - step * ROOT_TAPER, 0, ROOT_HEIGHT - step);
        }
    }
}

void bough(Turtle tower, Palette palette, Half half, double around, int away) {
    foreach (step; 0 .. BOUGH_STEPS) {
        double radius = BOUGH_RADIUS;
        if (step >= BOUGH_STEPS / 2) {
            radius = BOUGH_TIP;
        }
        disc(tower, palette.wall, half, asideAt(around + step * BOUGH_WANDER, BOUGH_OUT + step), radius, away + step, away + step + 1);
    }
    blob(tower, palette.trim, half, asideAt(around + BOUGH_WANDER, BOUGH_OUT + BOUGH_STEPS / 2), away + BOUGH_STEPS / 2 + 1, TWIG_LEAVES, 1);
    blob(tower, palette.trim, half, asideAt(around + BOUGH_STEPS * BOUGH_WANDER, BOUGH_OUT + BOUGH_STEPS), away + BOUGH_STEPS + 1, TIP_LEAVES, 2);
}

void boughs(Turtle tower, Palette palette, Half half) {
    int length = lengthOf(half);
    double around = tower.rollUnit() * FULL_TURN;
    int away = BOUGH_FIRST;
    while (away + CROWN_DEPTH < length) {
        bough(tower, palette, half, around, away);
        around += GOLDEN_ANGLE;
        away += BOUGH_EVERY;
    }
}

void crown(Turtle tower, Material leaves, Half half) {
    int length = lengthOf(half);
    if (length >= CROWN_LEAST) {
        blob(tower, leaves, half, Aside.init, length - CROWN_DEPTH, CROWN_RADIUS, CROWN_TALL);
        double first = tower.rollUnit() * FULL_TURN;
        foreach (lobe; 0 .. CROWN_LOBES) {
            double around = first + lobe * FULL_TURN / CROWN_LOBES;
            int sway = cast(int) floor((tower.rollUnit() - 0.5) * 2 * LOBE_SWAY);
            int radius = LOBE_LEAST + cast(int) tower.pick(LOBE_CHOICES);
            blob(tower, leaves, half, asideAt(around, LOBE_OUT), length - LOBE_DEPTH + sway, radius, LOBE_TALL);
        }
    }
}

void knots(Turtle tower, Span z, Rhythm rows) {
    tower.paint(Material.none, boxOf(KNOT, Span(-TRUNK_HALF, -HALF_WIDTH), z), rows);
    tower.paint(Material.none, boxOf(KNOT, Span(HALF_WIDTH - 1, TRUNK_HALF - 1), z), rows);
}

void lamp(Turtle tower, Half half) {
    if (half.end == End.lower) {
        int over = half.floor + DOOR_TOP + 1;
        tower.paint(materials.light, boxOf(Span(-TRUNK_HALF, -TRUNK_HALF), DOOR, Span(over, over)));
    }
}

void approach(Turtle door, int floor, End end) {
    foreach (away; 1 .. APPROACH + 1) {
        Span x = Span(-HALF_WIDTH - APRON - away, -HALF_WIDTH - APRON - away);
        final switch (end) {
            case End.lower:
                door.paint(Material.none, boxOf(x, APRON_WIDTH, Span(floor + away + 1, floor + away + DOOR_TOP)));
                break;
            case End.upper:
                door.paint(Material.none, boxOf(x, APRON_WIDTH, Span(floor - away - DOOR_TOP, floor - away - 1)));
                break;
        }
    }
}

void dress(Turtle tower, Dress dress, Palette palette, Half half) {
    final switch (dress) {
        case Dress.masonry:
            tower.paint(palette.wall, square(HALF_WIDTH, half.z));
            tower.paint(palette.trim, square(HALF_WIDTH, half.z), band(half, 0, 1));
            windows(tower, roomsOf(half), band(half, 1, 2));
            break;
        case Dress.trunk:
            crown(tower, palette.trim, half);
            boughs(tower, palette, half);
            roots(tower, palette.wall, half);
            trunk(tower, palette.wall, half);
            knots(tower, roomsOf(half), band(half, 1, 2));
            lamp(tower, half);
            break;
        case Dress.stairwell:
            tower.paint(palette.wall, square(HALF_WIDTH, half.z));
            tower.paint(palette.trim, square(HALF_WIDTH, half.z), band(half, STORY - 1, 1));
            break;
        case Dress.shelves:
            tower.paint(palette.wall, square(HALF_WIDTH, half.z));
            tower.paint(palette.trim, square(HALF_WIDTH, half.z), band(half, 1, 2));
            break;
    }
}

void paired(Turtle tower, Ends ends, Palette lower, Palette upper, Layout layout) {
    dress(tower, ends.lower, lower, lowerHalf(layout));
    dress(tower, ends.upper, upper, upperHalf(layout));
    tower.paint(lower.floor, square(INNER, Span(layout.base, layout.base)));
    tower.paint(upper.floor, square(INNER, Span(layout.base + layout.top, layout.base + layout.top)));
}

Palette dressedIn(Dress dress, Palette masonry) {
    final switch (dress) {
        case Dress.masonry:
            return masonry;
        case Dress.trunk:
            return materials.trunk;
        case Dress.stairwell:
            return materials.stairwell;
        case Dress.shelves:
            return materials.shelves;
    }
}

void lantern(Turtle tower, Palette palette, Layout layout) {
    int end = layout.base + layout.top;
    int tier = 0;
    int low = layout.base;
    while (low < end) {
        int high = lowerOf(low + LANTERN_TIER - 1, end - 1);
        int half = lanternHalf(layout, low);
        tower.paint(palette.trim, square(half, Span(low, low)));
        tower.paint(Material.none, square(half - 1, Span(low, high)));
        if (high > low && tier % LANTERN_BAND_EVERY == 0) {
            ring(tower, palette.wall, half, Span(low + 1, high));
        } else if (high > low) {
            ring(tower, materials.light, half, Span(low + 1, high));
        }
        low = high + 1;
        tier += 1;
    }
    openFloors(tower, palette, layout);
}

int upperShift(Layout layout) {
    return floorMod(layout.top, 2);
}

int upperDoorQuarters(Layout layout) {
    return floorMod(layout.top, TURN) / 2;
}

int firstUpperLayer(Layout layout, int segment) {
    return layout.flip + 1 + floorMod(segment + upperShift(layout) - layout.flip - 1, TURN);
}

Turtle upperDoorFrame(Turtle tower, Layout layout) {
    Turtle frame = tower;
    foreach (_; 0 .. upperDoorQuarters(layout)) {
        frame = frame.rollRight();
    }
    return frame;
}

void helix(Turtle tower, Material lower, Material upper, Layout layout) {
    int base = layout.base;
    int top = layout.top;
    int flip = layout.flip;
    tower.paint(Material.none, cells(Span(0, CORE - 1), Span(0, CORE - 1), Span(base + 1, base + top - 1)));
    tower.paint(upper, cells(WELL, WELL, Span(base + flip + WELL_CATCH, base + flip + WELL_CATCH + 1)));
    foreach (index, segment; SEGMENTS) {
        int i = cast(int) index;
        Span along = Span(segment.x, segment.x + 1);
        Span across = Span(segment.y, segment.y + 1);
        int last = flip - floorMod(flip - i, TURN);
        if (last >= 0) {
            tower.paint(lower, cells(along, across, Span(base, base + last)), Rhythm(TURN, floorMod(base + i - 1, TURN), 2));
        }
        int first = firstUpperLayer(layout, i);
        if (first <= top) {
            tower.paint(upper, cells(along, across, Span(base + first, base + top)), Rhythm(TURN, floorMod(base + i + upperShift(layout), TURN), 2));
        }
    }
}

void doorway(Turtle tower, int floor, Span room, Material landing) {
    Span apron = Span(-HALF_WIDTH - APRON, -HALF_WIDTH - 1);
    tower.paint(Material.none, boxOf(Span(-HALF_WIDTH, -HALF_WIDTH), DOOR, room));
    tower.paint(landing, boxOf(apron, APRON_WIDTH, Span(floor, floor)));
    tower.paint(Material.none, boxOf(apron, APRON_WIDTH, room));
}

void tread(Turtle tower, int segment, int z) {
    Cell at = SEGMENTS[floorMod(segment, TURN)];
    tower.stop(at.x + 1 - INNER, at.y + 1 - INNER, z);
}

void route(Turtle tower, Layout layout) {
    int base = layout.base;
    int top = layout.top;
    tower.stop(-HALF_WIDTH - 1.5f, 0, base + 1);
    tower.stop(0.5f - INNER, 0, base + 1);
    int highest = layout.flip - FLIP_SLACK;
    foreach (layer; 1 .. highest + 1) {
        tread(tower, layer, base + layer + 1);
    }
    foreach (layer; firstUpperLayer(layout, highest + 1) .. top + 1) {
        tread(tower, layer - upperShift(layout), base + layer);
    }
    Turtle door = upperDoorFrame(tower, layout);
    door.stop(0.5f - INNER, 0, base + top);
    door.stop(-HALF_WIDTH - 0.5f, 0, base + top);
}

void routeBack(Turtle tower, Layout layout) {
    int base = layout.base;
    int flip = layout.flip;
    int lowest = flip + FLIP_SLACK + 1;
    upperDoorFrame(tower, layout).stop(0.5f - INNER, 0, base + layout.top);
    foreach_reverse (layer; lowest .. layout.top + 1) {
        tread(tower, layer - upperShift(layout), base + layer);
    }
    int crossing = lowest - 1 - upperShift(layout);
    foreach_reverse (layer; 1 .. flip - floorMod(flip - crossing, TURN) + 1) {
        tread(tower, layer, base + layer + 1);
    }
    tower.stop(0.5f - INNER, 0, base + 1);
    tower.stop(-HALF_WIDTH - 1.5f, 0, base + 1);
}

Ground groundOf(KindTag tag) {
    const(Ground)[] grounds = materials.grounds.slice();
    size_t index = 0;
    while (index < grounds.length && !(tag.exists && grounds[index].tag.tag == tag.value)) {
        index += 1;
    }
    if (index < grounds.length) {
        return grounds[index];
    } else {
        return Ground(Named.init, OPEN_GROUND, Bridge.built);
    }
}

Layout layoutOf(Turtle site, ref const Risen risen, int upper, int lower) {
    int length = risen.edges * site.edgeCells();
    int base = lower - 1;
    return Layout(base, length - upper - base, length - risen.balance - base - 1);
}

Style chosenStyle(Turtle site, ref const Risen risen, uint upperTag, Connection how) {
    if (how.pick == StylePick.forced) {
        return how.style;
    } else {
        return styleOf(risen.lower, upperTag, site.probeHash(SitePart.vertex));
    }
}

void connect(Turtle site, ref const Risen risen, uint upperTag, Connection how) {
    Ground upper = groundOf(KindTag.of(upperTag));
    Ground lower = groundOf(risen.lower);
    Connection chosen = how;
    if (upper.bridge == Bridge.hidden) {
        chosen = Connection.forced(Style.hidden, how.routing);
    }
    if (upper.bridge != Bridge.none && lower.bridge == Bridge.built) {
        bridge(site, risen, upperTag, chosen, layoutOf(site, risen, upper.level, lower.level), Ends(lower.dress, upper.dress, lower.relief, upper.relief));
    }
}

bool probeOwnsFoot(Turtle face, ref const Risen risen) {
    ulong foot = Turtle(face.api, risen.foot).probeHash(SitePart.vertex);
    foreach (corner; cornersOf(face)) {
        if (corner.probeHash(SitePart.vertex) == foot && corner.probeOwns(SitePart.vertex)) {
            return true;
        }
    }
    return false;
}

void footTile(const(Api)* api, Site foot, const(Risen)* risen, const(void)* data) {
    connect(Turtle(api, foot), *risen, risen.tag.value, dataOf!Connection(data));
}

void bridge(Turtle site, ref const Risen risen, uint upperTag, Connection how, Layout layout, Ends ends) {
    Style style = chosenStyle(site, risen, upperTag, how);
    Palette palette = materials.palettes.items[site.pick(materials.palettes.count)];
    if (style == Style.drift) {
        palette = materials.drift;
    } else if (style == Style.lantern) {
        palette = materials.lantern;
    } else if (style == Style.hidden) {
        palette = materials.hidden;
    }
    Palette above = palette;
    if (style == Style.paired) {
        above = dressedIn(ends.upper, materials.palettes.items[site.pick(materials.palettes.count)]);
        palette = dressedIn(ends.lower, palette);
    }
    Turtle tower = site.pitchUp().rollRight().forward(risen.edges).pitchUp().pitchUp().rollRight();
    int plane = risen.edges * site.edgeCells();
    if (plane < layout.base + layout.top) {
        tower.paint(Material.none, square(HALF_WIDTH, Span(plane, layout.base + layout.top - 1)));
    }
    final switch (style) {
        case Style.tower:
            shell(tower, palette, layout);
            break;
        case Style.spiral:
            spiral(tower, palette, layout);
            break;
        case Style.drift:
            drift(tower, palette, layout);
            break;
        case Style.lantern:
            lantern(tower, palette, layout);
            break;
        case Style.hidden:
            openFloors(tower, palette, layout);
            flipGallery(tower, palette.wall, layout);
            break;
        case Style.paired:
            paired(tower, ends, palette, above, layout);
            break;
    }
    helix(tower, palette.floor, above.floor, layout);
    if (style == Style.spiral) {
        core(tower, palette.wall, palette.trim, layout);
    } else if (style == Style.drift) {
        core(tower, materials.light, materials.light, layout);
    } else if (style == Style.hidden) {
        core(tower, palette.trim, palette.trim, layout);
    }
    Material landing = materials.landing;
    if (style == Style.hidden) {
        landing = palette.floor;
    }
    doorway(tower, layout.base, Span(layout.base + 1, layout.base + DOOR_TOP), landing);
    doorway(upperDoorFrame(tower, layout), layout.base + layout.top, Span(layout.base + layout.top - DOOR_TOP, layout.base + layout.top - 1), landing);
    if (ends.lowerRelief == Relief.rough) {
        approach(tower, layout.base, End.lower);
    }
    if (ends.upperRelief == Relief.rough) {
        approach(upperDoorFrame(tower, layout), layout.base + layout.top, End.upper);
    }
    if (how.routing != Routing.unrouted) {
        route(tower, layout);
    }
    if (how.routing == Routing.roundTrip) {
        routeBack(tower, layout);
    }
}
