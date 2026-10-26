module plugins.library.plugin;

import plugins.api.api : Api, Box, ENTRY, HorosphereForm, Material, Registry, Rhythm, Risen, Site, SitePart;
import blocks = plugins.blocks.blocks;
import plugins.connector.connector : connect, slabFloor;
import plugins.turtle.turtle : Turtle, boxOf, cornersOf, roll, upright;

enum int STORY = 6;
enum int HALL_STORY = 2 * STORY;
enum int BOTTOM = -12;
enum int ROOF = 11;
enum int LOWEST_FLIGHT = -2;
enum int HIGHEST_FLIGHT = 0;
enum int PIER = 3;
enum int SHAFT = 8;
enum int CLEAR = 6;
enum int[2] LAMP = [10, 4];
enum int[2] TABLE_X = [3, 8];
enum int[2] TABLE_Y = [5, 6];
enum double RISE_ODDS = 0.03;
enum uint TAG = 0;
enum double WELL_ODDS = 0.15;
enum double HALL_ODDS = 0.15;
enum double STAIR_ODDS = 0.15;
enum double OPEN_ODDS = 0.4;
enum double ARCADE_ODDS = 0.4;
enum ulong KIND_SALT = 0x3B9ACA07;
enum ulong FLOOR_SALT = 0x7F4A7C15;
enum ulong WALL_SALT = 0x1B873593;
enum Material FRAME = Material.spruceWood;
enum Material CEILING = Material.plaster;
enum double FOG = 6;
enum int OPEN = 1;
enum float ROUTE_LANE_LOW = 2.5f;
enum float ROUTE_LANE_HIGH = 6.5f;
immutable float[3] SPAWN = [32, 10, 1];
immutable Material[4] FLOORS = [Material.woodPlanks, Material.spruceWood, Material.marble, Material.redCarpet];
immutable Material[7] BOOKS = [Material.redCarpet, Material.acaciaWood, Material.jungleWood, Material.birchWood, Material.oakWood, Material.carpet, Material.redSandstone];
immutable Rhythm[2] WALL_BOOKS = [Rhythm(2 * STORY, 2, 2), Rhythm(2 * STORY, STORY + 2, 2)];

enum Kind : ubyte {
    gallery,
    well,
    hall,
    stair,
}

enum Wall : ubyte {
    open,
    arcade,
    shelves,
}

struct Root {
    ulong face;
}

struct Quarter {
    Turtle tower;
    bool isClear;
}

Kind kindOf(ulong face, ref const Root root) {
    double chance = roll(face, KIND_SALT);
    if (face == root.face) {
        return Kind.stair;
    } else if (chance < WELL_ODDS) {
        return Kind.well;
    } else if (chance < WELL_ODDS + HALL_ODDS) {
        return Kind.hall;
    } else if (chance < WELL_ODDS + HALL_ODDS + STAIR_ODDS) {
        return Kind.stair;
    } else {
        return Kind.gallery;
    }
}

Wall wallOf(ulong edge) {
    double chance = roll(edge, WALL_SALT);
    if (chance < OPEN_ODDS) {
        return Wall.open;
    } else if (chance < OPEN_ODDS + ARCADE_ODDS) {
        return Wall.arcade;
    } else {
        return Wall.shelves;
    }
}

Box line(bool isAlongX, int[2] span, int[2] z) {
    if (isAlongX) {
        return boxOf(span, [0, 0], z);
    } else {
        return boxOf([0, 0], span, z);
    }
}

void spread(ref const Quarter q, Material material, int[2] z, Rhythm rhythm) {
    int far = q.tower.column().high;
    if (q.isClear) {
        q.tower.paint(material, boxOf([CLEAR, far], [0, far], z), rhythm);
        q.tower.paint(material, boxOf([0, CLEAR - 1], [CLEAR, far], z), rhythm);
    } else {
        q.tower.paint(material, boxOf([0, far], [0, far], z), rhythm);
    }
}

