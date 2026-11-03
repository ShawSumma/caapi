module plugins.library.plugin;

import plugins.api.api : Api, ENTRY, HorosphereForm, Look, Material, Registry, Rhythm, Risen, RisingKind, Site, SitePart, Tint;
import blocks = plugins.blocks.blocks;
import plugins.connector.connector : Connection, Tag, connect;
import plugins.turtle.turtle : Along, Rows, STAIR_HEADROOM, TURN_TREADS, Turtle, boxOf, cornersOf, floorDiv, floorMod, higherOf, line, lowerOf, onWedge, ringRows, roll, treadSpan, upright, wedgeRows;

immutable Look LOOK = Look("library", [0.72f, 0.62f, 0.46f], Tint.fog);

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
enum int[2] LAMP = [10, 4];
enum int[2] TABLE_X = [3, 8];
enum int[2] TABLE_Y = [5, 6];
enum double RISE_ODDS = 0.02;
enum double SHAFT_ODDS = 0.06;
enum double SHAFT_SHARE = 2;
enum double HALL_ODDS = 0.15;
enum double STAIR_ODDS = 0.2;
enum double ARCADE_ODDS = 0.12;
enum double SOLID_ODDS = 0.2;
enum ulong KIND_SALT = 0x3B9ACA07;
enum ulong FLOOR_SALT = 0x7F4A7C15;
enum ulong WALL_SALT = 0x1B873593;
enum Material FRAME = Material.spruceWood;
enum Material CEILING = Material.plaster;
enum double FOG = 6;
immutable Material[4] FLOORS = [Material.woodPlanks, Material.spruceWood, Material.marble, Material.redCarpet];
immutable Material[7] BOOKS = [Material.redCarpet, Material.acaciaWood, Material.jungleWood, Material.birchWood, Material.oakWood, Material.carpet, Material.redSandstone];
immutable Rhythm[2] WALL_BOOKS = [Rhythm(2 * STORY, 2, 2), Rhythm(2 * STORY, STORY + 2, 2)];
immutable Connection ROLLED = Connection.rolled();

enum double WELL = 4.5;
enum double STAIR_OUT = 8.5;
enum double SHELF = 10.5;
enum double RIM = 12;
enum double EVERYWHERE = 100;
enum double ROUTE_RADIUS = 6.5;
enum int TOP_TREAD = STORY;
enum int ROUTE_TREADS = 20 * TURN_TREADS;
enum int LAMP_SPOT = 6;
immutable float[3] SPAWN = [10, 7, 1];

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

struct Quarter {
    Turtle corner;
    Turtle tower;
    const(Risen)* risen;

    bool isClear() const {
        return blocks.isRisingFrom(corner) || (risen.edges > 0 && blocks.isFoot(corner, *risen));
    }
}

Kind kindOf(ulong face) {
    double chance = roll(face, KIND_SALT);
    if (chance < HALL_ODDS) {
        return Kind.hall;
    } else if (chance < HALL_ODDS + STAIR_ODDS) {
        return Kind.stair;
    } else {
        return Kind.gallery;
    }
}

Wall wallOf(ulong edge) {
    double chance = roll(edge, WALL_SALT);
    if (chance < ARCADE_ODDS) {
        return Wall.arcade;
    } else if (chance < ARCADE_ODDS + SOLID_ODDS) {
        return Wall.solid;
    } else {
        return Wall.door;
    }
}

void spread(ref const Quarter q, Material material, int[2] z, Rhythm rhythm) {
    int far = q.tower.column().high;
    if (!q.isClear()) {
        q.tower.paint(material, boxOf([0, far], [0, far], z), rhythm);
    } else {
        if (z[0] <= 0) {
            q.tower.paint(material, boxOf([0, far], [0, far], [z[0], lowerOf(z[1], 0)]), rhythm);
        }
        if (z[1] > 0) {
            int[2] open = [higherOf(z[0], 1), z[1]];
            q.tower.paint(material, boxOf([CLEAR, far], [0, far], open), rhythm);
            q.tower.paint(material, boxOf([0, CLEAR - 1], [CLEAR, far], open), rhythm);
        }
    }
}

