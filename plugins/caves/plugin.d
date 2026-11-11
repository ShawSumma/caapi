module plugins.caves.plugin;

import plugins.api.api : Api, HorosphereForm, KindId, Registry, Site, SitePart, entryOf, tagNamed;
import plugins.api.content : FIRST_VERSION, Manifest, ON_BASE;
import plugins.caves.caves : Entry, Found, LOOK, NAME, Root, enter, entryNear, resolveCaves, route, tile, tuning, underlie;
import plugins.turtle.turtle : Turtle;

enum uint CAVE_TAG = tagNamed("caves:caves");

void world(const(Api)* api, Site site, const(void)* data) {
    KindId kind = api.horosphere(api, 0, HorosphereForm.terrain, CAVE_TAG, null, null, 0);
    api.rooted(api, kind);
    api.look(api, kind, LOOK);
    api.worldLook(api, LOOK);
    api.fog(api, tuning.fog);
    Root root;
    Entry entry = entryNear(Turtle(api, site), root.blocked);
    if (entry.found == Found.none) {
        api.fail(api, "no sinkhole near the root opens into a branching cave");
    } else {
        root.spawn = entry.surface.frame.probeHash(SitePart.vertex);
        api.tileEdges(api, &tile, &root, Root.sizeof);
        api.flatten(api, entry.surface.frame.site);
        route(entry);
        enter(entry);
    }
}

void underground(const(Api)* api, Site site, const(void)* data) {
    underlie(api);
}

immutable Manifest MANIFEST = Manifest(NAME, FIRST_VERSION, ON_BASE[], null, &resolveCaves, null, import("plugins/caves/settings.conf"), import("plugins/caves/caves.decl"), import("plugins/caves/caves.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.add(registry, "caves", &world);
    registry.addDebug(registry, "underground", &underground);
}
