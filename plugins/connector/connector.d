module plugins.connector.connector;

import plugins.api.api : Box, Material, Rhythm, Risen, SitePart;
import plugins.turtle.turtle : Turtle, boxOf, floorMod, higherOf, lowerOf, mixed;

enum int STORY = 4;
enum int HALF_WIDTH = 4;
enum int INNER = HALF_WIDTH - 1;
enum int CORE = 2 * INNER;
enum int TURN = 8;
enum int FLIP_SLACK = 2;
enum int DOOR_TOP = 3;
enum int APRON = 2;
enum int OPEN_GROUND = 0;
enum int CITY_GROUND = 1;
enum int BACKROOMS_GROUND = -1;
enum int LIBRARY_GROUND = 1;
enum int[2] DOOR = [-1, 0];
enum int[2] APRON_WIDTH = [-2, 1];
enum Material LANDING = Material.concrete;
immutable int[2][2] GLASS = [[-3, -2], [1, 2]];
enum int[2] WELL = [2, 3];
enum int WELL_CATCH = 7;
enum uint ROLL_PERCENT = 100;
enum ulong STYLE_SALT = 0x3C6EF372;
enum int GALLERY = 12;
enum int DRIFT_EVERY = 11;
enum int STONE_SIDE = 2;
enum int LANTERN_WIDEST = 11;
enum int LANTERN_TIER = 3;
enum int LANTERN_BAND_EVERY = 2;
immutable int[2][8] STONES = [[-10, -1], [-8, 6], [-1, 8], [6, 6], [8, -1], [6, -8], [-1, -10], [-8, -8]];
immutable int[2][TURN] SEGMENTS = [
    [0, 2],
    [0, 4],
    [2, 4],
    [4, 4],
    [4, 2],
    [4, 0],
    [2, 0],
    [0, 0],
];

enum Tag : uint {
    wild,
    city,
    backrooms,
    tree,
    library,
    column,
    stacks,
}

