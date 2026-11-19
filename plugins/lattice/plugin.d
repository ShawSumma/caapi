module plugins.lattice.plugin;

import plugins.api.api : Api, HorosphereForm, KindId, Registry, Site, SitePart, Spot, entryOf, tagNamed;
import plugins.api.content : FIRST_VERSION, Manifest, ON_BASE;
import plugins.lattice.lattice : LOOK, Root, branch, colossus, drift, edge, hang, resolveLattice, stars, tuning;
import plugins.turtle.turtle : Lie, Turtle, upright;

enum uint LATTICE_TAG = tagNamed("lattice:lattice");
immutable Spot SPAWN = Spot(21, 2, -3);

void world(const(Api)* api, Site at, const(void)* data) {
    Turtle root = Turtle(api, at);
    Root lattice = Root(root.probeHash(SitePart.vertex));
    KindId kind = api.horosphere(api, 0, HorosphereForm.bare, LATTICE_TAG, null, null, 0);
    api.rooted(api, kind);
    api.invertGravity(api);
    api.fog(api, tuning.fog);
    api.worldLook(api, LOOK);
    api.tileEdges(api, &edge, &lattice, Root.sizeof);
    upright(root).entrance(SPAWN.x, SPAWN.y, SPAWN.z);
}

void voidOf(alias fill)(const(Api)* api, Site edge, double near, double far, double abyss) {
    fill(Turtle(api, edge), Lie(near, far), abyss);
}

immutable Manifest MANIFEST = Manifest("lattice", FIRST_VERSION, ON_BASE[], null, &resolveLattice, null, import("plugins/lattice/settings.conf"), import("plugins/lattice/lattice.decl"), import("plugins/lattice/lattice.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.add(registry, "lattice", &world);
    registry.addVoid(registry, "lattice:hang", &voidOf!hang);
    registry.addVoid(registry, "lattice:drift", &voidOf!drift);
    registry.addVoid(registry, "lattice:branch", &voidOf!branch);
    registry.addVoid(registry, "lattice:stars", &voidOf!stars);
    registry.addVoid(registry, "lattice:colossus", &voidOf!colossus);
}
