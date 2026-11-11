module plugins.backrooms.plugin;

import plugins.api.api : Api, KindTag, Registry, Site, SitePart, Spot, entryOf;
import plugins.api.content : BASE, Content, Dependency, FIRST_VERSION, Manifest, dependencyOn;
import caves = plugins.caves.caves;
import plugins.horospheres.horospheres : BACKROOMS_LOOK;
import layout = plugins.rooms.layout;
import plugins.rooms.levels : rooms;
import plugins.turtle.turtle : Turtle, upright;

immutable Spot SPAWN = Spot(14, 4.5, 0);

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    layout.Root root = layout.Root(at.probeHash(SitePart.vertex));
    api.tile(api, &layout.tile, &root, layout.Root.sizeof);
    api.worldLook(api, BACKROOMS_LOOK);
    caves.carve(api);
    caves.darken(api, KindTag.init, caves.SEALED_UNDER);
    upright(at).entrance(SPAWN.x, SPAWN.y, SPAWN.z + rooms.ground.level);
}

void resolve(const(Content)* content) {
    layout.resolveRooms(content);
    caves.resolveCaves(content);
}

immutable Dependency[6] NEEDS = [dependencyOn(BASE), dependencyOn("connector"), dependencyOn("blocks"), dependencyOn("rooms"), dependencyOn("horospheres"), dependencyOn("caves")];
immutable Manifest MANIFEST = Manifest("backrooms", FIRST_VERSION, NEEDS[], null, &resolve);

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.add(registry, "backrooms", &world);
}
