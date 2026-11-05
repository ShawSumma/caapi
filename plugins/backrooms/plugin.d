module plugins.backrooms.plugin;

import plugins.api.api : Api, Registry, Site, SitePart, Spot, entryOf;
import plugins.connector.connector : BACKROOMS_GROUND;
import plugins.horospheres.horospheres : BACKROOMS_LOOK;
import layout = plugins.rooms.layout;
import plugins.turtle.turtle : Turtle, upright;

immutable Spot SPAWN = Spot(14, 4.5, BACKROOMS_GROUND);

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    layout.Root root = layout.Root(at.probeHash(SitePart.vertex));
    api.tile(api, &layout.tile, &root, layout.Root.sizeof);
    api.worldLook(api, &BACKROOMS_LOOK);
    upright(at).entrance(SPAWN.x, SPAWN.y, SPAWN.z);
}

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.add(registry, "backrooms", &world);
}
