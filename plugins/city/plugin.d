module plugins.city.plugin;

import plugins.api.api : Api, ENTRY, Registry, Site, Sky;
import blocks = plugins.blocks.blocks;
import plugins.turtle.turtle : Turtle;

immutable float[3] SPAWN = [6, 0, -0.5];

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    blocks.Root root = blocks.rootAt(at, Sky.init, false, false);
    api.tile(api, &blocks.tile, &root, blocks.Root.sizeof);
    at.right().entrance(SPAWN[0], SPAWN[1], SPAWN[2]);
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "city", &world);
}
