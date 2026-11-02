module plugins.backrooms.plugin;

import plugins.api.api : Api, ENTRY, NO_KIND, Registry, Site, SitePart;
import plugins.connector.connector : BACKROOMS_GROUND;
import plugins.horospheres.horospheres : BACKROOMS_LOOK;
import layout = plugins.rooms.layout;
import plugins.turtle.turtle : Turtle, upright;

immutable float[3] SPAWN = [14, 4.5, BACKROOMS_GROUND];

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    layout.Root root = layout.Root(at.hash(SitePart.vertex));
    api.tile(api, &layout.tile, &root, layout.Root.sizeof);
    api.look(api, NO_KIND, &BACKROOMS_LOOK);
    upright(at).entrance(SPAWN[0], SPAWN[1], SPAWN[2]);
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "backrooms", &world);
}
