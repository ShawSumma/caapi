module plugins.horospheres.horospheres;

import plugins.api.api : Api, HorosphereForm, Risen, Site, SitePart;
import blocks = plugins.blocks.blocks;
import plugins.connector.connector : Floor, connect, slabFloor, terrainFloor;
import layout = plugins.rooms.layout;
import plugins.horospheres.tree : segment;
import plugins.turtle.turtle : Turtle;

enum Tag : uint {
    wild,
    city,
    backrooms,
    tree,
}

struct Kinds {
    uint wild;
    uint city;
    uint backrooms;
    uint tree;
}

bool isRoutedBy(const(void)* data) {
    return *cast(const(bool)*) data;
}

bool hasRisen(ref const Risen risen) {
    return risen.edges > 0;
}

Floor floorOf(uint tag, int measured) {
    if (tag == Tag.city) {
        return slabFloor(blocks.CITY_GROUND);
    } else if (tag == Tag.backrooms) {
        return slabFloor(layout.GROUND);
    } else {
        return terrainFloor(measured);
    }
}

Floor lowerOf(ref const Risen risen) {
    return floorOf(risen.lower, risen.below);
}

void wildTile(const(Api)* api, Site face, const(Risen)* risen, const(void)* data) {
    if (hasRisen(*risen) && blocks.ownsFoot(Turtle(api, face), *risen)) {
        connect(Turtle(api, risen.foot), *risen, terrainFloor(risen.ground), lowerOf(*risen), isRoutedBy(data));
    }
}

void cityTile(const(Api)* api, Site face, const(Risen)* risen, const(void)* data) {
    blocks.Root root;
    if (hasRisen(*risen)) {
        root = blocks.risenRootAt(Turtle(api, risen.foot), *risen, lowerOf(*risen), isRoutedBy(data));
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
        connect(Turtle(api, risen.foot), *risen, slabFloor(layout.GROUND), lowerOf(*risen), isRoutedBy(data));
    }
}

void treeTile(const(Api)* api, Site base, const(Risen)* risen, const(void)* data) {
    segment(Turtle(api, base), risen.segment);
}

Kinds addKinds(const(Api)* api, double odds, double treeOdds, const(bool)* isRouted) {
    Kinds kinds;
    kinds.wild = api.horosphere(api, odds, HorosphereForm.terrain, Tag.wild, &wildTile, isRouted, bool.sizeof);
    kinds.city = api.horosphere(api, odds, HorosphereForm.bare, Tag.city, &cityTile, isRouted, bool.sizeof);
    kinds.backrooms = api.horosphere(api, odds, HorosphereForm.bare, Tag.backrooms, &backroomsTile, isRouted, bool.sizeof);
    kinds.tree = api.horosphere(api, treeOdds, HorosphereForm.upright, Tag.tree, &treeTile, isRouted, bool.sizeof);
    return kinds;
}
