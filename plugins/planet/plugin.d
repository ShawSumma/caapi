module plugins.planet.plugin;

import plugins.api.api : Api, ENTRY, Registry, Site, SkyGround;
import plugins.skies.skies : backroomsSky, citySky, spiresSky, wildSky;
import plugins.turtle.turtle : Turtle;

enum double SKY_ODDS = 0.02;
enum int TREE_EDGES = 1;
immutable bool UNROUTED = false;

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    at.build("road");
    at.right().forward(TREE_EDGES).build("bigtree");
    api.sky(api, SKY_ODDS, SkyGround.terrain, &wildSky, &UNROUTED, bool.sizeof);
    api.sky(api, SKY_ODDS, SkyGround.flat, &citySky, &UNROUTED, bool.sizeof);
    api.sky(api, SKY_ODDS, SkyGround.flat, &spiresSky, &UNROUTED, bool.sizeof);
    api.sky(api, SKY_ODDS, SkyGround.flat, &backroomsSky, &UNROUTED, bool.sizeof);
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "planet", &world);
}
