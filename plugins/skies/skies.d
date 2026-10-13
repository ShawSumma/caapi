module plugins.skies.skies;

import plugins.api.api : Api, Material, Site, SitePart, Sky;
import blocks = plugins.blocks.blocks;
import layout = plugins.rooms.layout;
import plugins.buildings.building : Bound, Lot, Lots, Palette, Side, Spec, upright;
import plugins.buildings.types : Type, build, palettes, stories;
import plugins.connector.connector : connect;
import plugins.turtle.turtle : Turtle, boxOf;

enum uint SPIRE_PERCENT = 30;
enum int LOT_FRONT = 4;
enum int MEADOW_GROUND = 0;
immutable Type[3] SPIRE_TYPES = [Type.deco, Type.glass, Type.modern];

bool isRoutedBy(const(void)* data) {
    return *cast(const(bool)*) data;
}

void wildSky(const(Api)* api, Site face, const(Sky)* sky, const(void)* data) {
    if (blocks.ownsFoot(Turtle(api, face), *sky)) {
        connect(Turtle(api, sky.foot), *sky, sky.ground, isRoutedBy(data));
    }
}

void citySky(const(Api)* api, Site face, const(Sky)* sky, const(void)* data) {
    blocks.Root root = blocks.rootAt(Turtle(api, sky.foot), *sky, true, isRoutedBy(data));
    blocks.tileAt(Turtle(api, face), root);
}

void backroomsSky(const(Api)* api, Site face, const(Sky)* sky, const(void)* data) {
    Turtle at = Turtle(api, face);
    layout.Root root = layout.Root(Turtle(api, sky.foot).hash(SitePart.vertex), true, false);
    layout.tileAt(at, root);
    if (blocks.ownsFoot(at, *sky)) {
        connect(Turtle(api, sky.foot), *sky, layout.GROUND, isRoutedBy(data));
    }
}

void meadow(ref const Turtle[blocks.AROUND] quarters) {
    foreach (quarter; quarters) {
        Turtle ground = upright(quarter);
        int far = ground.column().high;
        ground.paint(Material.grass, boxOf([0, far], [0, far], [-1, -1]));
    }
}

void spire(Turtle corner) {
    Turtle tower = upright(corner);
    int far = tower.column().high;
    tower.paint(Material.concrete, boxOf([0, far], [0, far], [-1, 0]));
    Type chosen = SPIRE_TYPES[corner.pick(SPIRE_TYPES.length)];
    int[2] range = stories(chosen);
    int count = blocks.fit(corner, range[0] + cast(int) corner.pick(range[1] - range[0] + 1));
    immutable(Palette)[] options = palettes(chosen);
    Spec spec = Spec(count, options[corner.pick(cast(uint) options.length)], LOT_FRONT, 0, 0);
    if (count >= 1) {
        Lot lot;
        lot.site = corner;
        lot.bounds = [Bound.street, Bound.street, Bound.lot, Bound.lot];
        lot.front = Side.yLow;
        lot.hasFront = true;
        Lots lots;
        lots.add(lot);
        build(chosen, lots, spec);
    }
}

void spiresSky(const(Api)* api, Site face, const(Sky)* sky, const(void)* data) {
    foreach (corner; blocks.cornersOf(Turtle(api, face))) {
        Turtle[blocks.AROUND] quarters = blocks.quartersOf(corner);
        if (blocks.isOwner(quarters)) {
            meadow(quarters);
            if (blocks.isFoot(corner, *sky)) {
                connect(Turtle(api, sky.foot), *sky, MEADOW_GROUND, isRoutedBy(data));
            } else if (corner.chance(SPIRE_PERCENT)) {
                spire(corner);
            }
        }
    }
}
