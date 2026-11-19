module plugins.city.plugin;

import plugins.api.api : Api, HorosphereForm, KindId, KindTag, Registry, Site, Spot, entryOf, typedTile;
import plugins.api.content : BASE, Dependency, FIRST_VERSION, Manifest, dependencyOn;
import blocks = plugins.blocks.blocks;
import plugins.horospheres.horospheres : CITY_LOOK, CITY_TAG;
import plugins.turtle.turtle : Turtle;

immutable Spot SPAWN = Spot(6, 0, -0.5);

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    blocks.Root root = blocks.rootAt(at);
    KindId kind = api.horosphere(api, 0, HorosphereForm.solid, CITY_TAG, &typedTile!(blocks.tile, blocks.Root), &root, blocks.Root.sizeof);
    api.rooted(api, kind);
    api.portRule(api, KindTag.of(CITY_TAG), blocks.mostPortShare(), &blocks.portAt, null, 0);
    api.worldLook(api, CITY_LOOK);
    at.build("underground");
    at.right().entrance(SPAWN.x, SPAWN.y, SPAWN.z);
}

immutable Dependency[6] NEEDS = [dependencyOn(BASE), dependencyOn("buildings"), dependencyOn("connector"), dependencyOn("blocks"), dependencyOn("horospheres"), dependencyOn("caves")];
immutable Manifest MANIFEST = Manifest("city", FIRST_VERSION, NEEDS[], null, &blocks.resolveBlocks);

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.add(registry, "city", &world);
}
