module plugins.planet.plugin;

import plugins.api.api : Api, Registry, Site, Spot, entryOf;
import plugins.api.binding : settingsOf;
import plugins.api.content : BASE, Content, Dependency, FIRST_VERSION, Manifest, dependencyOn;
import plugins.connector.connector : Connection;
import plugins.horospheres.horospheres : Kinds, WILD_LOOK, addKinds, resolveHorospheres;
import plugins.turtle.turtle : Turtle;

enum int TREE_EDGES = 1;
enum uint TREE_RISE = 2;
enum int LANDMARK_RINGS = 3;
immutable Spot SPAWN = Spot(-14, 12, 0);
immutable Connection CONNECTION = Connection.rolled();

struct LandmarkSites {
    Turtle[4] arms;
    uint next;

    Turtle take() {
        uint arm = next % arms.length;
        Turtle site = arms[arm];
        if (next / arms.length % 2 == 0) {
            arms[arm] = site.forward(2).right();
        } else {
            arms[arm] = site.forward(2).left();
        }
        next += 1;
        return site;
    }
}

void landmarks(const(Api)* api, Turtle at) {
    Turtle ahead = at.forward(2).left();
    Turtle behind = at.left().left().forward(2).right();
    Turtle aside = at.left().forward(2);
    Turtle beyond = at.right().forward(5).right();
    LandmarkSites sites = LandmarkSites([ahead.forward(1), behind.forward(1), aside, beyond]);
    foreach (index; 0 .. LANDMARK_RINGS * cast(uint) sites.arms.length) {
        Turtle site = sites.take();
        bool placed = api.landmark(api, index, site.site);
        if (!placed) {
            return;
        }
        api.flatten(api, site.site);
    }
}

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    at.build("road");
    Kinds kinds = addKinds(api, tuning.riseOdds, tuning.treeOdds, &CONNECTION);
    api.rooted(api, kinds.wild);
    api.risingKinds(api, tuning.riseOdds);
    api.worldLook(api, WILD_LOOK);
    Turtle tree = at.right().forward(TREE_EDGES);
    api.openHorosphere(api, tree.site, kinds.tree, TREE_RISE);
    tree.entrance(SPAWN.x, SPAWN.y, SPAWN.z);
    landmarks(api, at);
}

immutable Dependency[7] NEEDS = [dependencyOn(BASE), dependencyOn("road"), dependencyOn("buildings"), dependencyOn("connector"), dependencyOn("blocks"), dependencyOn("rooms"), dependencyOn("horospheres")];
struct Tuning {
    double riseOdds;
    double treeOdds;
}

__gshared Tuning tuning;

void resolve(const(Content)* content) {
    resolveHorospheres(content);
    tuning = content.settingsOf!Tuning("planet");
}

immutable Manifest MANIFEST = Manifest("planet", FIRST_VERSION, NEEDS[], null, &resolve, null, import("plugins/planet/settings.conf"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.add(registry, "planet", &world);
}
