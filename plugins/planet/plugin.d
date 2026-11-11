module plugins.planet.plugin;

import plugins.api.api : Api, KindTag, Registry, Risen, Site, SitePart, Spot, entryOf, tagNamed;
import plugins.api.binding : settingsOf;
import plugins.api.content : BASE, Content, Dependency, FIRST_VERSION, Manifest, dependencyOn;
import blocks = plugins.blocks.blocks;
import caves = plugins.caves.caves;
import plugins.connector.connector : Connection;
import plugins.horospheres.horospheres : BACKROOMS_TAG, CITY_TAG, Kinds, WILD_LOOK, WILD_TAG, Wild, addKindsOn, resolveHorospheres, wildTile;
import lattice = plugins.lattice.lattice;
import plugins.turtle.turtle : Hashes, Turtle, cornersOf;

enum int TREE_EDGES = 1;
enum uint TREE_RISE = 2;
enum int LANDMARK_RINGS = 3;
enum int SINK_EDGES = 2;
enum uint LIBRARY_TAG = tagNamed("library:library");
enum uint VAULT_TAG = tagNamed("vaults:vaults");
immutable uint[3] BUILT_TAGS = [CITY_TAG, BACKROOMS_TAG, VAULT_TAG];
immutable uint[2] HOLLOW_TAGS = [WILD_TAG, VAULT_TAG];
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

struct Clear {
    Hashes faces;
    Hashes vertices;

    void keepFace(Turtle face) {
        faces.add(face.probeHash(SitePart.face));
        foreach (corner; cornersOf(face)) {
            vertices.add(corner.probeHash(SitePart.vertex));
        }
    }

    void keepAround(Turtle site) {
        keepFace(site);
        foreach (corner; cornersOf(site)) {
            keepFace(corner.right());
            keepFace(corner.right().right());
            keepFace(corner.left());
        }
    }
}

struct Ground {
    Connection how;
    Hashes clear;
}

void landmarks(const(Api)* api, Turtle at, ref Clear clear) {
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
        clear.keepAround(site);
    }
}

bool probeOpen(Turtle face, ref const Risen risen) {
    foreach (corner; cornersOf(face)) {
        bool taken = blocks.probeTaken(corner, risen);
        if (taken) {
            return false;
        }
    }
    return true;
}

void groundTile(const(Api)* api, Site face, const(Risen)* risen, const(void)* data) {
    const(Ground)* ground = cast(const(Ground)*) data;
    wildTile(api, face, risen, &ground.how);
    Turtle at = Turtle(api, face);
    ulong hash = at.probeHash(SitePart.face);
    if (!ground.clear.contains(hash)) {
        bool grown = lattice.probeGrove(at, tuning.groveShare);
        if (grown) {
            bool open = probeOpen(at, *risen);
            if (open) {
                lattice.grove(at);
            }
        }
    }
}

void sink(const(Api)* api, Turtle at, ref const Clear clear) {
    caves.Root root;
    root.blocked = clear.vertices;
    caves.Entry entry = caves.entryNear(at.right().forward(SINK_EDGES).right().forward(SINK_EDGES), root.blocked);
    if (entry.found == caves.Found.some) {
        root.spawn = entry.surface.frame.probeHash(SitePart.vertex);
        api.flatten(api, entry.surface.frame.site);
    }
    api.tileEdges(api, &underground, &root, caves.Root.sizeof);
    api.edgeCeiling(api, caves.SURFACE_BAND);
    api.ports(api, caves.tuning.portOdds);
    caves.darken(api, KindTag.init, caves.OPEN_UNDER);
    caves.darken(api, KindTag.of(WILD_TAG), caves.OPEN_UNDER);
    foreach (tag; BUILT_TAGS) {
        caves.darken(api, KindTag.of(tag), caves.SEALED_UNDER);
    }
    api.crust(api, KindTag.init, tuning.rootCrust);
    api.thinCrust(api, KindTag.init, tuning.rootThinCrust);
    api.abyss(api, KindTag.init, tuning.rootAbyss);
    lattice.deepen(api, KindTag.init);
    foreach (tag; HOLLOW_TAGS) {
        api.crust(api, KindTag.of(tag), tuning.risenCrust);
        api.abyss(api, KindTag.of(tag), tuning.risenAbyss);
        lattice.deepen(api, KindTag.of(tag));
    }
}

double abyssUnder(ref const Risen risen) {
    if (risen.hasRisen) {
        return tuning.risenAbyss;
    } else {
        return tuning.rootAbyss;
    }
}

void underground(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    if (risen.tag != KindTag.of(LIBRARY_TAG)) {
        caves.tile(api, site, risen, data);
    }
    lattice.hang(Turtle(api, site), abyssUnder(*risen));
}

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    at.build("road");
    Clear clear;
    clear.keepAround(at);
    landmarks(api, at, clear);
    Ground ground = Ground(CONNECTION, clear.faces);
    Kinds kinds = addKindsOn(api, tuning.riseOdds, tuning.treeOdds, &CONNECTION, Wild(&groundTile, &ground, Ground.sizeof));
    api.rooted(api, kinds.wild);
    api.risingKinds(api, tuning.riseOdds);
    api.worldLook(api, WILD_LOOK);
    Turtle tree = at.right().forward(TREE_EDGES);
    api.openHorosphere(api, tree.site, kinds.tree, TREE_RISE);
    tree.entrance(SPAWN.x, SPAWN.y, SPAWN.z);
    sink(api, at, clear);
}

immutable Dependency[9] NEEDS = [dependencyOn(BASE), dependencyOn("road"), dependencyOn("buildings"), dependencyOn("connector"), dependencyOn("blocks"), dependencyOn("rooms"), dependencyOn("horospheres"), dependencyOn("caves"), dependencyOn("lattice")];
struct Tuning {
    double riseOdds;
    double treeOdds;
    double groveShare;
    double rootCrust;
    double rootThinCrust;
    double risenCrust;
    double rootAbyss;
    double risenAbyss;
}

__gshared Tuning tuning;

void resolve(const(Content)* content) {
    resolveHorospheres(content);
    caves.resolveCaves(content);
    lattice.resolveLattice(content);
    tuning = content.settingsOf!Tuning("planet");
}

immutable Manifest MANIFEST = Manifest("planet", FIRST_VERSION, NEEDS[], null, &resolve, null, import("plugins/planet/settings.conf"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.add(registry, "planet", &world);
}
