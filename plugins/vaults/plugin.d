module plugins.vaults.plugin;

import core.stdc.math : cos, fabs, floor, pow, sqrt;
import plugins.api.api : Api, HorosphereForm, KindId, Material, Registry, Risen, Site, SitePart, Span, entryOf, tagNamed;
import plugins.api.binding : List, bound, settingsOf;
import plugins.api.content : Content, FIRST_VERSION, Manifest, ON_BASE;
import plugins.carve.carve : Choice, Slab, Vec, Way, along, emit, unitOf;
import plugins.turtle.turtle : FACE_CORNERS, PI, Turtle, cornersOf, upright;

enum string LOOK = "vaults:look";

enum uint VAULT_TAG = tagNamed("vaults:vaults");
enum int QUARTER = 12;
enum int FLOOR = -1;
enum int TOP = 21;
enum double CENTER = 12;
enum double WALL = 2;
enum double BAND = 4;
enum double INNER_WALL = 1;
enum double CLOSED_AT = 8.5;
enum double RING_WIDTH = 2;
enum double RINGED = 9;
enum double SPOKE = 0.5;
enum double LAMP = 0.7;
enum double ARCADE_BELOW_GALLERY = 2;
enum double FINIAL_ABOVE_GALLERY = 3;
enum double LEAST_GALLERY = 9;
enum double GALLERY_SPREAD = 2;
enum double VAULT_ABOVE_GALLERY = 4;
enum double WALL_SPREAD = 2;
enum double LOW_TIER = 2;
enum double HIGH_TIER = 3;
enum double ROOMY_TIERS = 6;
enum uint MOST_TIERS = 5;
enum uint LEAST_TIERS = 2;
immutable double[4] PERIODS = [3, 4, 5, 6];
enum double DOOR_HALF = 2.5;
enum double DOOR_HEIGHT = 4.5;
enum double ARCADE_HALF = 4.5;
enum double NICHE_PERIOD = 6;
enum double NICHE_HALF = 1.4;
enum double NICHE_HEIGHT = 4;
enum int STAIR_START = 4;
enum double SPIRE_RADIUS = 4.2;
enum double SPIRE_PLINTH = 1.4;
enum double SPIRE_TAPER = 0.72;
enum double SPIRE_CURVE = 1.5;
enum double SPIRE_TIER = 2;
enum double RIB = 0.85;
enum double RIB_OUT = 0.8;
enum double AMALAKA = 2.3;
enum double FINIAL = 0.9;
enum double STRETCH = 2.5;
enum ulong GALLERY_SALT = 0x47414C4C;
enum ulong WALL_SALT = 0x57414C4C;
enum ulong TIER_SALT = 0x54494552;
enum ulong PERIOD_SALT = 0x50455249;
enum ulong PALETTE_SALT = 0x50414C45;
enum ulong SPIRE_SALT = 0x53504952;
enum ulong DOOR_SALT = 0x444F4F52;
enum size_t MOST_PALETTES = 16;

struct Palette {
    Material floor;
    Material inlay;
    Material wall;
    Material vault;
    Material rib;
    Material accent;
}

struct Materials {
    Material lamp;
    List!(Palette, MOST_PALETTES) palettes;
}

__gshared Materials materials;

struct Tuning {
    double fog;
    double doorOdds;
    double arcadeOdds;
    double spireOdds;
}

__gshared Tuning tuning;

void resolve(const(Content)* content) {
    materials = content.bound!Materials("vaults:materials");
    tuning = content.settingsOf!Tuning("vaults");
}

enum Wall : ubyte {
    door,
    arcade,
    closed,
}

enum Spire : ubyte {
    none,
    shikhara,
}

struct Room {
    Palette palette;
    Wall[FACE_CORNERS] walls;
    double gallery = 0;
    double wallTop = 0;
    double tier = 0;
    double step = 0;
    double period = 0;
    uint tiers;
    Spire spire;
}