enum Style : ubyte {
    tower,
    spiral,
    drift,
    lantern,
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

struct Pair {
    Tag lower;
    Tag upper;
    ubyte[Style.max + 1] percents;
}

immutable Pair[16] PAIRS = [
    Pair(Tag.wild, Tag.wild, [39, 44, 11, 6]),
    Pair(Tag.wild, Tag.city, [64, 26, 5, 5]),
    Pair(Tag.wild, Tag.backrooms, [25, 12, 25, 38]),
    Pair(Tag.wild, Tag.library, [28, 39, 17, 16]),
    Pair(Tag.city, Tag.wild, [44, 44, 6, 6]),
    Pair(Tag.city, Tag.city, [67, 22, 5, 6]),
    Pair(Tag.city, Tag.backrooms, [53, 0, 20, 27]),
    Pair(Tag.city, Tag.library, [53, 18, 12, 17]),
    Pair(Tag.backrooms, Tag.wild, [17, 17, 33, 33]),
    Pair(Tag.backrooms, Tag.city, [60, 0, 20, 20]),
    Pair(Tag.backrooms, Tag.backrooms, [57, 0, 21, 22]),
    Pair(Tag.backrooms, Tag.library, [50, 10, 20, 20]),
    Pair(Tag.library, Tag.wild, [29, 36, 21, 14]),
    Pair(Tag.library, Tag.city, [55, 20, 10, 15]),
    Pair(Tag.library, Tag.backrooms, [50, 0, 25, 25]),
    Pair(Tag.library, Tag.library, [50, 28, 6, 16]),
];

bool isEveryPairWhole() {
    foreach (ref pair; PAIRS) {
        uint total = 0;
        foreach (percent; pair.percents) {
            total += percent;
        }
        if (total != ROLL_PERCENT) {
            return false;
        }
    }
    return true;
}

static assert(isEveryPairWhole());

Style styleOf(uint lower, uint upper, ulong vertex) {
    size_t index = 0;
    while (index < PAIRS.length && (PAIRS[index].lower != lower || PAIRS[index].upper != upper)) {
        index += 1;
    }
    if (index == PAIRS.length) {
        return Style.tower;
    } else {
        uint roll = cast(uint)(mixed(vertex, STYLE_SALT) % ROLL_PERCENT);
        uint below = 0;
        uint style = 0;
        while (style < Style.max && roll >= below + PAIRS[index].percents[style]) {
            below += PAIRS[index].percents[style];
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

immutable Palette[4] PALETTES = [
    Palette(Material.whiteBrick, Material.limestone, Material.woodPlanks),
    Palette(Material.redSandstone, Material.whiteBrick, Material.woodPlanks),
    Palette(Material.limestone, Material.steel, Material.concrete),
    Palette(Material.greyBrick, Material.whiteBrick, Material.woodPlanks),
];

immutable Palette DRIFT_PALETTE = Palette(Material.sunlight, Material.limestone, Material.marble);
immutable Palette LANTERN_PALETTE = Palette(Material.glass, Material.steel, Material.marble);

struct Layout {
    int base;
    int top;
    int flip;
}

Box cells(int[2] along, int[2] across, int[2] z) {
    return boxOf([along[0] - INNER, along[1] - INNER], [across[0] - INNER, across[1] - INNER], z);
}

Box square(int half, int[2] z) {
    return boxOf([-half, half - 1], [-half, half - 1], z);
}

void windows(Turtle tower, int[2] z, Rhythm rows) {
    foreach (run; GLASS) {
        tower.paint(Material.glass, boxOf([-HALF_WIDTH, -HALF_WIDTH], run, z), rows);
        tower.paint(Material.glass, boxOf([HALF_WIDTH - 1, HALF_WIDTH - 1], run, z), rows);
        tower.paint(Material.glass, boxOf(run, [-HALF_WIDTH, -HALF_WIDTH], z), rows);
        tower.paint(Material.glass, boxOf(run, [HALF_WIDTH - 1, HALF_WIDTH - 1], z), rows);
    }
}

void shell(Turtle tower, Palette palette, Layout layout) {
    int base = layout.base;
    int top = layout.top;
    int flip = layout.flip;
    tower.paint(palette.wall, square(HALF_WIDTH, [base, base + top]));
    tower.paint(palette.trim, square(HALF_WIDTH, [base, base + top]), Rhythm(STORY, floorMod(base, STORY), 1));
    windows(tower, [base + 1, base + flip], Rhythm(STORY, floorMod(base + 1, STORY), 2));
    windows(tower, [base + flip + 1, base + top - 1], Rhythm(STORY, floorMod(base + top - 2, STORY), 2));
    floors(tower, palette, layout, CORE);
}

void floors(Turtle tower, Palette palette, Layout layout, int span) {
    int low = -INNER;
    int high = low + span - 1;
    tower.paint(palette.floor, boxOf([low, high], [low, high], [layout.base, layout.base]));
    tower.paint(palette.floor, boxOf([low, high], [low, high], [layout.base + layout.top, layout.base + layout.top]));
}

void openFloors(Turtle tower, Palette palette, Layout layout) {
    tower.paint(palette.floor, square(HALF_WIDTH, [layout.base, layout.base]));
    tower.paint(palette.floor, square(HALF_WIDTH, [layout.base + layout.top, layout.base + layout.top]));
}

void posts(Turtle tower, Palette palette, Layout layout) {
    immutable int[2] sides = [-HALF_WIDTH, HALF_WIDTH - 1];
    foreach (x; sides) {
        foreach (y; sides) {
            tower.paint(palette.trim, boxOf([x, x], [y, y], [layout.base, layout.base + layout.top]));
        }
    }
}

void core(Turtle tower, Material material, Material band, Layout layout) {
    int[2] rising = [layout.base, layout.base + layout.top];
    tower.paint(material, cells(WELL, WELL, rising));
    tower.paint(band, cells(WELL, WELL, rising), Rhythm(TURN, floorMod(layout.base, TURN), 1));
}

void flipGallery(Turtle tower, Material material, Layout layout) {
    ring(tower, material, HALF_WIDTH, [layout.base + layout.flip - GALLERY, layout.base + layout.flip + GALLERY]);
}

void spiral(Turtle tower, Palette palette, Layout layout) {
    openFloors(tower, palette, layout);
    posts(tower, palette, layout);
    flipGallery(tower, palette.trim, layout);
}

void stones(Turtle tower, Layout layout) {
    int[2] rising = [layout.base + 1, layout.base + layout.top - 1];
    foreach (index, stone; STONES) {
        int[2] x = [stone[0], stone[0] + STONE_SIDE - 1];
        int[2] y = [stone[1], stone[1] + STONE_SIDE - 1];
        tower.paint(Material.marble, boxOf(x, y, rising), Rhythm(DRIFT_EVERY * cast(int) STONES.length, floorMod(layout.base + cast(int) index * DRIFT_EVERY, DRIFT_EVERY * cast(int) STONES.length), STONE_SIDE));
        tower.paint(Material.sunlight, boxOf(x, y, rising), Rhythm(DRIFT_EVERY * cast(int) STONES.length, floorMod(layout.base + cast(int) index * DRIFT_EVERY + STONE_SIDE, DRIFT_EVERY * cast(int) STONES.length), 1));
    }
}

void drift(Turtle tower, Palette palette, Layout layout) {
    stones(tower, layout);
    openFloors(tower, palette, layout);
    flipGallery(tower, Material.glass, layout);
}

int lanternHalf(Layout layout, int z) {
    int widest = layout.base + layout.flip;
    int reach = lowerOf(layout.flip, layout.top - layout.flip);
    int away = higherOf(z - widest, widest - z);
    return HALF_WIDTH + (LANTERN_WIDEST - HALF_WIDTH) * (reach - lowerOf(reach, away)) / higherOf(reach, 1);
}

void ring(Turtle tower, Material material, int half, int[2] z) {
    tower.paint(material, boxOf([-half, half - 1], [-half, -half], z));
    tower.paint(material, boxOf([-half, half - 1], [half - 1, half - 1], z));
    tower.paint(material, boxOf([-half, -half], [-half, half - 1], z));
    tower.paint(material, boxOf([half - 1, half - 1], [-half, half - 1], z));
}

void lantern(Turtle tower, Palette palette, Layout layout) {
    int end = layout.base + layout.top;
    int tier = 0;
    int low = layout.base;
    while (low < end) {
        int high = lowerOf(low + LANTERN_TIER - 1, end - 1);
        int half = lanternHalf(layout, low);
        tower.paint(palette.trim, square(half, [low, low]));
        tower.paint(Material.none, square(half - 1, [low, high]));
        if (high > low && tier % LANTERN_BAND_EVERY == 0) {
            ring(tower, palette.wall, half, [low + 1, high]);
        } else if (high > low) {
            ring(tower, Material.sunlight, half, [low + 1, high]);
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

void helix(Turtle tower, Material material, Layout layout) {
    int base = layout.base;
    int top = layout.top;
    int flip = layout.flip;
    tower.paint(Material.none, cells([0, CORE - 1], [0, CORE - 1], [base + 1, base + top - 1]));
    tower.paint(material, cells(WELL, WELL, [base + flip + WELL_CATCH, base + flip + WELL_CATCH + 1]));
    foreach (index, segment; SEGMENTS) {
        int i = cast(int) index;
        int[2] along = [segment[0], segment[0] + 1];
        int[2] across = [segment[1], segment[1] + 1];
        int last = flip - floorMod(flip - i, TURN);
        if (last >= 0) {
            tower.paint(material, cells(along, across, [base, base + last]), Rhythm(TURN, floorMod(base + i - 1, TURN), 2));
        }
        int first = firstUpperLayer(layout, i);
        if (first <= top) {
            tower.paint(material, cells(along, across, [base + first, base + top]), Rhythm(TURN, floorMod(base + i + upperShift(layout), TURN), 2));
        }
    }
}

void doorway(Turtle tower, int floor, int[2] room) {
    int[2] apron = [-HALF_WIDTH - APRON, -HALF_WIDTH - 1];
    tower.paint(Material.none, boxOf([-HALF_WIDTH, -HALF_WIDTH], DOOR, room));
    tower.paint(LANDING, boxOf(apron, APRON_WIDTH, [floor, floor]));
    tower.paint(Material.none, boxOf(apron, APRON_WIDTH, room));
}

void tread(Turtle tower, int segment, int z) {
    int[2] at = SEGMENTS[floorMod(segment, TURN)];
    tower.stop(at[0] + 1 - INNER, at[1] + 1 - INNER, z);
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

int groundOf(uint tag) {
    if (tag == Tag.city) {
        return CITY_GROUND;
    } else if (tag == Tag.backrooms) {
        return BACKROOMS_GROUND;
    } else if (tag == Tag.library) {
        return LIBRARY_GROUND;
    } else {
        return OPEN_GROUND;
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
        return styleOf(risen.lower, upperTag, site.hash(SitePart.vertex));
    }
}

void connect(Turtle site, ref const Risen risen, uint upperTag, Connection how) {
    Layout layout = layoutOf(site, risen, groundOf(upperTag), groundOf(risen.lower));
    Style style = chosenStyle(site, risen, upperTag, how);
    Palette palette = PALETTES[site.pick(PALETTES.length)];
    if (style == Style.drift) {
        palette = DRIFT_PALETTE;
    } else if (style == Style.lantern) {
        palette = LANTERN_PALETTE;
    }
    Turtle tower = site.pitchUp().rollRight().forward(risen.edges).pitchUp().pitchUp().rollRight();
    int plane = risen.edges * site.edgeCells();
    if (plane < layout.base + layout.top) {
        tower.paint(Material.none, square(HALF_WIDTH, [plane, layout.base + layout.top - 1]));
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
    }
    helix(tower, palette.floor, layout);
    if (style == Style.spiral) {
        core(tower, palette.wall, palette.trim, layout);
    } else if (style == Style.drift) {
        core(tower, Material.sunlight, Material.sunlight, layout);
    }
    doorway(tower, layout.base, [layout.base + 1, layout.base + DOOR_TOP]);
    doorway(upperDoorFrame(tower, layout), layout.base + layout.top, [layout.base + layout.top - DOOR_TOP, layout.base + layout.top - 1]);
    if (how.routing != Routing.unrouted) {
        route(tower, layout);
    }
    if (how.routing == Routing.roundTrip) {
        routeBack(tower, layout);
    }
}
