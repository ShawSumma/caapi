module plugins.babel.plugin;

import plugins.api.api : Api, ENTRY, HorosphereForm, Look, Material, NO_KIND, Registry, Rhythm, Risen, RisingKind, Site, Tint;
import plugins.connector.connector : Tag;
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
immutable float[3] SPAWN = [-PLAZA, 0, 1];
enum Material WALL = Material.sandstone;
enum Material STEP = Material.redSandstone;
enum Material BAND = Material.marble;
enum double COLUMN_SHARE = 0.1;
enum uint COLUMN_EDGES = 2;
immutable Look LOOK = Look("babel", [0.82f, 0.74f, 0.58f], Tint.fog);

void core(Turtle tower, int[2] rising, int lifted) {
    int[2] wall = [-CORE, CORE - 1];
    int[2] room = [-CORE + 1, CORE - 2];
    tower.paint(WALL, boxOf(wall, wall, rising));
    tower.paint(BAND, boxOf(wall, wall, rising), Rhythm(BAND_EVERY, floorMod(BAND_EVERY - 1 - lifted, BAND_EVERY), 1));
    tower.paint(Material.none, boxOf(room, room, rising), Rhythm(TREADS, floorMod(2 - lifted, TREADS), TREADS - 1));
    tower.paint(Material.lightPanel, boxOf([-1, 0], [-1, 0], rising), Rhythm(TREADS, floorMod(-lifted, TREADS), 1));
    tower.paint(Material.none, boxOf([0, 1], [CORE - 1, CORE - 1], rising), Rhythm(TREADS, floorMod(2 - lifted, TREADS), 3));
}

void stair(Turtle tower, int[2] rising, int lifted) {
    foreach (index; 0 .. TREADS) {
        Tread tread = treadAround(CORE, RING, SIDE_TREADS, index);
        tower.paint(STEP, boxOf(tread.x, tread.y, rising), Rhythm(TREADS, floorMod(index - TREAD_DEPTH + 1 - lifted, TREADS), TREAD_DEPTH));
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
        tower.fill(WALL, boxOf([-PLAZA, PLAZA - 1], [-PLAZA, PLAZA - 1], [plaza - FOOTING, plaza - 1]));
        tower.paint(Material.granite, boxOf([-PLAZA, PLAZA - 1], [-PLAZA, PLAZA - 1], [plaza, plaza]));
    }
    if (plaza < length) {
        int[2] rising = [higherOf(0, plaza), length - 1];
        core(tower, rising, lifted);
        stair(tower, rising, lifted);
    }
}

void landmark(const(Api)* api, Site site, const(void)* data) {
    uint kind = api.horosphere(api, 0, HorosphereForm.upright, Tag.column, &column, null, 0);
    api.openHorosphere(api, site, kind, COLUMN_EDGES);
}

void world(const(Api)* api, Site site, const(void)* data) {
    landmark(api, site, data);
    api.tile(api, &lawn, null, 0);
    api.look(api, NO_KIND, &LOOK);
    Turtle tower = Turtle(api, site).columnSite();
    route(tower);
    tower.entrance(SPAWN[0], SPAWN[1], SPAWN[2]);
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "babel", &world);
    RisingKind rising = RisingKind(COLUMN_SHARE, HorosphereForm.upright, Tag.column, &column, null, 0, LOOK);
    registry.addKind(registry, "babel", &rising);
    registry.addLandmark(registry, "babel", &landmark);
}
