module plugins.city.plugin;

import plugins.api.api : Api, Registry, Site, Spot, entryOf;
import blocks = plugins.blocks.blocks;
import plugins.horospheres.horospheres : CITY_LOOK;
import plugins.turtle.turtle : Turtle;

immutable Spot SPAWN = Spot(6, 0, -0.5);

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    blocks.Root root = blocks.rootAt(at);
    api.tile(api, &blocks.tile, &root, blocks.Root.sizeof);
    api.worldLook(api, &CITY_LOOK);
    at.right().entrance(SPAWN.x, SPAWN.y, SPAWN.z);
}

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.add(registry, "city", &world);
}
