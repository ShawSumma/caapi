module plugins.trail.plugin;

import plugins.api.api : Api, ENTRY, Look, Material, NO_KIND, Registry, Site, SitePart;
import box = plugins.box.box;
import plugins.turtle.turtle : Turtle, boxOf;

immutable Look LOOK = Look("trail");

enum int HALF_WIDTH = 2;
enum uint HUT_EVERY = 3;
enum float ROUTE_LANE = 0.5f;
enum uint TURNS = 3;
enum int ENDLESS = -1;
enum int LANDMARK_SEGMENTS = 12;

void pave(Turtle segment) {
    int length = segment.edgeCells();
    segment.paint(Material.gravel, boxOf([-HALF_WIDTH, HALF_WIDTH - 1], [-1, -1], [-HALF_WIDTH, length + HALF_WIDTH - 1]));
    segment.stop(ROUTE_LANE, 0, length / 2.0f);
}

void hut(const(Api)* api, Site site, const(void)* data) {
    box.hut(Turtle(api, site).pitchUp());
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

bool extend(Turtle segment, int left) {
    Turtle ahead = segment.forward(1);
    if (ahead.isClaimed(SitePart.vertex)) {
        return false;
    } else {
        bool isPlaced = segment.place(&stretch, &left, int.sizeof);
        if (isPlaced) {
            ahead.claim(SitePart.vertex);
        }
        return isPlaced;
    }
}

void stretch(const(Api)* api, Site site, const(void)* data) {
    int left = *cast(const(int)*) data;
    Turtle segment = Turtle(api, site);
    segment.claim(SitePart.vertex);
    segment.forward(1).claim(SitePart.vertex);
    pave(segment);
    Turtle tip = segment.forward(1);
    if (segment.hash(SitePart.edge) % HUT_EVERY == 0) {
        addHut(tip);
    }
    if (left != 0) {
        uint first = segment.pick(TURNS);
        uint tried = 0;
        bool isExtended = false;
        while (tried < TURNS && !isExtended) {
            isExtended = extend(turnedTo(tip, (first + tried) % TURNS), left - 1);
            tried += 1;
        }
    }
}

// A placed structure is never forgotten and grows with the deepest depth reached anywhere, so one sharing a world with
// everything else has to be finite.
void landmark(const(Api)* api, Site site, const(void)* data) {
    int left = LANDMARK_SEGMENTS;
    stretch(api, site, &left);
}

void world(const(Api)* api, Site site, const(void)* data) {
    int left = ENDLESS;
    api.look(api, NO_KIND, &LOOK);
    stretch(api, site, &left);
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "trail", &world);
    registry.addLandmark(registry, "trail", &landmark);
}
