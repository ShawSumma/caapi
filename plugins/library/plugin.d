module plugins.library.plugin;

import plugins.api.api : Api, HorosphereForm, KindId, KindTag, Material, Registry, Rhythm, Risen, RisingKind, Site, SitePart, Span, Spot, entryOf, tagNamed;
import plugins.api.binding : List, bound, settingsOf;
import plugins.api.content : BASE, Content, Dependency, FIRST_VERSION, Manifest, dependencyOn;
import blocks = plugins.blocks.blocks;
import plugins.connector.connector : Connection, connect, resolveConnector;
import plugins.turtle.turtle : Along, Cell, EVERY_HEIGHT, Offset, Rows, STAIR_HEADROOM, TURN_TREADS, Turtle, boxOf, cornersOf, floorDiv, floorMod, higherOf, line, lowerOf, onWedge, ringRows, roll, treadSpan, upright, wedgeRows;

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
immutable Spot SPAWN = Spot(10, 7, 1);

struct Materials {
    Material frame;
    Material ceiling;
    Material lamp;
    Material table;
    Material stair;
    Material well;
    List!(Material, MOST_CHOICES) floors;
    List!(Material, MOST_CHOICES) books;
}

__gshared Materials materials;

struct Tuning {
    double riseOdds;
    double shaftOdds;
    double hallOdds;
    double stairOdds;
    double arcadeOdds;
    double solidOdds;
    double fog;
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
    bool clear = corner.probeRising().exists;
    if (!clear && risen.hasRisen) {
        clear = blocks.probeFoot(corner, risen);
    }
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
            q.tower.paint(material, boxOf(Span(CLEAR, far), Span(0, far), open), rhythm);
            q.tower.paint(material, boxOf(Span(0, CLEAR - 1), Span(CLEAR, far), open), rhythm);
        }
    }
}

void shelves(Turtle tower, Along direction, Span span) {
    Span rooms = Span(BOTTOM + 1, ROOF - 1);
    tower.paint(materials.frame, line(direction, span, rooms));
    foreach (along; span.low .. span.high + 1) {
        foreach (row; WALL_BOOKS) {
            tower.paint(bookOf(tower), line(direction, Span(along, along), rooms), row);
        }
    }
}

void wall(Turtle tower, Along direction, ulong edge) {
    int far = tower.column().high;
    final switch (wallOf(edge)) {
        case Wall.door:
            shelves(tower, direction, Span(0, far - DOOR));
            break;
        case Wall.arcade:
            shelves(tower, direction, Span(0, PIER - 1));
            break;
        case Wall.solid:
            shelves(tower, direction, Span(0, far));
            break;
    }
}

void stack(Turtle tower, Span x, Span y) {
    Span rooms = Span(BOTTOM + 1, ROOF - 1);
    tower.paint(materials.frame, boxOf(x, y, rooms), Rhythm(STORY, 1, 3));
    tower.paint(bookOf(tower), boxOf(x, y, rooms), Rhythm(STORY, 2, 1));
}

void floors(ref const Quarter q, Kind kind, Material material) {
    Span whole = Span(BOTTOM, ROOF);
    int story = STORY;
    if (kind == Kind.hall) {
        story = HALL_STORY;
    }
    spread(q, Material.none, Span(BOTTOM + 1, ROOF - 1), EVERY_HEIGHT);
    spread(q, material, whole, Rhythm(story, 0, 1));
    spread(q, materials.ceiling, whole, Rhythm(story, story - 1, 1));
    q.tower.paint(materials.lamp, boxOf(Span(LAMP.x, LAMP.x), Span(LAMP.y, LAMP.y), whole), Rhythm(story, story - 1, 1));
    if (kind == Kind.hall) {
        q.tower.paint(materials.table, boxOf(TABLE_X, TABLE_Y, whole), Rhythm(HALL_STORY, 1, 1));
    }
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
        floors(q, kind, material);
        if (!q.isClear()) {
            wall(q.tower, Along.x, corner.probeHash(SitePart.edge));
            wall(q.tower, Along.y, corner.right().probeHash(SitePart.edge));
        }
        if (kind == Kind.stair && index == 0 && !q.isClear()) {
            stairwell(q.tower);
        } else if (kind == Kind.gallery) {
            stack(q.tower, Span(3, 7), Span(CLEAR, CLEAR + 1));
            uint second = q.tower.pick(2);
            if (second == 0) {
                stack(q.tower, Span(3, 7), Span(CLEAR + 3, CLEAR + 4));
            }
        }
    }
}

