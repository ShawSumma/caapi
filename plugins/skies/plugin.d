module plugins.skies.plugin;

import plugins.api.api : Api, Box, HorosphereForm, KindId, Material, Registry, Risen, RisingKind, Site, SitePart, Span, Spot, entryOf, tagNamed;
import plugins.api.binding : List, bound, settingsOf;
import plugins.api.content : BASE, Content, Dependency, FIRST_VERSION, Manifest, dependencyOn;
import blocks = plugins.blocks.blocks;
import plugins.connector.connector : Connection, connect, resolveConnector;
import plugins.turtle.turtle : Along, Turtle, boxOf, cornersOf, line, mixed, roll, strongestAround, upright;

enum uint TERRACES_TAG = tagNamed("skies:terraces");
enum uint GARDEN_TAG = tagNamed("skies:garden");
enum uint TRELLIS_TAG = tagNamed("skies:trellis");
enum string TERRACES_LOOK = "skies:terraces";
enum string GARDEN_LOOK = "skies:garden";
enum string TRELLIS_LOOK = "skies:trellis";
enum double RISING_SHARE = 0;
enum int FLOOR = -1;
enum int LEAST_STEPS = 3;
enum uint STEP_CHOICES = 6;
enum int LEAST_BEACON = 3;
enum uint BEACON_CHOICES = 9;
enum uint SIZE_CHOICES = 8;
enum int MONOLITH = 7;
enum Span MONOLITH_X = Span(5, 6);
enum Span MONOLITH_Y = Span(3, 8);
enum int ARCH = 4;
enum Span ARCH_Y = Span(5, 6);
enum Span ARCH_SPAN = Span(3, 9);
immutable Span[2] ARCH_POSTS = [Span(3, 4), Span(8, 9)];
enum int CUBE_AT = 4;
enum int LEAST_CUBE = 2;
enum uint CUBE_CHOICES = 3;
enum int CUBE_LIFT = 3;
enum int FLIGHT_START = 2;
enum int LEAST_FLIGHT = 4;
enum uint FLIGHT_CHOICES = 5;
enum Span FLIGHT_WIDTH = Span(4, 7);
immutable int[2] PILLAR_SPOTS = [3, 8];
enum int LEAST_PILLAR = 2;
enum uint PILLAR_CHOICES = 10;
enum Span SPIRE_BASE = Span(3, 8);
enum Span SPIRE_SHAFT = Span(4, 7);
enum Span SPIRE_TIP = Span(5, 6);
enum int SPIRE_PLINTH = 2;
enum int SPIRE_RISE = 3;
enum int DECK = 8;
enum int STAIR_START = 2;
enum ulong PALETTE_SALT = 0x50414C45;
enum ulong SHAPE_SALT = 0x53484150;
enum ulong STEPS_SALT = 0x53544550;
enum ulong BEACON_SALT = 0x42454143;
enum ulong FORM_SALT = 0x464F524D;
enum ulong SIZE_SALT = 0x53495A45;
enum ulong PILLAR_SALT = 0x50494C4C;
enum ulong PLANK_SALT = 0x504C414E;
enum ulong DECK_SALT = 0x4445434B;
enum ulong STAIR_SALT = 0x53544149;
enum ulong LANTERN_SALT = 0x4C414E54;
enum size_t MOST_PALETTES = 8;
immutable Spot SPAWN = Spot(27.5f, 6, 0);

struct Palette {
    Material floor;
    Material step;
    Material accent;
    Material light;
}

struct Materials {
    List!(Palette, MOST_PALETTES) terraces;
    List!(Palette, MOST_PALETTES) garden;
    List!(Palette, MOST_PALETTES) trellis;
}

__gshared Materials materials;

struct Tuning {
    double fog;
    double plazaShare;
    double pitShare;
    double beaconOdds;
    double formShare;
    double plankShare;
    double deckShare;
    double stairOdds;
    double lanternOdds;
}

__gshared Tuning tuning;

void resolve(const(Content)* content) {
    resolveConnector(content);
    materials = content.bound!Materials("skies:materials");
    tuning = content.settingsOf!Tuning("skies");
}

struct Root {
    Connection how;
    ulong plain;
}

immutable Root RISING = Root(Connection.rolled(), 0);