void shelves(Turtle tower, bool isAlongX, int[2] span) {
    int[2] rooms = [BOTTOM + 1, ROOF - 1];
    tower.paint(FRAME, line(isAlongX, span, rooms));
    foreach (along; span[0] .. span[1] + 1) {
        foreach (row; WALL_BOOKS) {
            tower.paint(BOOKS[tower.pick(BOOKS.length)], line(isAlongX, [along, along], rooms), row);
        }
    }
}

void wall(Turtle tower, bool isAlongX, ulong edge) {
    final switch (wallOf(edge)) {
        case Wall.open:
            break;
        case Wall.arcade:
            shelves(tower, isAlongX, [0, PIER - 1]);
            break;
        case Wall.shelves:
            shelves(tower, isAlongX, [0, tower.column().high]);
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

void well(Turtle tower) {
    int[2] shaft = [SHAFT, tower.column().high];
    tower.paint(Material.none, boxOf(shaft, shaft, [BOTTOM + 1, ROOF - 1]));
    tower.paint(Material.glass, boxOf(shaft, shaft, [ROOF, ROOF]));
    tower.paint(Material.sunlight, boxOf(shaft, shaft, [BOTTOM, BOTTOM]));
}

void tread(Turtle tower, int x, int[2] y, int top) {
    tower.paint(Material.marble, boxOf([x, x], y, [top - 1, top]));
}

void stairwell(Turtle tower, bool isRouted) {
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
        if (isRouted) {
            tower.stop(2.5f, ROUTE_LANE_LOW, level);
            foreach (step; 0 .. 2) {
                tower.stop(3.5f + step, ROUTE_LANE_LOW, level + step + 1);
            }
            tower.stop(6.5f, ROUTE_LANE_LOW, level + 3);
            tower.stop(6.5f, ROUTE_LANE_HIGH, level + 3);
            foreach (step; 0 .. 3) {
                tower.stop(4.5f - step, ROUTE_LANE_HIGH, level + 4 + step);
            }
            tower.stop(1.5f, ROUTE_LANE_HIGH, level + STORY);
            tower.stop(1.5f, ROUTE_LANE_LOW, level + STORY);
        }
    }
}

void quarter(Turtle corner, size_t index, Kind kind, Material material, bool isRoot, ref const Risen risen) {
    bool isClear = blocks.isRisingFrom(corner) || (risen.edges > 0 && blocks.isFoot(corner, risen));
    Quarter q = Quarter(upright(corner), isClear);
    floors(q, kind, material);
    if (!isClear) {
        wall(q.tower, true, corner.hash(SitePart.edge));
        wall(q.tower, false, corner.right().hash(SitePart.edge));
    }
    if (kind == Kind.well) {
        well(q.tower);
    }
    if (kind == Kind.stair && index == 0 && !isClear) {
        stairwell(q.tower, isRoot);
    } else if (kind == Kind.gallery || kind == Kind.well) {
        stack(q.tower, [3, 7], [CLEAR, CLEAR + 1]);
        if (kind == Kind.gallery && q.tower.pick(2) == 0) {
            stack(q.tower, [3, 7], [CLEAR + 3, CLEAR + 4]);
        }
    }
}

void tile(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    Turtle face = Turtle(api, site);
    Root root = *cast(const(Root)*) data;
    ulong hash = face.hash(SitePart.face);
    Kind kind = kindOf(hash, root);
    Material material = FLOORS[cast(size_t)(roll(hash, FLOOR_SALT) * FLOORS.length)];
    foreach (index, corner; cornersOf(face)) {
        quarter(corner, index, kind, material, hash == root.face && risen.edges == 0, *risen);
    }
    if (risen.edges > 0 && blocks.ownsFoot(face, *risen)) {
        connect(Turtle(api, risen.foot), *risen, slabFloor(OPEN), slabFloor(OPEN), false);
    }
}

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    Root root = Root(at.hash(SitePart.face));
    uint kind = api.horosphere(api, RISE_ODDS, HorosphereForm.bare, TAG, &tile, &root, Root.sizeof);
    api.rooted(api, kind);
    api.fog(api, FOG);
    upright(at).entrance(SPAWN[0], SPAWN[1], SPAWN[2]);
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "library", &world);
}
