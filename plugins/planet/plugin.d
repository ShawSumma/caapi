module plugins.planet.plugin;

import plugins.api.api : Api, ENTRY, Registry, Site;
import plugins.horospheres.horospheres : Kinds, addKinds;
import plugins.turtle.turtle : Turtle;

enum double RISE_ODDS = 0.02;
enum double TREE_ODDS = 0.002;
enum int TREE_EDGES = 1;
enum uint TREE_RISE = 2;
immutable float[3] SPAWN = [-14, 12, 0];
immutable bool UNROUTED = false;

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    at.build("road");
    Kinds kinds = addKinds(api, RISE_ODDS, TREE_ODDS, &UNROUTED);
    api.rooted(api, kinds.wild);
    Turtle tree = at.right().forward(TREE_EDGES);
    api.openHorosphere(api, tree.site, kinds.tree, TREE_RISE);
    tree.entrance(SPAWN[0], SPAWN[1], SPAWN[2]);
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "planet", &world);
}
