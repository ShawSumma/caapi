module plugins.road.plugin;

import core.stdc.math : fabs, floor, sqrt;
import plugins.api.api : Api, Column, ENTRY, Material, Registry, Rhythm, Site;
import plugins.turtle.turtle : ENDLESS_HIGH, ENDLESS_LOW, Turtle, boxOf, higherOf;

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
enum Material SURFACE = Material.basalt;
enum Material STRIPE = Material.whiteBrick;
enum Material DECK_MATERIAL = Material.greyBrick;
enum Material PARAPET_MATERIAL = Material.concrete;
enum Material MASONRY = Material.greyBrick;
enum Material RING = Material.limestone;

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
    int[2] width = [-INNER_HALF_WIDTH, INNER_HALF_WIDTH - 1];
    ArchRows found = archRows(edge, below);
    foreach (row; found.rows[0 .. found.count]) {
        Rhythm rhythm = Rhythm(edge, row.from, row.span);
        road.fill(MASONRY, boxOf(width, [row.soffit, -1], [ENDLESS_LOW, ENDLESS_HIGH]), rhythm);
        road.fill(RING, boxOf(width, [row.soffit, row.ring], [ENDLESS_LOW, ENDLESS_HIGH]), rhythm);
    }
}

void pier(const(Api)* api, Site at, const(void)* data) {
    Turtle site = Turtle(api, at);
    int depth = PIER_EDGES * site.edgeCells();
    site.pitchDown().fill(MASONRY, boxOf([-INNER_HALF_WIDTH, INNER_HALF_WIDTH - 1], [-PIER_HALF_WIDTH, PIER_HALF_WIDTH - 1], [0, depth - 1]));
    if (!site.forward(1).place(&pier, null, 0)) {
        site.fail("the next pier is behind the road's piers");
    }
}

void world(const(Api)* api, Site at, const(void)* data) {
    Turtle road = Turtle(api, at);
    Column column = road.column();
    int[2] width = [-HALF_WIDTH, HALF_WIDTH - 1];
    int[2] lanes = [-INNER_HALF_WIDTH, INNER_HALF_WIDTH - 1];
    int[2] along = [ENDLESS_LOW, ENDLESS_HIGH];
    road.paint(Material.none, boxOf(width, [DECK, column.high], along));
    road.paint(DECK_MATERIAL, boxOf(width, [0, DECK - 1], along));
    road.paint(SURFACE, boxOf(lanes, [DECK - 1, DECK - 1], along));
    road.paint(STRIPE, boxOf([-1, 0], [DECK - 1, DECK - 1], along), DASHES);
    road.paint(PARAPET_MATERIAL, boxOf([-HALF_WIDTH, -HALF_WIDTH], [DECK - 1, DECK + PARAPET - 1], along));
    road.paint(PARAPET_MATERIAL, boxOf([HALF_WIDTH - 1, HALF_WIDTH - 1], [DECK - 1, DECK + PARAPET - 1], along));
    arches(road, column.low);
    road.place(&pier, null, 0);
    road.left().left().forward(1).place(&pier, null, 0);
    foreach (stop; 0 .. ROUTE_STOPS) {
        road.stop(ROUTE_LANE, DECK, 0.5f + stop * ROUTE_STOP_CELLS);
    }
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "road", &world);
}
