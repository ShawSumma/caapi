module plugins.horospheres.horospheres;

import plugins.api.api : Api, HorosphereForm, KindId, Risen, Site, SitePart, Tile, tagNamed;
import plugins.api.content : Content;
import blocks = plugins.blocks.blocks;
import plugins.connector.connector : Connection, connect;
import layout = plugins.rooms.layout;
import plugins.horospheres.tree : Trunk, resolveTree, segment;
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

Connection connectionOf(const(void)* data) {
    return *cast(const(Connection)*) data;
}

void wildTile(const(Api)* api, Site face, const(Risen)* risen, const(void)* data) {
    if (risen.hasRisen) {
        bool owner = blocks.probeOwnsFoot(Turtle(api, face), *risen);
        if (owner) {
            connect(Turtle(api, risen.foot), *risen, WILD_TAG, connectionOf(data));
        }
    }
}

void cityTile(const(Api)* api, Site face, const(Risen)* risen, const(void)* data) {
    blocks.Root root;
    if (risen.hasRisen) {
        root = blocks.risenRootAt(Turtle(api, risen.foot), *risen, CITY_TAG, connectionOf(data));
    }
    blocks.tileAt(Turtle(api, face), root);
}

void backroomsTile(const(Api)* api, Site face, const(Risen)* risen, const(void)* data) {
    Turtle at = Turtle(api, face);
    layout.Root root;
    if (risen.hasRisen) {
        root = layout.Root(Turtle(api, risen.foot).probeHash(SitePart.vertex), layout.Shaft.open);
    }
    layout.tileAt(at, root);
    if (risen.hasRisen) {
        bool owner = blocks.probeOwnsFoot(at, *risen);
        if (owner) {
            connect(Turtle(api, risen.foot), *risen, BACKROOMS_TAG, connectionOf(data));
        }
    }
}

void treeTile(const(Api)* api, Site base, const(Risen)* risen, const(void)* data) {
    segment(Turtle(api, base), risen.segment, risen.ground, Trunk.bare);
}

struct Wild {
    Tile tile;
    const(void)* data;
    size_t size;
}

Kinds addKinds(const(Api)* api, double odds, double treeOdds, const(Connection)* how) {
    return addKindsOn(api, odds, treeOdds, how, Wild(&wildTile, how, Connection.sizeof));
}

Kinds addKindsOn(const(Api)* api, double odds, double treeOdds, const(Connection)* how, Wild wild) {
    Kinds kinds;
    kinds.wild = api.horosphere(api, odds, HorosphereForm.terrain, WILD_TAG, wild.tile, wild.data, wild.size);
    kinds.city = api.horosphere(api, odds, HorosphereForm.solid, CITY_TAG, &cityTile, how, Connection.sizeof);
    kinds.backrooms = api.horosphere(api, odds, HorosphereForm.solid, BACKROOMS_TAG, &backroomsTile, how, Connection.sizeof);
    kinds.tree = api.horosphere(api, treeOdds, HorosphereForm.upright, TREE_TAG, &treeTile, how, Connection.sizeof);
    api.look(api, kinds.wild, WILD_LOOK);
    api.look(api, kinds.city, CITY_LOOK);
    api.look(api, kinds.backrooms, BACKROOMS_LOOK);
    return kinds;
}