enum Terrace : ubyte {
    plaza,
    pit,
    ziggurat,
}

enum Form : ubyte {
    monolith,
    arch,
    cube,
    flight,
    pillars,
    spire,
}

enum uint FORM_COUNT = Form.max + 1;

Palette paletteOf(ref const List!(Palette, MOST_PALETTES) palettes, Turtle face) {
    return palettes.items[mixed(strongestAround(face), PALETTE_SALT) % palettes.count];
}

Box bay(int low, int far, Span z) {
    return boxOf(Span(low, far), Span(low, far), z);
}

Span level(int z) {
    return Span(z, z);
}

bool probeOpen(Turtle face, ref const Risen risen) {
    foreach (corner; cornersOf(face)) {
        bool taken = blocks.probeTaken(corner, risen);
        if (taken) {
            return false;
        }
    }
    return true;
}

void foot(const(Api)* api, Turtle face, const(Risen)* risen, uint tag, ref const Root root) {
    if (risen.hasRisen) {
        bool owner = blocks.probeOwnsFoot(face, *risen);
        if (owner) {
            connect(Turtle(api, risen.foot), *risen, tag, root.how);
        }
    }
}

Material banded(Palette palette, int step) {
    if (step % 2 == 0) {
        return palette.floor;
    } else {
        return palette.step;
    }
}

Terrace terraceOf(Turtle face, ulong hash, ref const Risen risen, ref const Root root) {
    double chance = roll(hash, SHAPE_SALT);
    if (hash == root.plain || chance < tuning.plazaShare) {
        return Terrace.plaza;
    } else {
        bool open = probeOpen(face, risen);
        if (!open) {
            return Terrace.plaza;
        } else if (chance < tuning.plazaShare + tuning.pitShare) {
            return Terrace.pit;
        } else {
            return Terrace.ziggurat;
        }
    }
}

void ziggurat(Turtle quarter, Palette palette, int steps, int beacon) {
    int far = quarter.column().high;
    foreach (step; 1 .. steps + 1) {
        quarter.paint(banded(palette, step), bay(step, far, level(step - 1)));
    }
    if (beacon > 0) {
        quarter.paint(palette.light, bay(far, far, Span(steps, steps + beacon - 1)));
    }
}

void pit(Turtle quarter, Palette palette, int steps) {
    int far = quarter.column().high;
    foreach (step; 1 .. steps + 1) {
        quarter.paint(Material.none, bay(step, far, level(-step)));
        quarter.paint(banded(palette, step), bay(step, far, level(-step - 1)));
    }
    quarter.paint(palette.light, bay(far, far, level(-steps - 1)));
}

void terraces(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    const(Root)* root = cast(const(Root)*) data;
    Turtle face = Turtle(api, site);
    ulong hash = face.probeHash(SitePart.face);
    Palette palette = paletteOf(materials.terraces, face);
    Terrace shape = terraceOf(face, hash, *risen, *root);
    int steps = LEAST_STEPS + cast(int)(mixed(hash, STEPS_SALT) % STEP_CHOICES);
    int beacon = 0;
    if (roll(hash, BEACON_SALT) < tuning.beaconOdds) {
        beacon = LEAST_BEACON + cast(int)(mixed(hash, BEACON_SALT + 1) % BEACON_CHOICES);
    }
    foreach (corner; cornersOf(face)) {
        Turtle quarter = upright(corner);
        quarter.paint(palette.floor, bay(0, quarter.column().high, level(FLOOR)));
        final switch (shape) {
            case Terrace.plaza:
                break;
            case Terrace.pit:
                pit(quarter, palette, steps);
                break;
            case Terrace.ziggurat:
                ziggurat(quarter, palette, steps, beacon);
                break;
        }
    }
    foot(api, face, risen, TERRACES_TAG, *root);
}

void monolith(Turtle quarter, Palette palette, int tall) {
    quarter.paint(palette.step, boxOf(MONOLITH_X, MONOLITH_Y, Span(0, MONOLITH + tall)));
    quarter.paint(palette.light, boxOf(MONOLITH_X, MONOLITH_Y, level(MONOLITH + tall + 1)));
}

