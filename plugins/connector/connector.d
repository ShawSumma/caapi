module plugins.connector.connector;

import plugins.api.api : Box, KindTag, Material, Rhythm, Risen, SitePart, Span;
import plugins.api.binding : List, Named, bound;
import plugins.api.content : Content;
import plugins.turtle.turtle : Cell, Turtle, boxOf, floorMod, higherOf, lowerOf, mixed;

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

struct Ground {
    Named tag;
    int level;
}

struct Pair {
    Named lower;
    Named upper;
    uint tower;
    uint spiral;
    uint drift;
    uint lantern;
    uint hidden;

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
        }
    }

    uint total() const {
        return tower + spiral + drift + lantern + hidden;
    }
}

Style styleOf(KindTag lower, uint upper, ulong vertex) {
    const(Pair)[] pairs = materials.pairs.slice();
    size_t index = 0;
    while (index < pairs.length && !(lower.exists && pairs[index].lower.tag == lower.value && pairs[index].upper.tag == upper)) {
        index += 1;
    }
    if (index == pairs.length || pairs[index].total == 0) {
        return Style.tower;
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
    List!(Palette, MOST_PALETTES) palettes;
    Palette drift;
    Palette lantern;
    Palette hidden;
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

void ring(Turtle tower, Material material, int half, Span z) {
    tower.paint(material, boxOf(Span(-half, half - 1), Span(-half, -half), z));
    tower.paint(material, boxOf(Span(-half, half - 1), Span(half - 1, half - 1), z));
    tower.paint(material, boxOf(Span(-half, -half), Span(-half, half - 1), z));
    tower.paint(material, boxOf(Span(half - 1, half - 1), Span(-half, half - 1), z));
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

void helix(Turtle tower, Material material, Layout layout) {
    int base = layout.base;
    int top = layout.top;
    int flip = layout.flip;
    tower.paint(Material.none, cells(Span(0, CORE - 1), Span(0, CORE - 1), Span(base + 1, base + top - 1)));
    tower.paint(material, cells(WELL, WELL, Span(base + flip + WELL_CATCH, base + flip + WELL_CATCH + 1)));
    foreach (index, segment; SEGMENTS) {
        int i = cast(int) index;
        Span along = Span(segment.x, segment.x + 1);
        Span across = Span(segment.y, segment.y + 1);
        int last = flip - floorMod(flip - i, TURN);
        if (last >= 0) {
            tower.paint(material, cells(along, across, Span(base, base + last)), Rhythm(TURN, floorMod(base + i - 1, TURN), 2));
        }
        int first = firstUpperLayer(layout, i);
        if (first <= top) {
            tower.paint(material, cells(along, across, Span(base + first, base + top)), Rhythm(TURN, floorMod(base + i + upperShift(layout), TURN), 2));
        }
    }
}

void doorway(Turtle tower, int floor, Span room) {
    Span apron = Span(-HALF_WIDTH - APRON, -HALF_WIDTH - 1);
    tower.paint(Material.none, boxOf(Span(-HALF_WIDTH, -HALF_WIDTH), DOOR, room));
    tower.paint(materials.landing, boxOf(apron, APRON_WIDTH, Span(floor, floor)));
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

int groundOf(KindTag tag) {
    const(Ground)[] grounds = materials.grounds.slice();
    size_t index = 0;
    while (index < grounds.length && !(tag.exists && grounds[index].tag.tag == tag.value)) {
        index += 1;
    }
    if (index < grounds.length) {
        return grounds[index].level;
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
        return styleOf(risen.lower, upperTag, site.probeHash(SitePart.vertex));
    }
}

void connect(Turtle site, ref const Risen risen, uint upperTag, Connection how) {
    Layout layout = layoutOf(site, risen, groundOf(KindTag.of(upperTag)), groundOf(risen.lower));
    Style style = chosenStyle(site, risen, upperTag, how);
    Palette palette = materials.palettes.items[site.pick(materials.palettes.count)];
    if (style == Style.drift) {
        palette = materials.drift;
    } else if (style == Style.lantern) {
        palette = materials.lantern;
    } else if (style == Style.hidden) {
        palette = materials.hidden;
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
    }
    helix(tower, palette.floor, layout);
    if (style == Style.spiral) {
        core(tower, palette.wall, palette.trim, layout);
    } else if (style == Style.drift) {
        core(tower, materials.light, materials.light, layout);
    } else if (style == Style.hidden) {
        core(tower, palette.trim, palette.trim, layout);
    }
    doorway(tower, layout.base, Span(layout.base + 1, layout.base + DOOR_TOP));
    doorway(upperDoorFrame(tower, layout), layout.base + layout.top, Span(layout.base + layout.top - DOOR_TOP, layout.base + layout.top - 1));
    if (how.routing != Routing.unrouted) {
        route(tower, layout);
    }
    if (how.routing == Routing.roundTrip) {
        routeBack(tower, layout);
    }
}