struct Place {
    double along = 0;
    double wall = 0;
    double rise = 0;
    double radius = 0;
    double u = 0;
    double v = 0;
    int level;
    uint edge;
    int stair;
}

double drifted(ref const ulong[FACE_CORNERS] corners, ulong salt) {
    double total = 0;
    foreach (hash; corners) {
        total += unitOf(hash, salt);
    }
    double share = 0.5 + (total / FACE_CORNERS - 0.5) * STRETCH;
    if (share < 0) {
        return 0;
    } else if (share > 1) {
        return 1;
    } else {
        return share;
    }
}

uint pickOf(double share, size_t count) {
    uint index = cast(uint)(share * count);
    if (index >= count) {
        return cast(uint) count - 1;
    } else {
        return index;
    }
}

Wall wallOf(ulong edge) {
    double roll = unitOf(edge, DOOR_SALT);
    if (roll < tuning.doorOdds) {
        return Wall.door;
    } else if (roll < tuning.arcadeOdds) {
        return Wall.arcade;
    } else {
        return Wall.closed;
    }
}

Room roomOf(ref const Turtle[FACE_CORNERS] corners) {
    ulong[FACE_CORNERS] hashes;
    Room room;
    foreach (index, corner; corners) {
        hashes[index] = corner.probeHash(SitePart.vertex);
        room.walls[index] = wallOf(along(upright(corner), Way.xPlus).probeHash(SitePart.edge));
    }
    room.walls[0] = Wall.closed;
    room.gallery = LEAST_GALLERY + floor(GALLERY_SPREAD * drifted(hashes, GALLERY_SALT) + 0.5);
    room.wallTop = room.gallery + VAULT_ABOVE_GALLERY + floor(WALL_SPREAD * drifted(hashes, WALL_SALT) + 0.5);
    double headroom = TOP + 1 - room.wallTop;
    room.tier = LOW_TIER;
    if (headroom >= ROOMY_TIERS &&drifted(hashes, TIER_SALT) > 0.5) {
        room.tier = HIGH_TIER;
    }
    uint tiers = cast(uint) floor(headroom / room.tier);
    if (tiers > MOST_TIERS) {
        tiers = MOST_TIERS;
    }
    assert(tiers >= LEAST_TIERS);
    room.tiers = tiers;
    room.step = (CLOSED_AT - WALL) / tiers;
    room.period = PERIODS[pickOf(drifted(hashes, PERIOD_SALT), PERIODS.length)];
    room.palette = materials.palettes.items[pickOf(drifted(hashes, PALETTE_SALT), materials.palettes.count)];
    if (drifted(hashes, SPIRE_SALT) > tuning.spireOdds) {
        room.spire = Spire.shikhara;
    }
    return room;
}

Place placeOf(uint quarter, Vec cell) {
    Place place;
    place.rise = cell.z;
    place.level = cast(int) floor(cell.z);
    place.u = CENTER - cell.x;
    place.v = CENTER - cell.y;
    place.radius = sqrt(place.u * place.u + place.v * place.v);
    if (cell.x <= cell.y) {
        place.wall = cell.x;
        place.along = cell.y;
        place.edge = (quarter + FACE_CORNERS - 1) % FACE_CORNERS;
    } else {
        place.wall = cell.y;
        place.along = cell.x;
        place.edge = quarter;
    }
    place.stair = -1;
    if (quarter == 0 && cell.y >= WALL && cell.y < BAND && cell.x >= WALL) {
        place.stair = cast(int) floor(cell.x);
    } else if (quarter == 1 && cell.x >= WALL && cell.x < BAND && cell.y >= WALL) {
        place.stair = 2 * QUARTER - 1 - cast(int) floor(cell.y);
    }
    return place;
}

double archOver(double half, double offset) {
    double squared = half * half - offset * offset;
    if (squared > 0) {
        return sqrt(squared);
    } else {
        return 0;
    }
}

