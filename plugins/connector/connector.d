module plugins.connector.connector;

import plugins.api.api : Box, Material, Rhythm, Risen, SitePart;
import plugins.turtle.turtle : Turtle, boxOf, floorMod, higherOf, lowerOf, mixed;

enum int STORY = 4;
enum int HALF_WIDTH = 4;
enum int INNER = HALF_WIDTH - 1;
enum int CORE = 2 * INNER;
enum int TURN = 8;
enum int FLIP_CLEARANCE = 1;
enum int FLIP_SLACK = 2;
enum int FOOTING = 8;
enum int DOOR_TOP = 3;
enum int CITY_GROUND = 1;
enum int BACKROOMS_GROUND = -1;
enum int LIBRARY_GROUND = 1;
enum int[2] DOOR = [-1, 0];
enum int[2] STOOP = [-2, 1];
enum Material LANDING = Material.concrete;
immutable int[2][2] GLASS = [[-3, -2], [1, 2]];
enum int[2] WELL = [2, 3];
enum uint ROLL_PERCENT = 100;
enum ulong STYLE_SALT = 0x3C6EF372;
enum int GALLERY_BELOW = 5;
enum int GALLERY_ABOVE = 11;
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
}

enum Style : ubyte {
    none,
    tower,
    spiral,
    drift,
    lantern,
}

struct Connection {
    bool isRouted;
    bool isForced;
    Style style;

    static Connection rolled() {
        return Connection(false, false, Style.none);
    }

    static Connection forced(Style style, bool isRouted) {
        return Connection(isRouted, true, style);
    }
}

struct Pair {
    Tag lower;
    Tag upper;
    ubyte[Style.max + 1] percents;
}

