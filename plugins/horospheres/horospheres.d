module plugins.horospheres.horospheres;

import plugins.api.api : Api, Color, HorosphereForm, KindId, Look, Risen, Site, SitePart, Tint;
import blocks = plugins.blocks.blocks;
import plugins.connector.connector : Connection, Tag, connect;
import layout = plugins.rooms.layout;
import plugins.horospheres.tree : Trunk, segment;
import plugins.turtle.turtle : Turtle;

struct Kinds {
    KindId wild;
    KindId city;
    KindId backrooms;
    KindId tree;
}

immutable Look WILD_LOOK = Look("wild");
immutable Look CITY_LOOK = Look("city", Color(0.74f, 0.79f, 0.86f), Tint.fog);
immutable Look BACKROOMS_LOOK = Look("backrooms", Color(0.78f, 0.72f, 0.45f), Tint.fog);

Connection connectionOf(const(void)* data) {
    return *cast(const(Connection)*) data;
}

void wildTile(const(Api)* api, Site face, const(Risen)* risen, const(void)* data) {
    if (risen.hasRisen) {
        bool owner = blocks.probeOwnsFoot(Turtle(api, face), *risen);
        if (owner) {
            connect(Turtle(api, risen.foot), *risen, Tag.wild, connectionOf(data));
        }
    }
}

void cityTile(const(Api)* api, Site face, const(Risen)* risen, const(void)* data) {
    blocks.Root root;
    if (risen.hasRisen) {
        root = blocks.risenRootAt(Turtle(api, risen.foot), *risen, connectionOf(data));
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
            connect(Turtle(api, risen.foot), *risen, Tag.backrooms, connectionOf(data));
        }
    }
}

void treeTile(const(Api)* api, Site base, const(Risen)* risen, const(void)* data) {
    segment(Turtle(api, base), risen.segment, risen.ground, Trunk.bare);
}

Kinds addKinds(const(Api)* api, double odds, double treeOdds, const(Connection)* how) {
    Kinds kinds;
    kinds.wild = api.horosphere(api, odds, HorosphereForm.terrain, Tag.wild, &wildTile, how, Connection.sizeof);
    kinds.city = api.horosphere(api, odds, HorosphereForm.solid, Tag.city, &cityTile, how, Connection.sizeof);
    kinds.backrooms = api.horosphere(api, odds, HorosphereForm.solid, Tag.backrooms, &backroomsTile, how, Connection.sizeof);
    kinds.tree = api.horosphere(api, treeOdds, HorosphereForm.upright, Tag.tree, &treeTile, how, Connection.sizeof);
    api.look(api, kinds.wild, &WILD_LOOK);
    api.look(api, kinds.city, &CITY_LOOK);
    api.look(api, kinds.backrooms, &BACKROOMS_LOOK);
    return kinds;
}
