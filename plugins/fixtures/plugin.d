module plugins.fixtures.plugin;

import plugins.api.api : Api, ENTRY, Registry, Site, SitePart, SkyGround, Tile;
import box = plugins.box.box;
import plugins.buildings.building : Bound, Lot, Lots, Side, Spec;
import plugins.buildings.types : Type, build, palettes;
import layout = plugins.rooms.layout;
import plugins.skies.skies : backroomsSky, citySky, wildSky;
import plugins.turtle.turtle : Turtle, cornersOf;

enum uint SKY_EDGES = 2;
enum uint HOUSE_FLOOR = 1;
enum uint TOP_FLOOR = 0;
enum int SHOWCASE_FRONT = 4;
immutable bool ROUTED = true;

void openRoutedSky(const(Api)* api, Site site, SkyGround ground, Tile tile) {
    uint kind = api.sky(api, 0, ground, tile, &ROUTED, bool.sizeof);
    api.openSky(api, site, kind, SKY_EDGES);
}

void skyCity(const(Api)* api, Site site, const(void)* data) {
    openRoutedSky(api, site, SkyGround.flat, &citySky);
}

void skyWild(const(Api)* api, Site site, const(void)* data) {
    openRoutedSky(api, site, SkyGround.terrain, &wildSky);
}

void skyBackrooms(const(Api)* api, Site site, const(void)* data) {
    openRoutedSky(api, site, SkyGround.flat, &backroomsSky);
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
    registry.add(registry, "skycity", &skyCity);
    registry.add(registry, "skywild", &skyWild);
    registry.add(registry, "skybackrooms", &skyBackrooms);
    registry.add(registry, "basement", &basement);
    registry.add(registry, "backroomsstairs", &backroomsStairs);
    registry.add(registry, "showcase", &showcase);
    registry.add(registry, "hamlet", &hamlet);
}
