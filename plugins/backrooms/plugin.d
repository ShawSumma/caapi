module plugins.backrooms.plugin;

import plugins.api.api : Api, HorosphereForm, KindId, KindTag, Registry, Site, SitePart, Spot, entryOf, typedTile;
import plugins.api.content : BASE, Dependency, FIRST_VERSION, Manifest, dependencyOn;
import plugins.horospheres.horospheres : BACKROOMS_LOOK, BACKROOMS_TAG;
import layout = plugins.rooms.layout;
import plugins.rooms.levels : rooms;
import plugins.turtle.turtle : Turtle, upright;

immutable Spot SPAWN = Spot(14, 4.5, 0);

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    layout.Root root = layout.Root(at.probeHash(SitePart.vertex));
    KindId kind = api.horosphere(api, 0, HorosphereForm.solid, BACKROOMS_TAG, &typedTile!(layout.tile, layout.Root), &root, layout.Root.sizeof);
    api.rooted(api, kind);
    api.portRule(api, KindTag.of(BACKROOMS_TAG), layout.mostWellShare(), &layout.portAt, null, 0);
    api.tileReach(api, KindTag.of(BACKROOMS_TAG), layout.reachAbove(), layout.reachBelow());
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
