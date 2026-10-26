module plugins.babel.plugin;

import plugins.api.api : Api, ENTRY, Material, Registry, Rhythm, Risen, Site;
import plugins.turtle.turtle : ENDLESS_HIGH, Tread, Turtle, boxOf, cornersOf, floorMod, middle, treadAround, upright;

enum int CORE = 3;
enum int RING = 5;
enum int SIDE_TREADS = 3;
enum int TREADS = 4 * (SIDE_TREADS + 1);
enum int TREAD_DEPTH = 3;
enum int PLAZA = 12;
enum int BAND_EVERY = 64;
enum int ROUTE_TURNS = 2;
immutable float[3] SPAWN = [-PLAZA, 0, 1];
enum Material WALL = Material.sandstone;
enum Material STEP = Material.redSandstone;
enum Material BAND = Material.marble;

void core(Turtle tower) {
    int[2] wall = [-CORE, CORE - 1];
    int[2] room = [-CORE + 1, CORE - 2];
    int[2] rising = [0, ENDLESS_HIGH];
    tower.paint(WALL, boxOf(wall, wall, rising));
    tower.paint(BAND, boxOf(wall, wall, rising), Rhythm(BAND_EVERY, BAND_EVERY - 1, 1));
    tower.paint(Material.none, boxOf(room, room, rising), Rhythm(TREADS, 2, TREADS - 1));
    tower.paint(Material.lightPanel, boxOf([-1, 0], [-1, 0], rising), Rhythm(TREADS, 0, 1));
    tower.paint(Material.none, boxOf([0, 1], [CORE - 1, CORE - 1], rising), Rhythm(TREADS, 2, 3));
}

void stair(Turtle tower) {
    foreach (index; 0 .. TREADS) {
        Tread tread = treadAround(CORE, RING, SIDE_TREADS, index);
        tower.paint(STEP, boxOf(tread.x, tread.y, [0, ENDLESS_HIGH]), Rhythm(TREADS, floorMod(index - TREAD_DEPTH + 1, TREADS), TREAD_DEPTH));
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

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle tower = upright(Turtle(api, site));
    tower.paint(Material.granite, boxOf([-PLAZA, PLAZA - 1], [-PLAZA, PLAZA - 1], [0, 0]));
    core(tower);
    stair(tower);
    route(tower);
    api.tile(api, &lawn, null, 0);
    tower.entrance(SPAWN[0], SPAWN[1], SPAWN[2]);
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "babel", &world);
}