bool isOpening(ref const Room room, ref const Place place) {
    double offset = CENTER - place.along;
    final switch (room.walls[place.edge]) {
        case Wall.door:
            return offset < DOOR_HALF && place.rise < DOOR_HEIGHT + archOver(DOOR_HALF, offset);
        case Wall.arcade:
            double springing = room.gallery - ARCADE_BELOW_GALLERY - ARCADE_HALF;
            return offset < ARCADE_HALF && place.rise < springing + archOver(ARCADE_HALF, offset);
        case Wall.closed:
            return false;
    }
}

bool isNiche(ref const Room room, ref const Place place) {
    double reach = CENTER - DOOR_HALF - 1;
    if (room.walls[place.edge] == Wall.arcade) {
        reach = CENTER - ARCADE_HALF - 1;
    } else if (room.walls[place.edge] == Wall.closed) {
        reach = CENTER;
    }
    double index = floor(place.along / NICHE_PERIOD);
    double center = (index + 0.5) * NICHE_PERIOD;
    double offset = fabs(place.along - center);
    return center + NICHE_HALF < reach && offset < NICHE_HALF && place.rise < NICHE_HEIGHT + archOver(NICHE_HALF, offset);
}

double nicheDepth(ref const Room room, ref const Place place, uint tier) {
    double shift = (tier % 2) * room.period / 2;
    double cycle = place.along + shift;
    double local = cycle - floor(cycle / room.period) * room.period - room.period / 2;
    double across = 1 - (local / (room.period / 2)) * (local / (room.period / 2));
    double share = (place.rise - room.wallTop - tier * room.tier) / room.tier;
    if (across <= 0) {
        return 0;
    } else {
        return room.step * sqrt(across) * cos(PI / 2 * share);
    }
}

double nicheCenter(ref const Room room, ref const Place place, uint tier) {
    double shift = (tier % 2) * room.period / 2;
    double cycle = place.along + shift;
    return fabs(cycle - floor(cycle / room.period) * room.period - room.period / 2);
}

bool isVaultSolid(ref const Room room, ref const Place place) {
    double above = place.rise - room.wallTop;
    uint tier = cast(uint) floor(above / room.tier);
    return tier < room.tiers && place.wall < WALL + (tier + 1) * room.step - nicheDepth(room, place, tier);
}

double spireRadius(ref const Room room, ref const Place place) {
    double top = room.gallery + 1;
    double stepped = floor(place.rise / SPIRE_TIER) * SPIRE_TIER;
    double rib = 0;
    if (place.u < RIB || place.v < RIB || fabs(place.u - place.v) < RIB) {
        rib = RIB_OUT;
    }
    if (place.level == 0) {
        return SPIRE_RADIUS + SPIRE_PLINTH;
    } else if (place.rise < top) {
        return SPIRE_RADIUS * (1 - SPIRE_TAPER * pow(stepped / top, SPIRE_CURVE)) + rib;
    } else if (place.rise < top + 1) {
        return AMALAKA + rib;
    } else if (place.rise < top + 3) {
        return FINIAL;
    } else {
        return 0;
    }
}

Choice floorChoice(ref const Room room, ref const Place place) {
    Palette palette = room.palette;
    uint ring = cast(uint) floor(place.radius / RING_WIDTH);
    if (place.wall < BAND) {
        return Choice.of(palette.inlay);
    } else if (fabs(place.u - place.v) < SPOKE || place.u < SPOKE || place.v < SPOKE) {
        return Choice.of(palette.inlay);
    } else if (ring % 2 == 1 && place.radius < RINGED) {
        return Choice.of(palette.inlay);
    } else {
        return Choice.of(palette.floor);
    }
}

