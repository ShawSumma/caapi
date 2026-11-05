module plugins.trail.plugin;

import plugins.api.api : Api, Look, Material, Registry, Site, SitePart, Span, entryOf;
import box = plugins.box.box;
import plugins.turtle.turtle : Turtle, boxOf;

immutable Look LOOK = Look("trail");

enum int HALF_WIDTH = 2;
enum uint HUT_EVERY = 3;
enum float ROUTE_LANE = 0.5f;
enum uint TURNS = 3;
enum int LANDMARK_SEGMENTS = 12;

enum Extent : ubyte {
    endless,
    counted,
}

struct Length {
    int left;
    Extent extent;

    bool isDone() const {
        return extent == Extent.counted && left == 0;
    }

    Length next() const {
        return Length(left - 1, extent);
    }
}

void pave(Turtle segment) {
    int length = segment.edgeCells();
    segment.paint(Material.gravel, boxOf(Span(-HALF_WIDTH, HALF_WIDTH - 1), Span(-1, -1), Span(-HALF_WIDTH, length + HALF_WIDTH - 1)));
    segment.stop(ROUTE_LANE, 0, length / 2.0f);
}

void hut(const(Api)* api, Site site, const(void)* data) {
    box.hut(Turtle(api, site).pitchUp());
}

void addHut(Turtle tip) {
    Turtle yard = tip.right().forward(1);
    bool claimed = yard.probeClaimed(SitePart.vertex);
    if (!claimed) {
        bool placed = yard.left().place(&hut, null, 0);
        if (placed) {
            yard.claim(SitePart.vertex);
        }
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

bool extend(Turtle segment, Length length) {
    Turtle ahead = segment.forward(1);
    bool placed = false;
    bool claimed = ahead.probeClaimed(SitePart.vertex);
    if (!claimed) {
        placed = segment.place(&stretch, &length, Length.sizeof);
    }
    if (placed) {
        ahead.claim(SitePart.vertex);
    }
    return placed;
}

void stretch(const(Api)* api, Site site, const(void)* data) {
    Length length = *cast(const(Length)*) data;
    Turtle segment = Turtle(api, site);
    segment.claim(SitePart.vertex);
    segment.forward(1).claim(SitePart.vertex);
    pave(segment);
    Turtle tip = segment.forward(1);
    ulong edge = segment.probeHash(SitePart.edge);
    if (edge % HUT_EVERY == 0) {
        addHut(tip);
    }
    if (!length.isDone) {
        uint first = segment.pick(TURNS);
        uint tried = 0;
        bool extended = false;
        while (tried < TURNS && !extended) {
            extended = extend(turnedTo(tip, (first + tried) % TURNS), length.next);
            tried += 1;
        }
    }
}

void landmark(const(Api)* api, Site site, const(void)* data) {
    Length length = Length(LANDMARK_SEGMENTS, Extent.counted);
    stretch(api, site, &length);
}

void world(const(Api)* api, Site site, const(void)* data) {
    Length length = Length(0, Extent.endless);
    api.worldLook(api, &LOOK);
    stretch(api, site, &length);
}

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.add(registry, "trail", &world);
    registry.addLandmark(registry, "trail", &landmark);
}