void shelves(Turtle tower, Along direction, int[2] span) {
    int[2] rooms = [BOTTOM + 1, ROOF - 1];
    tower.paint(FRAME, line(direction, span, rooms));
    foreach (along; span[0] .. span[1] + 1) {
        foreach (row; WALL_BOOKS) {
            tower.paint(BOOKS[tower.pick(BOOKS.length)], line(direction, [along, along], rooms), row);
        }
    }
}

void wall(Turtle tower, Along direction, ulong edge) {
    int far = tower.column().high;
    final switch (wallOf(edge)) {
        case Wall.door:
            shelves(tower, direction, [0, far - DOOR]);
            break;
        case Wall.arcade:
            shelves(tower, direction, [0, PIER - 1]);
            break;
        case Wall.solid:
            shelves(tower, direction, [0, far]);
            break;
    }
}

void stack(Turtle tower, int[2] x, int[2] y) {
    int[2] rooms = [BOTTOM + 1, ROOF - 1];
    tower.paint(FRAME, boxOf(x, y, rooms), Rhythm(STORY, 1, 3));
    tower.paint(BOOKS[tower.pick(BOOKS.length)], boxOf(x, y, rooms), Rhythm(STORY, 2, 1));
}

void floors(ref const Quarter q, Kind kind, Material material) {
    int[2] whole = [BOTTOM, ROOF];
    int story = STORY;
    if (kind == Kind.hall) {
        story = HALL_STORY;
    }
    spread(q, Material.none, [BOTTOM + 1, ROOF - 1], Rhythm.init);
    spread(q, material, whole, Rhythm(story, 0, 1));
    spread(q, CEILING, whole, Rhythm(story, story - 1, 1));
    q.tower.paint(Material.lightPanel, boxOf([LAMP[0], LAMP[0]], [LAMP[1], LAMP[1]], whole), Rhythm(story, story - 1, 1));
    if (kind == Kind.hall) {
        q.tower.paint(Material.oakWood, boxOf(TABLE_X, TABLE_Y, whole), Rhythm(HALL_STORY, 1, 1));
    }
}

void tread(Turtle tower, int x, int[2] y, int top) {
    tower.paint(Material.marble, boxOf([x, x], y, [top - 1, top]));
}

void stairwell(Turtle tower) {
    int[2] low = [1, 3];
    int[2] high = [5, 7];
    foreach (flight; LOWEST_FLIGHT .. HIGHEST_FLIGHT + 1) {
        int level = flight * STORY + 1;
        tower.paint(Material.none, boxOf([3, 8], [1, 7], [level + STORY - 2, level + STORY - 1]));
        foreach (step; 0 .. 2) {
            tread(tower, 3 + step, low, level + step);
        }
        tower.paint(Material.marble, boxOf([5, 8], [1, 7], [level + 1, level + 2]));
        foreach (step; 0 .. 3) {
            tread(tower, 4 - step, high, level + 3 + step);
        }
    }
}

void quarter(Turtle corner, size_t index, Kind kind, Material material, ref const Risen risen) {
    uint rising = corner.rising();
    if (rising != Tag.stacks) {
        Quarter q = Quarter(corner, upright(corner), &risen);
        floors(q, kind, material);
        if (!q.isClear()) {
            wall(q.tower, Along.x, corner.hash(SitePart.edge));
            wall(q.tower, Along.y, corner.right().hash(SitePart.edge));
        }
        if (kind == Kind.stair && index == 0 && !q.isClear()) {
            stairwell(q.tower);
        } else if (kind == Kind.gallery) {
            stack(q.tower, [3, 7], [CLEAR, CLEAR + 1]);
            if (q.tower.pick(2) == 0) {
                stack(q.tower, [3, 7], [CLEAR + 3, CLEAR + 4]);
            }
        }
    }
}

void tile(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    Turtle face = Turtle(api, site);
    Connection connection = *cast(const(Connection)*) data;
    ulong hash = face.hash(SitePart.face);
    Kind kind = kindOf(hash);
    Material material = FLOORS[cast(size_t)(roll(hash, FLOOR_SALT) * FLOORS.length)];
    foreach (index, corner; cornersOf(face)) {
        quarter(corner, index, kind, material, *risen);
    }
    if (risen.edges > 0 && blocks.ownsFoot(face, *risen)) {
        connect(Turtle(api, risen.foot), *risen, Tag.library, connection);
    }
}

