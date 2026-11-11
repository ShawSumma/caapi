module plugins.road.plugin;

import core.stdc.math : fabs, floor, sqrt;
import plugins.api.api : Api, Material, Registry, Rhythm, Site, Span, entryOf;
import plugins.api.binding : bound;
import plugins.api.content : Content, FIRST_VERSION, Manifest, ON_BASE;
import plugins.turtle.turtle : Turtle, alongLine, boxOf, higherOf;

enum string LOOK = "base:sky";

enum int HALF_WIDTH = 6;
enum int DECK = 2;
enum int PARAPET = 1;
enum int INNER_HALF_WIDTH = HALF_WIDTH - 1;
enum int PIER_HALF_WIDTH = 2;
enum int PIER_EDGES = 8;
enum int CROWN = -2;
enum Rhythm DASHES = Rhythm(8, 2, 4);
enum float ROUTE_STOP_CELLS = 12;
enum int ROUTE_STOPS = 5;
enum float ROUTE_LANE = 0;
enum size_t MOST_EDGE_CELLS = 64;

struct Materials {
    Material surface;
    Material stripe;
    Material deck;
    Material parapet;
    Material masonry;
    Material ring;
}

__gshared Materials materials;

void resolve(const(Content)* content) {
    materials = content.bound!Materials("road:materials");
}

struct ArchRow {
    int from;
    int span;
    int soffit;
    int ring;
}

struct ArchRows {
    ArchRow[MOST_EDGE_CELLS] rows;
    size_t count;
}

int[MOST_EDGE_CELLS] soffits(int edge, int below) {
    int[MOST_EDGE_CELLS] heights;
    double halfSpan = edge / 2.0 - PIER_HALF_WIDTH;
    double rise = CROWN - below;
    foreach (offset; PIER_HALF_WIDTH .. edge - PIER_HALF_WIDTH) {
        double fromMiddle = fabs(offset + 0.5 - edge / 2.0);
        double ratio = fromMiddle / halfSpan;
        double sag = rise * (1 - sqrt(1 - ratio * ratio));
        heights[offset] = CROWN - cast(int) floor(sag + 0.5);
    }
    return heights;
}

ArchRows archRows(int edge, int below) {
    int[MOST_EDGE_CELLS] heights = soffits(edge, below);
    ArchRows found;
    foreach (offset; PIER_HALF_WIDTH .. edge - PIER_HALF_WIDTH) {
        int inner = offset + 1;
        if (offset + 0.5 > edge / 2.0) {
            inner = offset - 1;
        }
        int soffit = heights[offset];
        int ring = higherOf(soffit, heights[inner]);
        if (found.count > 0 && found.rows[found.count - 1].soffit == soffit && found.rows[found.count - 1].ring == ring) {
            found.rows[found.count - 1].span += 1;
        } else {
            found.rows[found.count] = ArchRow(offset, 1, soffit, ring);
            found.count += 1;
        }
    }
    return found;
}

void arches(Turtle road, int below) {
    int edge = road.edgeCells();
    Span width = Span(-INNER_HALF_WIDTH, INNER_HALF_WIDTH - 1);
    ArchRows found = archRows(edge, below);
    foreach (row; found.rows[0 .. found.count]) {
        Rhythm rhythm = Rhythm(edge, row.from, row.span);
        road.fill(materials.masonry, alongLine(width, Span(row.soffit, -1)), rhythm);
        road.fill(materials.ring, alongLine(width, Span(row.soffit, row.ring)), rhythm);
    }
}

void pier(const(Api)* api, Site at, const(void)* data) {
    Turtle site = Turtle(api, at);
    int depth = PIER_EDGES * site.edgeCells();
    site.pitchDown().fill(materials.masonry, boxOf(Span(-INNER_HALF_WIDTH, INNER_HALF_WIDTH - 1), Span(-PIER_HALF_WIDTH, PIER_HALF_WIDTH - 1), Span(0, depth - 1)));
    bool placed = site.forward(1).place(&pier, null, 0);
    if (!placed) {
        site.fail("the next pier is behind the road's piers");
    }
}

void world(const(Api)* api, Site at, const(void)* data) {
    Turtle road = Turtle(api, at);
    Span column = road.column();
    Span width = Span(-HALF_WIDTH, HALF_WIDTH - 1);
    Span lanes = Span(-INNER_HALF_WIDTH, INNER_HALF_WIDTH - 1);
    road.paint(Material.none, alongLine(width, Span(DECK, column.high)));
    road.paint(materials.deck, alongLine(width, Span(0, DECK - 1)));
    road.paint(materials.surface, alongLine(lanes, Span(DECK - 1, DECK - 1)));
    road.paint(materials.stripe, alongLine(Span(-1, 0), Span(DECK - 1, DECK - 1)), DASHES);
    road.paint(materials.parapet, alongLine(Span(-HALF_WIDTH, -HALF_WIDTH), Span(DECK - 1, DECK + PARAPET - 1)));
    road.paint(materials.parapet, alongLine(Span(HALF_WIDTH - 1, HALF_WIDTH - 1), Span(DECK - 1, DECK + PARAPET - 1)));
    arches(road, column.low);
    road.place(&pier, null, 0);
    road.left().left().forward(1).place(&pier, null, 0);
    foreach (stop; 0 .. ROUTE_STOPS) {
        road.stop(ROUTE_LANE, DECK, 0.5f + stop * ROUTE_STOP_CELLS);
    }
}

void lookedWorld(const(Api)* api, Site at, const(void)* data) {
    api.worldLook(api, LOOK);
    world(api, at, data);
}

immutable Manifest MANIFEST = Manifest("road", FIRST_VERSION, ON_BASE[], null, &resolve, null, null, import("plugins/road/road.decl"), import("plugins/road/road.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.addDebug(registry, "road", &lookedWorld);
}
