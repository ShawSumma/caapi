module plugins.trail.plugin;

import plugins.api.api : Api, ENTRY, Material, Registry, Site, SitePart;
import box = plugins.box.box;
import plugins.turtle.turtle : Turtle, boxOf;

enum int HALF_WIDTH = 2;
enum uint HUT_EVERY = 3;
enum int HUT_STORIES = 2;
enum float ROUTE_LANE = 0.5f;
enum uint TURNS = 3;
immutable box.Palette TIMBER = box.Palette(Material.oakWood, Material.woodPlanks, Material.spruceWood);

void pave(Turtle segment) {
    int length = segment.edgeCells();
    segment.paint(Material.gravel, boxOf([-HALF_WIDTH, HALF_WIDTH - 1], [-1, -1], [-HALF_WIDTH, length + HALF_WIDTH - 1]));
    segment.stop(ROUTE_LANE, 0, length / 2.0f);
}

void hut(const(Api)* api, Site site, const(void)* data) {
    Turtle tower = Turtle(api, site).pitchUp();
    box.tower(tower, HUT_STORIES * box.STORY, TIMBER);
    box.door(tower);
}

void addHut(Turtle tip) {
    Turtle yard = tip.right().forward(1);
    if (!yard.isClaimed(SitePart.vertex) && yard.left().place(&hut, null, 0)) {
        yard.claim(SitePart.vertex);
    }
}

Turtle turnedTo(Turtle tip, uint turn) {
    if (turn == 0) {
        return tip;
    } else if (turn == 1) {
        return tip.left();
    } else {
        return tip.right();
    }
}

bool extend(Turtle segment) {
    Turtle ahead = segment.forward(1);
    if (ahead.isClaimed(SitePart.vertex)) {
        return false;
    } else {
        immutable bool isPlaced = segment.place(&world, null, 0);
        if (isPlaced) {
            ahead.claim(SitePart.vertex);
        }
        return isPlaced;
    }
}

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle segment = Turtle(api, site);
    segment.claim(SitePart.vertex);
    segment.forward(1).claim(SitePart.vertex);
    pave(segment);
    Turtle tip = segment.forward(1);
    if (segment.hash(SitePart.edge) % HUT_EVERY == 0) {
        addHut(tip);
    }
    uint first = segment.pick(TURNS);
    uint tried = 0;
    bool isExtended = false;
    while (tried < TURNS && !isExtended) {
        isExtended = extend(turnedTo(tip, (first + tried) % TURNS));
        tried += 1;
    }
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "trail", &world);
}