void stories(Turtle tower, double outer, int[2] z, Material floor) {
    Rows ring = ringRows(tower.column(), WELL, outer);
    Rows well = ringRows(tower.column(), 0, WELL);
    tower.paintRows(Material.none, ring, z);
    tower.paintRows(Material.none, well, z);
    tower.paintRows(floor, ring, z, Rhythm(STORY, 0, 1));
    tower.paintRows(Material.glass, well, z, Rhythm(STORY, 0, 1));
    tower.paintRows(CEILING, ring, z, Rhythm(STORY, CEILING_AT, 1));
    immutable int[2] sides = [-LAMP_SPOT, LAMP_SPOT - 1];
    foreach (x; sides) {
        foreach (y; sides) {
            tower.paint(Material.lightPanel, boxOf([x, x], [y, y], z), Rhythm(STORY, CEILING_AT, 1));
        }
    }
}

void shelving(Turtle tower, int[2] z) {
    Rows wall = ringRows(tower.column(), SHELF, RIM);
    tower.paintRows(FRAME, wall, z);
    foreach (row; wall.slice()) {
        tower.paint(BOOKS[tower.pick(BOOKS.length)], boxOf(row.x, [row.y, row.y], z), Rhythm(STORY, 2, 2));
    }
}

void descent(Turtle tower, int lastTread) {
    Rows[TURN_TREADS] treads = wedgeRows(tower.column(), WELL, STAIR_OUT);
    foreach (at; -STAIR_HEADROOM .. lastTread + 1) {
        Rows* wedge = &treads[floorMod(at, TURN_TREADS)];
        tower.clearOver(*wedge, at);
        if (at >= 0) {
            tower.paintRows(Material.marble, *wedge, treadSpan(at));
        }
    }
}

void shaft(const(Api)* api, Site base, const(Risen)* risen, const(void)* data) {
    Turtle tower = Turtle(api, base);
    int length = tower.edgeCells();
    int bottom = risen.segment * length;
    int top = lowerOf(ROOF, bottom + length - 1);
    Material floor = FLOORS[cast(size_t)(roll(Turtle(api, risen.foot).hash(SitePart.vertex), FLOOR_SALT) * FLOORS.length)];
    int[2] deep = [bottom, lowerOf(BOTTOM - 1, top)];
    int[2] slab = [higherOf(BOTTOM, bottom), top];
    if (deep[0] <= deep[1]) {
        int[2] z = [deep[0] - bottom, deep[1] - bottom];
        stories(tower, SHELF, z, floor);
        shelving(tower, z);
    }
    if (slab[0] <= slab[1]) {
        stories(tower, EVERYWHERE, [slab[0] - bottom, slab[1] - bottom], floor);
    }
    int lastTread = TURN_TREADS - 1;
    if (risen.segment == 0) {
        lastTread = TOP_TREAD;
        Rows cap = ringRows(tower.column(), 0, WELL);
        tower.paintRows(CEILING, cap, [ROOF, ROOF]);
    }
    descent(tower, lastTread);
}

void route(Turtle tower) {
    foreach (index; 0 .. ROUTE_TREADS + 1) {
        int segment = floorDiv(-index, TURN_TREADS);
        float[2] at = onWedge(-index, ROUTE_RADIUS);
        tower.forward(segment).stop(at[0], at[1], 1 - index - segment * TURN_TREADS);
    }
}

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    Connection connection = Connection.rolled();
    uint kind = api.horosphere(api, RISE_ODDS, HorosphereForm.solid, Tag.library, &tile, &connection, Connection.sizeof);
    api.rooted(api, kind);
    api.look(api, kind, &LOOK);
    uint stacks = api.sunken(api, SHAFT_ODDS, Tag.library, Tag.stacks, &shaft, null, 0);
    api.openHorosphere(api, site, stacks, 2);
    api.fog(api, FOG);
    Turtle tower = at.columnSite();
    route(tower);
    tower.entrance(SPAWN[0], SPAWN[1], SPAWN[2]);
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "library", &world);
    RisingKind rising = RisingKind(1, HorosphereForm.solid, Tag.library, &tile, &ROLLED, Connection.sizeof, LOOK);
    registry.addKind(registry, "library", &rising);
    RisingKind stacks = RisingKind(SHAFT_SHARE, HorosphereForm.sunken, Tag.stacks, &shaft, null, 0, LOOK, Tag.library);
    registry.addKind(registry, "librarystacks", &stacks);
}
