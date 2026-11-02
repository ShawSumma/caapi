module plugins.horospheres.horospheres;

import plugins.api.api : Api, HorosphereForm, Look, Risen, Site, SitePart;
import blocks = plugins.blocks.blocks;
import plugins.connector.connector : Connection, Tag, connect;
import layout = plugins.rooms.layout;
import plugins.horospheres.tree : segment;
import plugins.turtle.turtle : Turtle;

struct Kinds {
    uint wild;
    uint city;
    uint backrooms;
    uint tree;
}

immutable Look WILD_LOOK = Look("wild");
immutable Look CITY_LOOK = Look("city", [0.74f, 0.79f, 0.86f], true);
immutable Look BACKROOMS_LOOK = Look("backrooms", [0.78f, 0.72f, 0.45f], true);

Connection connectionOf(const(void)* data) {
    return *cast(const(Connection)*) data;
}

bool hasRisen(ref const Risen risen) {
    return risen.edges > 0;
}

void wildTile(const(Api)* api, Site face, const(Risen)* risen, const(void)* data) {
    if (hasRisen(*risen) && blocks.ownsFoot(Turtle(api, face), *risen)) {
        connect(Turtle(api, risen.foot), *risen, Tag.wild, connectionOf(data));
    }
}

void cityTile(const(Api)* api, Site face, const(Risen)* risen, const(void)* data) {
    blocks.Root root;
    if (hasRisen(*risen)) {
        root = blocks.risenRootAt(Turtle(api, risen.foot), *risen, connectionOf(data));
    }
    blocks.tileAt(Turtle(api, face), root);
}

void backroomsTile(const(Api)* api, Site face, const(Risen)* risen, const(void)* data) {
    Turtle at = Turtle(api, face);
    layout.Root root;
    if (hasRisen(*risen)) {
        root = layout.Root(Turtle(api, risen.foot).hash(SitePart.vertex), true, false);
    }
    layout.tileAt(at, root);
    if (hasRisen(*risen) && blocks.ownsFoot(at, *risen)) {
        connect(Turtle(api, risen.foot), *risen, Tag.backrooms, connectionOf(data));
    }
}

void treeTile(const(Api)* api, Site base, const(Risen)* risen, const(void)* data) {
    segment(Turtle(api, base), risen.segment);
}

Kinds addKinds(const(Api)* api, double odds, double treeOdds, const(Connection)* how) {
    Kinds kinds;
    kinds.wild = api.horosphere(api, odds, HorosphereForm.terrain, Tag.wild, &wildTile, how, Connection.sizeof);
    kinds.city = api.horosphere(api, odds, HorosphereForm.bare, Tag.city, &cityTile, how, Connection.sizeof);
    kinds.backrooms = api.horosphere(api, odds, HorosphereForm.bare, Tag.backrooms, &backroomsTile, how, Connection.sizeof);
    kinds.tree = api.horosphere(api, treeOdds, HorosphereForm.upright, Tag.tree, &treeTile, how, Connection.sizeof);
    api.look(api, kinds.wild, &WILD_LOOK);
    api.look(api, kinds.city, &CITY_LOOK);
    api.look(api, kinds.backrooms, &BACKROOMS_LOOK);
    return kinds;
}
