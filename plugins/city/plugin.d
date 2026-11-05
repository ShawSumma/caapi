module plugins.city.plugin;

import plugins.api.api : Api, NO_KIND, Registry, Site, entryOf;
import blocks = plugins.blocks.blocks;
import plugins.horospheres.horospheres : CITY_LOOK;
import plugins.turtle.turtle : Turtle;

immutable float[3] SPAWN = [6, 0, -0.5];

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    blocks.Root root = blocks.rootAt(at);
    api.tile(api, &blocks.tile, &root, blocks.Root.sizeof);
    api.look(api, NO_KIND, &CITY_LOOK);
    at.right().entrance(SPAWN[0], SPAWN[1], SPAWN[2]);
}

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.add(registry, "city", &world);
}
