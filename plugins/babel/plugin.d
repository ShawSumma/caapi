module plugins.babel.plugin;

import plugins.api.api : Api, ENTRY, HorosphereForm, Look, Material, NO_KIND, Registry, Rhythm, Risen, RisingKind, Site;
import plugins.connector.connector : Tag;
import plugins.turtle.turtle : ENDLESS_HIGH, Tread, Turtle, boxOf, cornersOf, floorMod, middle, treadAround, upright;

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
immutable Look LOOK = Look("babel", "An endless stair. Climb and the ground below shrinks to a disc while the sky keeps opening.", [0.82f, 0.74f, 0.58f], true);

// A rhythm counts from the bottom of its site; a segment lifted above the stair's start moves every rhythm down by that much.
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

void lawn(const(Api)* api, Site face, const(Risen)* risen, const(void)* data) {
    foreach (corner; cornersOf(Turtle(api, face))) {
        upright(corner).paint(Material.grass, boxOf([0, corner.column().high], [0, corner.column().high], [-1, -1]));
    }
}

void landmark(const(Api)* api, Site site, const(void)* data) {
    Turtle tower = upright(Turtle(api, site));
    tower.paint(Material.granite, boxOf([-PLAZA, PLAZA - 1], [-PLAZA, PLAZA - 1], [0, 0]));
    core(tower, [0, ENDLESS_HIGH], 0);
    stair(tower, [0, ENDLESS_HIGH], 0);
    route(tower);
}

void column(const(Api)* api, Site base, const(Risen)* risen, const(void)* data) {
    Turtle tower = Turtle(api, base);
    int length = tower.edgeCells();
    int[2] rising = [0, length - 1];
    int lifted = risen.segment * length;
    if (risen.segment == 0) {
        tower.fill(WALL, boxOf([-PLAZA, PLAZA - 1], [-PLAZA, PLAZA - 1], [-FOOTING, -1]));
        tower.paint(Material.granite, boxOf([-PLAZA, PLAZA - 1], [-PLAZA, PLAZA - 1], [0, 0]));
    }
    core(tower, rising, lifted);
    stair(tower, rising, lifted);
}

void world(const(Api)* api, Site site, const(void)* data) {
    landmark(api, site, data);
    api.tile(api, &lawn, null, 0);
    api.look(api, NO_KIND, &LOOK);
    upright(Turtle(api, site)).entrance(SPAWN[0], SPAWN[1], SPAWN[2]);
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "babel", &world);
    RisingKind rising = RisingKind(COLUMN_SHARE, HorosphereForm.upright, Tag.column, &column, null, 0, LOOK);
    registry.addKind(registry, "babel", &rising);
    registry.addLandmark(registry, "babel", &landmark);
}
