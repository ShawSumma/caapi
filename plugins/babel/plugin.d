module plugins.babel.plugin;

import plugins.api.api : Api, HorosphereForm, KindId, Material, Registry, Rhythm, Risen, RisingKind, Site, Span, Spot, entryOf, tagNamed;
import plugins.api.binding : bound;
import plugins.api.content : Content, FIRST_VERSION, Manifest, ON_BASE;
import plugins.turtle.turtle : Tread, Turtle, boxOf, floorMod, higherOf, lawn, middle, treadAround;

enum int CORE = 3;
enum int RING = 5;
enum int SIDE_TREADS = 3;
enum int TREADS = 4 * (SIDE_TREADS + 1);
enum int TREAD_DEPTH = 3;
enum int PLAZA = 12;
enum int BAND_EVERY = 64;
enum int ROUTE_TURNS = 2;
enum int FOOTING = 12;
immutable Spot SPAWN = Spot(-PLAZA, 0, 1);
enum double COLUMN_SHARE = 0.1;
enum uint COLUMN_EDGES = 2;
enum uint COLUMN_TAG = tagNamed("babel:column");
enum string LOOK = "babel:look";

struct Materials {
    Material wall;
    Material step;
    Material band;
    Material light;
    Material plaza;
    Material lawn;
}

__gshared Materials materials;

void resolve(const(Content)* content) {
    materials = content.bound!Materials("babel:materials");
}

void core(Turtle tower, Span rising, int lifted) {
    Span wall = Span(-CORE, CORE - 1);
    Span room = Span(-CORE + 1, CORE - 2);
    tower.paint(materials.wall, boxOf(wall, wall, rising));
    tower.paint(materials.band, boxOf(wall, wall, rising), Rhythm(BAND_EVERY, floorMod(BAND_EVERY - 1 - lifted, BAND_EVERY), 1));
    tower.paint(Material.none, boxOf(room, room, rising), Rhythm(TREADS, floorMod(2 - lifted, TREADS), TREADS - 1));
    tower.paint(materials.light, boxOf(Span(-1, 0), Span(-1, 0), rising), Rhythm(TREADS, floorMod(-lifted, TREADS), 1));
    tower.paint(Material.none, boxOf(Span(0, 1), Span(CORE - 1, CORE - 1), rising), Rhythm(TREADS, floorMod(2 - lifted, TREADS), 3));
}

void stair(Turtle tower, Span rising, int lifted) {
    foreach (index; 0 .. TREADS) {
        Tread tread = treadAround(CORE, RING, SIDE_TREADS, index);
        tower.paint(materials.step, boxOf(tread.x, tread.y, rising), Rhythm(TREADS, floorMod(index - TREAD_DEPTH + 1 - lifted, TREADS), TREAD_DEPTH));
    }
}

void route(Turtle tower) {
    tower.stop(CORE + RING + 1.5f, middle(treadAround(CORE, RING, SIDE_TREADS, 0).y), 1);
    foreach (index; 0 .. ROUTE_TURNS * TREADS) {
        Tread tread = treadAround(CORE, RING, SIDE_TREADS, index);
        tower.stop(middle(tread.x), middle(tread.y), index + 1);
    }
}

void column(const(Api)* api, Site base, const(Risen)* risen, const(void)* data) {
    Turtle tower = Turtle(api, base);
    int length = tower.edgeCells();
    int lifted = risen.segment * length;
    int plaza = risen.ground - lifted;
    if (plaza >= 0 && plaza < length) {
        tower.fill(materials.wall, boxOf(Span(-PLAZA, PLAZA - 1), Span(-PLAZA, PLAZA - 1), Span(plaza - FOOTING, plaza - 1)));
        tower.paint(materials.plaza, boxOf(Span(-PLAZA, PLAZA - 1), Span(-PLAZA, PLAZA - 1), Span(plaza, plaza)));
    }
    if (plaza < length) {
        Span rising = Span(higherOf(0, plaza), length - 1);
        core(tower, rising, lifted);
        stair(tower, rising, lifted);
    }
}

void landmark(const(Api)* api, Site site, const(void)* data) {
    KindId kind = api.horosphere(api, 0, HorosphereForm.upright, COLUMN_TAG, &column, null, 0);
    api.openHorosphere(api, site, kind, COLUMN_EDGES);
}

void world(const(Api)* api, Site site, const(void)* data) {
    landmark(api, site, data);
    api.tile(api, &lawn, &materials.lawn, Material.sizeof);
    api.worldLook(api, LOOK);
    Turtle tower = Turtle(api, site).columnSite();
    route(tower);
    tower.entrance(SPAWN.x, SPAWN.y, SPAWN.z);
}

immutable Manifest MANIFEST = Manifest("babel", FIRST_VERSION, ON_BASE[], null, &resolve, null, null, import("plugins/babel/babel.decl"), import("plugins/babel/babel.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.addDebug(registry, "babel", &world);
    RisingKind rising = RisingKind(COLUMN_SHARE, HorosphereForm.upright, COLUMN_TAG, &column, null, 0, LOOK);
    registry.addKind(registry, "babel", &rising);
    registry.addLandmark(registry, "babel", &landmark);
}
