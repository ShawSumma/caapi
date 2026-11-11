module plugins.backrooms.plugin;

import plugins.api.api : Api, Registry, Site, SitePart, Spot, entryOf;
import plugins.api.content : BASE, Dependency, FIRST_VERSION, Manifest, dependencyOn;
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
    at.build("underground");
    upright(at).entrance(SPAWN.x, SPAWN.y, SPAWN.z + rooms.ground.level);
}

immutable Dependency[6] NEEDS = [dependencyOn(BASE), dependencyOn("connector"), dependencyOn("blocks"), dependencyOn("rooms"), dependencyOn("horospheres"), dependencyOn("caves")];
immutable Manifest MANIFEST = Manifest("backrooms", FIRST_VERSION, NEEDS[], null, &layout.resolveRooms);

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.add(registry, "backrooms", &world);
}
