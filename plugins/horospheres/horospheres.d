module plugins.horospheres.horospheres;

import plugins.api.api : Api, HorosphereForm, KindId, KindTag, Risen, Site, SitePart, tagNamed, typedTile;
import plugins.api.content : Content;
import blocks = plugins.blocks.blocks;
import plugins.connector.connector : Connection, footTile;
import plugins.horospheres.tree : Trunk, resolveTree, segment;
import layout = plugins.rooms.layout;
import plugins.turtle.turtle : Turtle;

void resolveHorospheres(const(Content)* content) {
    blocks.resolveBlocks(content);
    layout.resolveRooms(content);
    resolveTree(content);
}

enum uint WILD_TAG = tagNamed("horospheres:wild");
enum uint CITY_TAG = tagNamed("horospheres:city");
enum uint BACKROOMS_TAG = tagNamed("horospheres:backrooms");
enum uint TREE_TAG = tagNamed("horospheres:tree");

struct Kinds {
    KindId wild;
    KindId city;
    KindId backrooms;
    KindId tree;
}

enum string WILD_LOOK = "base:sky";
enum string CITY_LOOK = "horospheres:city";
enum string BACKROOMS_LOOK = "horospheres:backrooms";

void cityTile(const(Api)* api, Site face, ref const Risen risen, ref const Connection how) {
    blocks.Root root;
    if (risen.hasRisen) {
        root = blocks.risenRootAt(Turtle(api, risen.foot), risen, CITY_TAG, how);
    }
    blocks.tileAt(Turtle(api, face), root);
}

void backroomsTile(const(Api)* api, Site face, ref const Risen risen, ref const Connection how) {
    Turtle at = Turtle(api, face);
    layout.Root root;
    if (risen.hasRisen) {
        root = layout.Root(Turtle(api, risen.foot).probeHash(SitePart.vertex), layout.Shaft.open);
    }
    layout.tileAt(at, root);
}

void treeTile(const(Api)* api, Site base, ref const Risen risen, ref const Connection how) {
    segment(Turtle(api, base), risen.segment, risen.ground, Trunk.bare);
}

Kinds addKinds(const(Api)* api, double odds, double treeOdds, const(Connection)* how) {
    Kinds kinds;
    kinds.wild = api.horosphere(api, odds, HorosphereForm.terrain, WILD_TAG, null, null, 0);
    kinds.city = api.horosphere(api, odds, HorosphereForm.solid, CITY_TAG, &typedTile!(cityTile, Connection), how, Connection.sizeof);
    kinds.backrooms = api.horosphere(api, odds, HorosphereForm.solid, BACKROOMS_TAG, &typedTile!(backroomsTile, Connection), how, Connection.sizeof);
    kinds.tree = api.horosphere(api, treeOdds, HorosphereForm.upright, TREE_TAG, &typedTile!(treeTile, Connection), how, Connection.sizeof);
    api.foot(api, WILD_TAG, &footTile, how, Connection.sizeof);
    api.foot(api, BACKROOMS_TAG, &footTile, how, Connection.sizeof);
    api.portRule(api, KindTag.of(CITY_TAG), blocks.mostPortShare(), &blocks.portAt, null, 0);
    api.portRule(api, KindTag.of(BACKROOMS_TAG), layout.mostWellShare(), &layout.portAt, null, 0);
    api.tileReach(api, KindTag.of(BACKROOMS_TAG), layout.reachAbove(), layout.reachBelow());
    api.look(api, kinds.wild, WILD_LOOK);
    api.look(api, kinds.city, CITY_LOOK);
    api.look(api, kinds.backrooms, BACKROOMS_LOOK);
    return kinds;
}