Choice cellChoice(ref const Room room, uint quarter, Vec cell) {
    Place place = placeOf(quarter, cell);
    Palette palette = room.palette;
    double gallery = room.gallery;
    if (place.level == FLOOR) {
        return floorChoice(room, place);
    } else if (place.stair >= STAIR_START && place.stair < STAIR_START + gallery - 1 && place.level < cast(int) gallery) {
        if (place.level < place.stair - STAIR_START + 1) {
            return Choice.of(palette.inlay);
        } else {
            return Choice.keep();
        }
    } else if (room.spire == Spire.shikhara && place.radius < spireRadius(room, place)) {
        if (place.rise >= gallery + FINIAL_ABOVE_GALLERY) {
            return Choice.of(materials.lamp);
        } else {
            return Choice.of(palette.accent);
        }
    } else if (place.rise >= room.wallTop) {
        if (isVaultSolid(room, place)) {
            Place below = place;
            below.rise -= 1;
            uint tier = cast(uint) floor((place.rise - room.wallTop) / room.tier);
            if (tier % 2 == 1 && !isVaultSolid(room, below) && nicheCenter(room, place, tier) < LAMP) {
                return Choice.of(materials.lamp);
            } else if (tier % 2 == 1) {
                return Choice.of(palette.rib);
            } else {
                return Choice.of(palette.vault);
            }
        } else {
            return Choice.keep();
        }
    } else if (place.wall < WALL) {
        if (isOpening(room, place)) {
            return Choice.keep();
        } else if (place.wall >= INNER_WALL && isNiche(room, place)) {
            return Choice.keep();
        } else if (place.level == 0 || place.level == cast(int) gallery - 1) {
            return Choice.of(palette.inlay);
        } else {
            return Choice.of(palette.wall);
        }
    } else if (place.wall < BAND && place.level == cast(int) gallery - 1) {
        return Choice.of(palette.inlay);
    } else {
        return Choice.keep();
    }
}

void hall(const(Api)* api, Site face, const(Risen)* risen, const(void)* data) {
    Turtle[FACE_CORNERS] corners = cornersOf(Turtle(api, face));
    Room made = roomOf(corners);
    foreach (index, corner; corners) {
        uint quarter = cast(uint) index;
        Choice choose(Vec cell) {
            return cellChoice(made, quarter, cell);
        }
        emit!choose(Slab(upright(corner), Span(0, QUARTER - 1), Span(0, QUARTER - 1), Span(FLOOR, TOP)));
    }
}

void route(ref const Turtle[FACE_CORNERS] corners, ref const Room made) {
    Turtle first = upright(corners[0]);
    Turtle second = upright(corners[1]);
    int last = STAIR_START + cast(int) made.gallery - 2;
    first.stop(STAIR_START - 1.5f, BAND - 1, 0);
    foreach (tread; STAIR_START .. last + 1) {
        float top = tread - STAIR_START + 1;
        if (tread < QUARTER) {
            first.stop(tread + 0.5f, BAND - 1, top);
        } else {
            second.stop(BAND - 1, 2 * QUARTER - 1 - tread + 0.5f, top);
        }
    }
    float gallery = cast(float) made.gallery;
    immutable float[3] back = [5.5f, 3.5f, 3];
    second.stop(BAND - 1, 2 * QUARTER - 1 - last - 0.5f, gallery);
    foreach (spot; back) {
        second.stop(BAND - 1, spot, gallery);
    }
    immutable float[3] onward = [5.5f, 8.5f, 11];
    foreach (spot; onward) {
        second.stop(spot, BAND - 1, gallery);
    }
}

void world(const(Api)* api, Site site, const(void)* data) {
    KindId kind = api.horosphere(api, 0, HorosphereForm.solid, VAULT_TAG, &hall, null, 0);
    api.rooted(api, kind);
    api.look(api, kind, LOOK);
    api.worldLook(api, LOOK);
    api.fog(api, tuning.fog);
    Turtle[FACE_CORNERS] corners = cornersOf(Turtle(api, site));
    Room made = roomOf(corners);
    route(corners, made);
    upright(corners[0]).entrance(QUARTER + 15.5f, CENTER - 3, 0);
}

immutable Manifest MANIFEST = Manifest("vaults", FIRST_VERSION, ON_BASE[], null, &resolve, null, import("plugins/vaults/settings.conf"), import("plugins/vaults/vaults.decl"), import("plugins/vaults/vaults.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.add(registry, "vaults", &world);
}