void arch(Turtle quarter, Palette palette, int tall) {
    foreach (post; ARCH_POSTS) {
        quarter.paint(palette.step, boxOf(post, ARCH_Y, Span(0, ARCH + tall)));
    }
    quarter.paint(palette.accent, boxOf(ARCH_SPAN, ARCH_Y, Span(ARCH + tall + 1, ARCH + tall + 2)));
}

void cube(Turtle quarter, Palette palette, int tall) {
    int side = LEAST_CUBE + tall % cast(int) CUBE_CHOICES;
    int lift = CUBE_LIFT + tall / 2;
    Span across = Span(CUBE_AT, CUBE_AT + side);
    quarter.paint(palette.accent, boxOf(across, across, Span(lift, lift + side)));
    quarter.paint(palette.light, boxOf(across, across, level(lift + side + 1)));
}

void flight(Turtle quarter, Palette palette, int tall) {
    int count = LEAST_FLIGHT + tall % cast(int) FLIGHT_CHOICES;
    foreach (index; 0 .. count) {
        quarter.paint(palette.step, boxOf(level(FLIGHT_START + index), FLIGHT_WIDTH, Span(0, index)));
    }
    quarter.paint(palette.light, boxOf(level(FLIGHT_START + count), FLIGHT_WIDTH, level(count - 1)));
}

void pillars(Turtle quarter, Palette palette, ulong spot) {
    uint index = 0;
    foreach (x; PILLAR_SPOTS) {
        foreach (y; PILLAR_SPOTS) {
            int tall = LEAST_PILLAR + cast(int)(mixed(spot, PILLAR_SALT + index) % PILLAR_CHOICES);
            quarter.paint(palette.step, boxOf(Span(x, x + 1), Span(y, y + 1), Span(0, tall)));
            if (index == 0) {
                quarter.paint(palette.light, boxOf(Span(x, x + 1), Span(y, y + 1), level(tall + 1)));
            }
            index += 1;
        }
    }
}

void spire(Turtle quarter, Palette palette, int tall) {
    int shaft = SPIRE_PLINTH + SPIRE_RISE + tall;
    int tip = shaft + SPIRE_RISE + tall;
    quarter.paint(palette.step, boxOf(SPIRE_BASE, SPIRE_BASE, Span(0, SPIRE_PLINTH)));
    quarter.paint(palette.accent, boxOf(SPIRE_SHAFT, SPIRE_SHAFT, Span(SPIRE_PLINTH + 1, shaft)));
    quarter.paint(palette.step, boxOf(SPIRE_TIP, SPIRE_TIP, Span(shaft + 1, tip)));
    quarter.paint(palette.light, boxOf(SPIRE_TIP, SPIRE_TIP, level(tip + 1)));
}

void form(Turtle quarter, Palette palette, ulong spot) {
    Form chosen = cast(Form)(mixed(spot, FORM_SALT + 1) % FORM_COUNT);
    int tall = cast(int)(mixed(spot, SIZE_SALT) % SIZE_CHOICES);
    final switch (chosen) {
        case Form.monolith:
            monolith(quarter, palette, tall);
            break;
        case Form.arch:
            arch(quarter, palette, tall);
            break;
        case Form.cube:
            cube(quarter, palette, tall);
            break;
        case Form.flight:
            flight(quarter, palette, tall);
            break;
        case Form.pillars:
            pillars(quarter, palette, spot);
            break;
        case Form.spire:
            spire(quarter, palette, tall);
            break;
    }
}

void garden(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    const(Root)* root = cast(const(Root)*) data;
    Turtle face = Turtle(api, site);
    ulong hash = face.probeHash(SitePart.face);
    Palette palette = paletteOf(materials.garden, face);
    foreach (corner; cornersOf(face)) {
        Turtle quarter = upright(corner);
        quarter.paint(palette.floor, bay(0, quarter.column().high, level(FLOOR)));
        ulong spot = corner.probeHash(SitePart.vertex) ^ hash;
        bool taken = blocks.probeTaken(corner, *risen);
        if (!taken && hash != root.plain && roll(spot, FORM_SALT) < tuning.formShare) {
            form(quarter, palette, spot);
        }
    }
    foot(api, face, risen, GARDEN_TAG, *root);
}