// Percent chances of each style, in the order of Style. A pair left out of the table is never connected.
immutable Pair[12] PAIRS = [
    Pair(Tag.wild, Tag.wild, [10, 35, 40, 10, 5]),
    Pair(Tag.wild, Tag.city, [5, 60, 25, 5, 5]),
    Pair(Tag.wild, Tag.backrooms, [20, 20, 10, 20, 30]),
    Pair(Tag.wild, Tag.library, [10, 25, 35, 15, 15]),
    Pair(Tag.city, Tag.wild, [10, 40, 40, 5, 5]),
    Pair(Tag.city, Tag.city, [10, 60, 20, 5, 5]),
    Pair(Tag.city, Tag.backrooms, [25, 40, 0, 15, 20]),
    Pair(Tag.city, Tag.library, [15, 45, 15, 10, 15]),
    Pair(Tag.backrooms, Tag.wild, [40, 10, 10, 20, 20]),
    Pair(Tag.backrooms, Tag.backrooms, [30, 40, 0, 15, 15]),
    Pair(Tag.library, Tag.wild, [30, 20, 25, 15, 10]),
    Pair(Tag.library, Tag.library, [10, 45, 25, 5, 15]),
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
        return Style.none;
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
    int below;
    int stoop;
    int base;
    int top;
    int split;
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
    int split = layout.split;
    tower.paint(palette.wall, square(HALF_WIDTH, [base, base + top]));
    tower.paint(palette.trim, square(HALF_WIDTH, [base, base + top]), Rhythm(STORY, floorMod(base, STORY), 1));
    windows(tower, [base + 1, base + split], Rhythm(STORY, floorMod(base + 1, STORY), 2));
    windows(tower, [base + split + 1, base + top - 1], Rhythm(STORY, floorMod(base + top - 2, STORY), 2));
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

// Near the balance gravity weakens and turns over, and a walker there drifts wherever it last pushed. Open stairs wall in
// this one stretch so nobody drifts off the side.
void flipGallery(Turtle tower, Material material, Layout layout) {
    ring(tower, material, HALF_WIDTH, [layout.base + layout.flip - GALLERY_BELOW, layout.base + layout.flip + GALLERY_ABOVE]);
}

void spiral(Turtle tower, Palette palette, Layout layout) {
    openFloors(tower, palette, layout);
    posts(tower, palette, layout);
    flipGallery(tower, palette.trim, layout);
}

void stones(Turtle tower, Layout layout) {
    int[2] rising = [layout.base - DRIFT_EVERY, layout.base + layout.top + DRIFT_EVERY];
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
    int widest = layout.base + layout.split;
    int reach = lowerOf(layout.split, layout.top - layout.split);
    int growth = (LANTERN_WIDEST - HALF_WIDTH) * (reach - lowerOf(reach, z > widest ? z - widest : widest - z)) / higherOf(reach, 1);
    return HALF_WIDTH + growth;
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

int landingLayer(int flip) {
    return flip - FLIP_SLACK + 1 + TURN;
}

void helix(Turtle tower, Material material, Layout layout) {
    int base = layout.base;
    int top = layout.top;
    int flip = layout.flip;
    int landing = base + landingLayer(flip);
    tower.paint(Material.none, cells([0, CORE - 1], [0, CORE - 1], [base + 1, base + top - 1]));
    tower.paint(material, cells(WELL, WELL, [landing, landing + 1]));
    foreach (index, segment; SEGMENTS) {
        int i = cast(int) index;
        int[2] along = [segment[0], segment[0] + 1];
        int[2] across = [segment[1], segment[1] + 1];
        int last = flip - floorMod(flip - i, TURN);
        if (last >= 0) {
            tower.paint(material, cells(along, across, [base, base + last]), Rhythm(TURN, floorMod(base + i - 1, TURN), 2));
        }
        if (last + TURN <= top) {
            tower.paint(material, cells(along, across, [base + last + TURN, base + top]), Rhythm(TURN, floorMod(base + i, TURN), 2));
        }
    }
}

void lowerDoor(Turtle tower, Palette palette, Layout layout, int footing) {
    int base = layout.base;
    int below = layout.below;
    tower.paint(Material.none, boxOf([-HALF_WIDTH, -HALF_WIDTH], DOOR, [base + 1, base + DOOR_TOP]));
    foreach (distance; 1 .. layout.stoop + 2) {
        int[2] x = [-HALF_WIDTH - distance, -HALF_WIDTH - distance];
        int surface = higherOf(below, base + 1 - distance);
        if (footing > 1) {
            tower.fill(palette.trim, boxOf(x, STOOP, [below - footing, below - 2]));
        }
        tower.paint(palette.trim, boxOf(x, STOOP, [below - 1, surface - 1]));
        tower.paint(Material.none, boxOf(x, STOOP, [surface, base + DOOR_TOP]));
    }
}

void upperDoor(Turtle tower, Layout layout, int footing) {
    int floor = layout.base + layout.top;
    int[2] x = [-HALF_WIDTH - 1, -HALF_WIDTH - 1];
    tower.paint(Material.none, boxOf([-HALF_WIDTH, -HALF_WIDTH], DOOR, [floor - DOOR_TOP, floor - 1]));
    tower.fill(LANDING, boxOf(x, STOOP, [floor + 1, floor + footing]));
    tower.paint(LANDING, boxOf(x, STOOP, [floor, floor]));
    tower.paint(Material.none, boxOf(x, STOOP, [floor - DOOR_TOP, floor - 1]));
}

void tread(Turtle tower, int layer, int z) {
    int[2] segment = SEGMENTS[floorMod(layer, TURN)];
    tower.stop(segment[0] + 1 - INNER, segment[1] + 1 - INNER, z);
}

void route(Turtle tower, Layout layout) {
    int base = layout.base;
    int top = layout.top;
    int flip = layout.flip;
    tower.stop(-HALF_WIDTH - layout.stoop - 0.5f, 0, layout.below);
    tower.stop(0.5f - INNER, 0, base + 1);
    foreach (layer; 1 .. flip - FLIP_SLACK + 1) {
        tread(tower, layer, base + layer + 1);
    }
    foreach (layer; landingLayer(flip) .. top + 1) {
        tread(tower, layer, base + layer);
    }
    tower.stop(0.5f - INNER, 0, base + top);
    tower.stop(-HALF_WIDTH - 0.5f, 0, base + top);
}

struct Floor {
    int open;
    int footing;
}

Floor terrainFloor(int open) {
    return Floor(open, FOOTING);
}

Floor slabFloor(int open) {
    return Floor(open, 1);
}

Floor floorOf(uint tag, int measured) {
    if (tag == Tag.city) {
        return slabFloor(CITY_GROUND);
    } else if (tag == Tag.backrooms) {
        return slabFloor(BACKROOMS_GROUND);
    } else if (tag == Tag.library) {
        return slabFloor(LIBRARY_GROUND);
    } else {
        return terrainFloor(measured);
    }
}

Layout layoutOf(Turtle site, ref const Risen risen, Floor upper, Floor lower) {
    int length = risen.edges * site.edgeCells();
    int upperFloor = length - upper.open;
    int stoop = floorMod(upperFloor - lower.open + 1, TURN);
    int base = lower.open - 1 + stoop;
    int split = length - risen.balance - base - 1;
    return Layout(lower.open, stoop, base, upperFloor - base, split, split + 1 - FLIP_CLEARANCE);
}

Style chosenStyle(Turtle site, ref const Risen risen, uint upperTag, Connection how) {
    if (how.isForced) {
        return how.style;
    } else {
        return styleOf(risen.lower, upperTag, site.hash(SitePart.vertex));
    }
}

void connect(Turtle site, ref const Risen risen, uint upperTag, Connection how) {
    Floor upper = floorOf(upperTag, risen.ground);
    Floor lower = floorOf(risen.lower, risen.below);
    Layout layout = layoutOf(site, risen, upper, lower);
    Style style = chosenStyle(site, risen, upperTag, how);
    if (style != Style.none && layout.split >= STORY && layout.top - layout.split > STORY && layout.top >= 2 * TURN) {
        Palette palette = PALETTES[site.pick(PALETTES.length)];
        if (style == Style.drift) {
            palette = DRIFT_PALETTE;
        } else if (style == Style.lantern) {
            palette = LANTERN_PALETTE;
        }
        Turtle tower = site.pitchUp().rollRight().forward(risen.edges).pitchUp().pitchUp().rollRight();
        if (layout.below - lower.footing < layout.base) {
            tower.fill(palette.trim, square(HALF_WIDTH, [layout.below - lower.footing, layout.base - 1]));
        }
        tower.fill(palette.trim, square(HALF_WIDTH, [layout.base + layout.top + 1, layout.base + layout.top + upper.footing]));
        final switch (style) {
            case Style.none:
                break;
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
        lowerDoor(tower, palette, layout, lower.footing);
        upperDoor(tower, layout, upper.footing);
        if (how.isRouted) {
            route(tower, layout);
        }
    }
}

