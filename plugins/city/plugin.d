module plugins.city.plugin;

import plugins.api.api : Api, KindTag, Registry, Site, Spot, entryOf;
import plugins.api.content : BASE, Content, Dependency, FIRST_VERSION, Manifest, dependencyOn;
import blocks = plugins.blocks.blocks;
import caves = plugins.caves.caves;
import plugins.horospheres.horospheres : CITY_LOOK;
import plugins.turtle.turtle : Turtle;

immutable Spot SPAWN = Spot(6, 0, -0.5);

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    blocks.Root root = blocks.rootAt(at);
    api.tile(api, &blocks.tile, &root, blocks.Root.sizeof);
    api.worldLook(api, CITY_LOOK);
    caves.carve(api);
    caves.darken(api, KindTag.init, caves.SEALED_UNDER);
    at.right().entrance(SPAWN.x, SPAWN.y, SPAWN.z);
}

void resolve(const(Content)* content) {
    blocks.resolveBlocks(content);
    caves.resolveCaves(content);
}

immutable Dependency[6] NEEDS = [dependencyOn(BASE), dependencyOn("buildings"), dependencyOn("connector"), dependencyOn("blocks"), dependencyOn("horospheres"), dependencyOn("caves")];
immutable Manifest MANIFEST = Manifest("city", FIRST_VERSION, NEEDS[], null, &resolve);

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.add(registry, "city", &world);
}
