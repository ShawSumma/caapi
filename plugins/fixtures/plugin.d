module plugins.fixtures.plugin;

import plugins.api.api : Api, ENTRY, HorosphereForm, Registry, Site, SitePart;
import box = plugins.box.box;
import plugins.buildings.building : Bound, Lot, Lots, Side, Spec;
import plugins.buildings.types : Type, build, palettes;
import layout = plugins.rooms.layout;
import plugins.horospheres.horospheres : Kinds, Tag, addKinds, cityTile;
import plugins.turtle.turtle : Turtle, cornersOf;

enum uint RISE_EDGES = 2;
enum int CHAIN_EDGES = 4;
immutable float[3] CHAIN_SPAWN = [0, 4, 0];
immutable bool UNROUTED = false;
enum uint HOUSE_FLOOR = 1;
enum uint TOP_FLOOR = 0;
enum int SHOWCASE_FRONT = 4;
immutable bool ROUTED = true;

// The kinds, none of which rise by chance, with their connectors routed.
Kinds routedKinds(const(Api)* api) {
    return addKinds(api, 0, 0, &ROUTED);
}

void risenCity(const(Api)* api, Site site, const(void)* data) {
    api.openHorosphere(api, site, routedKinds(api).city, RISE_EDGES);
}

void risenWild(const(Api)* api, Site site, const(void)* data) {
    api.openHorosphere(api, site, routedKinds(api).wild, RISE_EDGES);
}

void risenBackrooms(const(Api)* api, Site site, const(void)* data) {
    api.openHorosphere(api, site, routedKinds(api).backrooms, RISE_EDGES);
}

// Backrooms at the root with a city rising from them, reached from the lobby under the city's foot.
void stacked(const(Api)* api, Site site, const(void)* data) {
    Kinds kinds = routedKinds(api);
    api.rooted(api, kinds.backrooms);
    api.openHorosphere(api, site, kinds.city, RISE_EDGES);
}

// A city rising from the ground and a second rising from the first, a few edges along it, where the two planes are
// far enough apart; only the second's connector is routed, and the spawn stands on the first by its foot.
void chain(const(Api)* api, Site site, const(void)* data) {
    Kinds kinds = addKinds(api, 0, 0, &UNROUTED);
    uint upper = api.horosphere(api, 0, HorosphereForm.bare, Tag.city, &cityTile, &ROUTED, bool.sizeof);
    api.openHorosphere(api, site, kinds.city, RISE_EDGES);
    Turtle along = Turtle(api, site).pitchUp().forward(RISE_EDGES).pitchUp().forward(CHAIN_EDGES);
    api.openHorosphere(api, along.site, upper, RISE_EDGES);
    along.entrance(CHAIN_SPAWN[0], CHAIN_SPAWN[1], CHAIN_SPAWN[2]);
}

void forcedStair(const(Api)* api, Site site, uint upper) {
    Turtle at = Turtle(api, site);
    Turtle stairs = at.forward(1).right();
    layout.ForcedStair forced = layout.ForcedStair(stairs.hash(SitePart.vertex), stairs.hash(SitePart.face), upper, true);
    layout.Root root = layout.Root(at.hash(SitePart.vertex), false, true, forced);
    api.tile(api, &layout.tile, &root, layout.Root.sizeof);
}

void basement(const(Api)* api, Site site, const(void)* data) {
    forcedStair(api, site, HOUSE_FLOOR);
}

void backroomsStairs(const(Api)* api, Site site, const(void)* data) {
    forcedStair(api, site, TOP_FLOOR);
}

Turtle show(Turtle quarter, Type type, int stories) {
    Lot lot;
    lot.site = quarter;
    lot.bounds = [Bound.street, Bound.street, Bound.lot, Bound.lot];
    lot.front = Side.yLow;
    lot.hasFront = true;
    Lots lots;
    lots.add(lot);
    build(type, lots, Spec(stories, palettes(type)[0], SHOWCASE_FRONT, 0, 0));
    return quarter.right();
}

void showcase(const(Api)* api, Site site, const(void)* data) {
    Turtle quarter = Turtle(api, site);
    quarter = show(quarter, Type.brownstone, 5);
    quarter = show(quarter, Type.tenement, 8);
    quarter = show(quarter, Type.deco, 24);
    show(quarter, Type.glass, 30);
}

void hut(Turtle site) {
    Turtle tower = site.pitchUp();
    box.hut(tower);
    box.stairRoute(tower, 0, box.HUT_TOP);
    tower.entrance(-box.HALF_WIDTH, 0, 1);
}

void hamlet(const(Api)* api, Site site, const(void)* data) {
    foreach (corner; cornersOf(Turtle(api, site))) {
        hut(corner);
    }
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "risencity", &risenCity);
    registry.add(registry, "risenwild", &risenWild);
    registry.add(registry, "risenbackrooms", &risenBackrooms);
    registry.add(registry, "stacked", &stacked);
    registry.add(registry, "chain", &chain);
    registry.add(registry, "basement", &basement);
    registry.add(registry, "backroomsstairs", &backroomsStairs);
    registry.add(registry, "showcase", &showcase);
    registry.add(registry, "hamlet", &hamlet);
}