void tile(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    Turtle face = Turtle(api, site);
    Connection connection = *cast(const(Connection)*) data;
    ulong hash = face.probeHash(SitePart.face);
    Kind kind = kindOf(hash);
    Material material = floorOf(hash);
    foreach (index, corner; cornersOf(face)) {
        quarter(corner, index, kind, material, *risen);
    }
    if (risen.hasRisen) {
        bool owner = blocks.probeOwnsFoot(face, *risen);
        if (owner) {
            connect(Turtle(api, risen.foot), *risen, LIBRARY_TAG, connection);
        }
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

void shaft(const(Api)* api, Site base, const(Risen)* risen, const(void)* data) {
    Turtle tower = Turtle(api, base);
    int length = tower.edgeCells();
    int bottom = risen.segment * length;
    int top = lowerOf(ROOF, bottom + length - 1);
    Material floor = floorOf(Turtle(api, risen.foot).probeHash(SitePart.vertex));
    Span deep = Span(bottom, lowerOf(BOTTOM - 1, top));
    Span slab = Span(higherOf(BOTTOM, bottom), top);
    if (deep.low <= deep.high) {
        Span z = Span(deep.low - bottom, deep.high - bottom);
        stories(tower, SHELF, z, floor);
        shelving(tower, z);
    }
    if (slab.low <= slab.high) {
        stories(tower, EVERYWHERE, Span(slab.low - bottom, slab.high - bottom), floor);
    }
    int lastTread = TURN_TREADS - 1;
    if (risen.segment == 0) {
        lastTread = TOP_TREAD;
        Rows cap = ringRows(tower.column(), 0, WELL);
        tower.paintRows(materials.ceiling, cap, Span(ROOF, ROOF));
    }
    descent(tower, lastTread);
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
    Connection connection = Connection.rolled();
    KindId kind = api.horosphere(api, tuning.riseOdds, HorosphereForm.solid, LIBRARY_TAG, &tile, &connection, Connection.sizeof);
    api.rooted(api, kind);
    api.look(api, kind, LOOK);
    KindId stacks = api.sunken(api, tuning.shaftOdds, LIBRARY_TAG, STACKS_TAG, &shaft, null, 0);
    api.openHorosphere(api, site, stacks, 2);
    api.fog(api, tuning.fog);
    Turtle tower = at.columnSite();
    route(tower);
    tower.entrance(SPAWN.x, SPAWN.y, SPAWN.z);
}

immutable Dependency[2] NEEDS = [dependencyOn(BASE), dependencyOn("connector")];
immutable Manifest MANIFEST = Manifest("library", FIRST_VERSION, NEEDS[], null, &resolve, null, import("plugins/library/settings.conf"), import("plugins/library/library.decl"), import("plugins/library/library.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.add(registry, "library", &world);
    RisingKind rising = RisingKind(1, HorosphereForm.solid, LIBRARY_TAG, &tile, &ROLLED, Connection.sizeof, LOOK);
    registry.addKind(registry, "library", &rising);
    RisingKind stacks = RisingKind(SHAFT_SHARE, HorosphereForm.sunken, STACKS_TAG, &shaft, null, 0, LOOK, LIBRARY_TAG);
    registry.addKind(registry, "librarystacks", &stacks);
}
