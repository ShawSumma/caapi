module plugins.fixtures.plugin;

import plugins.api.api : Api, HorosphereForm, Registry, Site, SitePart, entryOf;
import box = plugins.box.box;
import plugins.buildings.building : Bound, Lot, Lots, Side, Spec;
import plugins.buildings.types : Type, build, palettes;
import plugins.connector.connector : Connection, Routing, Style, Tag;
import layout = plugins.rooms.layout;
import plugins.horospheres.horospheres : Kinds, addKinds, cityTile;
import plugins.turtle.turtle : Turtle, cornersOf;

enum uint RISE_EDGES = 2;
enum int CHAIN_EDGES = 4;
immutable float[3] CHAIN_SPAWN = [0, 4, 0];
immutable Connection UNROUTED = Connection.forced(Style.tower, Routing.unrouted);
immutable Connection ROUTED = Connection.forced(Style.tower, Routing.routed);
enum uint HOUSE_FLOOR = 1;
enum uint TOP_FLOOR = 0;
enum int SHOWCASE_FRONT = 4;

Kinds routedKinds(const(Api)* api) {
    return addKinds(api, 0, 0, &ROUTED);
}

void risenCity(const(Api)* api, Site site, const(void)* data) {
    api.openHorosphere(api, site, routedKinds(api).city, RISE_EDGES);
}

void styled(Style style)(const(Api)* api, Site site, const(void)* data) {
    immutable Connection how = Connection.forced(style, Routing.routed);
    api.openHorosphere(api, site, addKinds(api, 0, 0, &how).city, RISE_EDGES);
}

void risenWild(const(Api)* api, Site site, const(void)* data) {
    api.openHorosphere(api, site, routedKinds(api).wild, RISE_EDGES);
}

void risenBackrooms(const(Api)* api, Site site, const(void)* data) {
    api.openHorosphere(api, site, routedKinds(api).backrooms, RISE_EDGES);
}

void stacked(const(Api)* api, Site site, const(void)* data) {
    Kinds kinds = routedKinds(api);
    api.rooted(api, kinds.backrooms);
    api.openHorosphere(api, site, kinds.city, RISE_EDGES);
}

void stackedRooms(const(Api)* api, Site site, const(void)* data) {
    Kinds kinds = routedKinds(api);
    api.rooted(api, kinds.backrooms);
    api.openHorosphere(api, site, kinds.backrooms, RISE_EDGES);
}

enum Ground : ubyte {
    plain,
    wild,
    city,
    backrooms,
}

uint kindOf(Kinds kinds, Ground ground) {
    final switch (ground) {
        case Ground.plain:
        case Ground.wild:
            return kinds.wild;
        case Ground.city:
            return kinds.city;
        case Ground.backrooms:
            return kinds.backrooms;
    }
}

void trip(Style style, Ground lower, Ground upper)(const(Api)* api, Site site, const(void)* data) {
    immutable Connection how = Connection.forced(style, Routing.roundTrip);
    Kinds kinds = addKinds(api, 0, 0, &how);
    if (lower != Ground.plain) {
        api.rooted(api, kindOf(kinds, lower));
    }
    api.openHorosphere(api, site, kindOf(kinds, upper), RISE_EDGES);
}

void chain(const(Api)* api, Site site, const(void)* data) {
    Kinds kinds = addKinds(api, 0, 0, &UNROUTED);
    uint upper = api.horosphere(api, 0, HorosphereForm.solid, Tag.city, &cityTile, &ROUTED, Connection.sizeof);
    api.openHorosphere(api, site, kinds.city, RISE_EDGES);
    Turtle along = Turtle(api, site).pitchUp().forward(RISE_EDGES).pitchUp().forward(CHAIN_EDGES);
    api.openHorosphere(api, along.site, upper, RISE_EDGES);
    along.entrance(CHAIN_SPAWN[0], CHAIN_SPAWN[1], CHAIN_SPAWN[2]);
}

void forcedStair(const(Api)* api, Site site, uint upper) {
    Turtle at = Turtle(api, site);
    Turtle stairs = at.forward(1).right();
    layout.ForcedStair forced = layout.ForcedStair(stairs.hash(SitePart.vertex), stairs.hash(SitePart.face), upper);
    layout.Root root = layout.Root(at.hash(SitePart.vertex), layout.Shaft.none, Routing.routed, forced);
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

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.add(registry, "risencity", &risenCity);
    registry.add(registry, "spiralcity", &styled!(Style.spiral));
    registry.add(registry, "driftcity", &styled!(Style.drift));
    registry.add(registry, "lanterncity", &styled!(Style.lantern));
    registry.add(registry, "risenwild", &risenWild);
    registry.add(registry, "risenbackrooms", &risenBackrooms);
    registry.add(registry, "stacked", &stacked);
    registry.add(registry, "stackedrooms", &stackedRooms);
    registry.add(registry, "tripcity", &trip!(Style.tower, Ground.plain, Ground.city));
    registry.add(registry, "tripwild", &trip!(Style.tower, Ground.plain, Ground.wild));
    registry.add(registry, "triprooms", &trip!(Style.tower, Ground.plain, Ground.backrooms));
    registry.add(registry, "tripstacked", &trip!(Style.tower, Ground.backrooms, Ground.backrooms));
    registry.add(registry, "tripcities", &trip!(Style.tower, Ground.city, Ground.city));
    registry.add(registry, "tripwildwild", &trip!(Style.tower, Ground.wild, Ground.wild));
    registry.add(registry, "tripspiral", &trip!(Style.spiral, Ground.plain, Ground.wild));
    registry.add(registry, "tripdrift", &trip!(Style.drift, Ground.plain, Ground.backrooms));
    registry.add(registry, "triplantern", &trip!(Style.lantern, Ground.city, Ground.city));
    registry.add(registry, "chain", &chain);
    registry.add(registry, "basement", &basement);
    registry.add(registry, "backroomsstairs", &backroomsStairs);
    registry.add(registry, "showcase", &showcase);
    registry.add(registry, "hamlet", &hamlet);
}