void catwalk(Turtle quarter, Palette palette, Along along, ulong hash) {
    int far = quarter.column().high;
    if (roll(hash, STAIR_SALT) < tuning.stairOdds) {
        foreach (index; 0 .. DECK - 1) {
            quarter.paint(palette.step, line(along, level(STAIR_START + index), level(index)));
        }
        quarter.paint(palette.accent, line(along, Span(STAIR_START + DECK - 1, far), level(DECK - 1)));
    } else {
        quarter.paint(palette.accent, line(along, Span(1, far), level(DECK - 1)));
    }
}

void trellis(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    const(Root)* root = cast(const(Root)*) data;
    Turtle face = Turtle(api, site);
    ulong hash = face.probeHash(SitePart.face);
    Palette palette = paletteOf(materials.trellis, face);
    Material floor = palette.floor;
    if (roll(hash, PLANK_SALT) < tuning.plankShare) {
        floor = palette.step;
    }
    bool decked = hash != root.plain && roll(hash, DECK_SALT) < tuning.deckShare;
    foreach (corner; cornersOf(face)) {
        Turtle quarter = upright(corner);
        int far = quarter.column().high;
        ulong vertex = corner.probeHash(SitePart.vertex);
        quarter.paint(floor, bay(1, far, level(FLOOR)));
        quarter.paint(palette.accent, line(Along.x, Span(0, far), level(FLOOR)));
        quarter.paint(palette.accent, line(Along.y, Span(1, far), level(FLOOR)));
        bool taken = blocks.probeTaken(corner, *risen);
        if (!taken) {
            quarter.paint(palette.accent, boxOf(level(0), level(0), Span(0, DECK - 1)));
            if (roll(vertex, LANTERN_SALT) < tuning.lanternOdds) {
                quarter.paint(palette.light, boxOf(level(0), level(0), level(DECK)));
            }
            catwalk(quarter, palette, Along.x, corner.probeHash(SitePart.edge) ^ vertex);
            catwalk(quarter, palette, Along.y, corner.right().probeHash(SitePart.edge) ^ vertex);
            if (decked) {
                quarter.paint(palette.step, bay(1, far, level(DECK - 1)));
            }
        }
    }
    foot(api, face, risen, TRELLIS_TAG, *root);
}

void world(alias tile, uint tag, string look)(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    Root root = Root(Connection.rolled(), at.probeHash(SitePart.face));
    KindId kind = api.horosphere(api, 0, HorosphereForm.bare, tag, &tile, &root, Root.sizeof);
    api.rooted(api, kind);
    api.look(api, kind, look);
    api.worldLook(api, look);
    api.fog(api, tuning.fog);
    upright(at).entrance(SPAWN.x, SPAWN.y, SPAWN.z);
}

immutable Dependency[2] NEEDS = [dependencyOn(BASE), dependencyOn("connector")];
immutable Manifest MANIFEST = Manifest("skies", FIRST_VERSION, NEEDS[], null, &resolve, null, import("plugins/skies/settings.conf"), import("plugins/skies/skies.decl"), import("plugins/skies/skies.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.add(registry, "terraces", &world!(terraces, TERRACES_TAG, TERRACES_LOOK));
    registry.add(registry, "garden", &world!(garden, GARDEN_TAG, GARDEN_LOOK));
    registry.add(registry, "trellis", &world!(trellis, TRELLIS_TAG, TRELLIS_LOOK));
    RisingKind risingTerraces = RisingKind(RISING_SHARE, HorosphereForm.bare, TERRACES_TAG, &terraces, &RISING, Root.sizeof, TERRACES_LOOK);
    registry.addKind(registry, "zenith-terraces", &risingTerraces);
    RisingKind risingGarden = RisingKind(RISING_SHARE, HorosphereForm.bare, GARDEN_TAG, &garden, &RISING, Root.sizeof, GARDEN_LOOK);
    registry.addKind(registry, "zenith-garden", &risingGarden);
    RisingKind risingTrellis = RisingKind(RISING_SHARE, HorosphereForm.bare, TRELLIS_TAG, &trellis, &RISING, Root.sizeof, TRELLIS_LOOK);
    registry.addKind(registry, "zenith-trellis", &risingTrellis);
}
