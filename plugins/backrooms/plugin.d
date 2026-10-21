module plugins.backrooms.plugin;

import plugins.api.api : Api, ENTRY, Registry, Site, SitePart;
import layout = plugins.rooms.layout;
import plugins.turtle.turtle : Turtle, upright;

immutable float[3] SPAWN = [14, 4.5, layout.GROUND];

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    layout.Root root = layout.Root(at.hash(SitePart.vertex), false, false);
    api.tile(api, &layout.tile, &root, layout.Root.sizeof);
    upright(at).entrance(SPAWN[0], SPAWN[1], SPAWN[2]);
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "backrooms", &world);
}
