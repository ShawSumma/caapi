module plugins.fixtures.plugin;

import plugins.api.api : Api, HorosphereForm, KindId, Registry, Site, SitePart, Spot, entryOf;
import plugins.api.content : BASE, Content, Dependency, FIRST_VERSION, Manifest, dependencyOn;
import box = plugins.box.box;
import plugins.api.binding : bound;
import plugins.buildings.building : Bound, Lot, Lots, Side, Spec, Traits;
import plugins.buildings.types : build;
import plugins.connector.connector : Connection, Routing, Style;
import layout = plugins.rooms.layout;
import plugins.horospheres.horospheres : CITY_TAG, Kinds, addKinds, cityTile, resolveHorospheres;
import plugins.rooms.rooms : MaybeLayer;
import plugins.turtle.turtle : Turtle, cornersOf;

enum uint RISE_EDGES = 2;
enum int CHAIN_EDGES = 4;
immutable Spot CHAIN_SPAWN = Spot(0, 4, 0);
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

KindId kindOf(Kinds kinds, Ground ground) {
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
    KindId upper = api.horosphere(api, 0, HorosphereForm.solid, CITY_TAG, &cityTile, &ROUTED, Connection.sizeof);
    api.openHorosphere(api, site, kinds.city, RISE_EDGES);
    Turtle along = Turtle(api, site).pitchUp().forward(RISE_EDGES).pitchUp().forward(CHAIN_EDGES);
    api.openHorosphere(api, along.site, upper, RISE_EDGES);
    along.entrance(CHAIN_SPAWN.x, CHAIN_SPAWN.y, CHAIN_SPAWN.z);
}

void forcedStair(const(Api)* api, Site site, uint upper) {
    Turtle at = Turtle(api, site);
    Turtle stairs = at.forward(1).right();
    layout.ForcedStair forced = layout.ForcedStair(stairs.probeHash(SitePart.vertex), stairs.probeHash(SitePart.face), MaybeLayer.of(upper));
    layout.Root root = layout.Root(at.probeHash(SitePart.vertex), layout.Shaft.none, Routing.routed, forced);
    api.tile(api, &layout.tile, &root, layout.Root.sizeof);
}

void basement(const(Api)* api, Site site, const(void)* data) {
    forcedStair(api, site, HOUSE_FLOOR);
}

void backroomsStairs(const(Api)* api, Site site, const(void)* data) {
    forcedStair(api, site, TOP_FLOOR);
}

struct Shown {
    string type;
    int stories;
}

immutable Shown[4] SHOWN = [Shown("buildings:brownstone", 5), Shown("buildings:tenement", 8), Shown("buildings:deco", 24), Shown("buildings:glass", 30)];

__gshared Traits[SHOWN.length] showcased;

Turtle show(Turtle quarter, ref const Traits traits, int stories) {
    Lot lot;
    lot.site = quarter;
    lot.bounds = [Bound.street, Bound.street, Bound.lot, Bound.lot];
    lot.front = Side.yLow;
    Lots lots;
    lots.add(lot);
    Spec spec = {stories: stories, palette: traits.palettes.items[0], front: SHOWCASE_FRONT};
    build(traits, lots, spec);
    return quarter.right();
}

void showcase(const(Api)* api, Site site, const(void)* data) {
    Turtle quarter = Turtle(api, site);
    foreach (index, ref shown; SHOWN) {
        quarter = show(quarter, showcased[index], shown.stories);
    }
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

void resolve(const(Content)* content) {
    resolveHorospheres(content);
    box.resolveBox(content);
    foreach (index, ref shown; SHOWN) {
        showcased[index] = content.bound!Traits(shown.type);
    }
}

immutable Dependency[7] NEEDS = [dependencyOn(BASE), dependencyOn("buildings"), dependencyOn("connector"), dependencyOn("blocks"), dependencyOn("rooms"), dependencyOn("horospheres"), dependencyOn("box")];
immutable Manifest MANIFEST = Manifest("fixtures", FIRST_VERSION, NEEDS[], null, &resolve);

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.addDebug(registry, "risencity", &risenCity);
    registry.addDebug(registry, "spiralcity", &styled!(Style.spiral));
    registry.addDebug(registry, "driftcity", &styled!(Style.drift));
    registry.addDebug(registry, "lanterncity", &styled!(Style.lantern));
    registry.addDebug(registry, "hiddenstair", &styled!(Style.hidden));
    registry.addDebug(registry, "risenwild", &risenWild);
    registry.addDebug(registry, "risenbackrooms", &risenBackrooms);
    registry.addDebug(registry, "stacked", &stacked);
    registry.addDebug(registry, "stackedrooms", &stackedRooms);
    registry.addDebug(registry, "tripcity", &trip!(Style.tower, Ground.plain, Ground.city));
    registry.addDebug(registry, "tripwild", &trip!(Style.tower, Ground.plain, Ground.wild));
    registry.addDebug(registry, "triprooms", &trip!(Style.tower, Ground.plain, Ground.backrooms));
    registry.addDebug(registry, "tripstacked", &trip!(Style.tower, Ground.backrooms, Ground.backrooms));
    registry.addDebug(registry, "tripcities", &trip!(Style.tower, Ground.city, Ground.city));
    registry.addDebug(registry, "tripwildwild", &trip!(Style.tower, Ground.wild, Ground.wild));
    registry.addDebug(registry, "tripspiral", &trip!(Style.spiral, Ground.plain, Ground.wild));
    registry.addDebug(registry, "tripdrift", &trip!(Style.drift, Ground.plain, Ground.backrooms));
    registry.addDebug(registry, "triplantern", &trip!(Style.lantern, Ground.city, Ground.city));
    registry.addDebug(registry, "chain", &chain);
    registry.addDebug(registry, "basement", &basement);
    registry.addDebug(registry, "backroomsstairs", &backroomsStairs);
    registry.addDebug(registry, "showcase", &showcase);
    registry.addDebug(registry, "hamlet", &hamlet);
}
