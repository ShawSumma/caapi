module plugins.box.box;

import plugins.api.api : Material, Rhythm, Span;
import plugins.turtle.turtle : Turtle, boxOf;

enum int HALF_WIDTH = 5;
enum int STORY = 4;
enum int DOOR = STORY - 1;
enum int FOUNDATION = 3;
enum int STAIR_START = 2 - HALF_WIDTH;
enum int WINDOW_INSET = 1;
enum int WINDOW_WIDTH = 2;
enum float MIDDLE_LANE = 0;
enum float ROUTE_LANE = 0.5f;
enum Rhythm FLOORS = Rhythm(STORY, 0, 1);
enum Rhythm ROOMS = Rhythm(STORY, 1, STORY - 1);
enum Rhythm WINDOW_ROW = Rhythm(STORY, STORY / 2, 1);
enum int LOW = -HALF_WIDTH;
enum int HIGH = HALF_WIDTH - 1;
enum int HUT_STORIES = 2;
enum int HUT_TOP = HUT_STORIES * STORY;

struct Palette {
    Material wall;
    Material floor;
    Material trim;
}

immutable Palette[4] PALETTES = [
    Palette(Material.concrete, Material.concrete, Material.steel),
    Palette(Material.whiteBrick, Material.greyBrick, Material.steel),
    Palette(Material.sandstone, Material.woodPlanks, Material.steel),
    Palette(Material.greyBrick, Material.concrete, Material.marble),
];

immutable Palette TIMBER = Palette(Material.oakWood, Material.woodPlanks, Material.spruceWood);

immutable int[2] SIDES = [LOW, HIGH];
immutable int[2] WINDOW_STARTS = [LOW + 1 + WINDOW_INSET, HIGH - WINDOW_INSET - WINDOW_WIDTH];

Palette palette(Turtle site) {
    return PALETTES[site.pick(PALETTES.length)];
}

int top(Turtle site, int edges) {
    return edges * site.edgeCells() / STORY * STORY;
}

int lane(int story) {
    if (story % 2 == 0) {
        return 1 - HALF_WIDTH;
    } else {
        return HALF_WIDTH - 3;
    }
}

void shell(Turtle tower, int top, Palette palette) {
    tower.paint(palette.wall, boxOf(Span(LOW, HIGH), Span(LOW, HIGH), Span(-FOUNDATION, top)));
    tower.paint(palette.trim, boxOf(Span(LOW, HIGH), Span(LOW, HIGH), Span(0, top)), FLOORS);
    foreach (x; SIDES) {
        foreach (y; SIDES) {
            tower.paint(palette.trim, boxOf(Span(x, x), Span(y, y), Span(0, top)));
        }
    }
}

void floors(Turtle tower, int top, Palette palette) {
    tower.paint(palette.floor, boxOf(Span(LOW + 1, HIGH - 1), Span(LOW + 1, HIGH - 1), Span(0, top)), FLOORS);
    tower.paint(Material.none, boxOf(Span(LOW + 1, HIGH - 1), Span(LOW + 1, HIGH - 1), Span(0, top)), ROOMS);
}

void windows(Turtle tower, int top) {
    foreach (start; WINDOW_STARTS) {
        Span window = Span(start, start + WINDOW_WIDTH - 1);
        tower.paint(Material.none, boxOf(Span(LOW, LOW), window, Span(0, top - 1)), WINDOW_ROW);
        tower.paint(Material.none, boxOf(Span(HIGH, HIGH), window, Span(0, top - 1)), WINDOW_ROW);
        tower.paint(Material.none, boxOf(window, Span(LOW, LOW), Span(0, top - 1)), WINDOW_ROW);
        tower.paint(Material.none, boxOf(window, Span(HIGH, HIGH), Span(0, top - 1)), WINDOW_ROW);
    }
}

void stairs(Turtle tower, int top, Palette palette) {
    int everyOtherStory = 2 * STORY;
    foreach (parity; 0 .. 2) {
        Span stairLane = Span(lane(parity), lane(parity) + 1);
        int floor = parity * STORY;
        foreach (tread; 0 .. STORY - 1) {
            int step = STAIR_START + tread;
            tower.paint(palette.floor, boxOf(Span(step, step), stairLane, Span(0, top - 1)), Rhythm(everyOtherStory, floor + 1, tread + 1));
        }
        tower.paint(Material.none, boxOf(Span(STAIR_START - 1, STAIR_START + STORY - 2), stairLane, Span(STORY, top)), Rhythm(everyOtherStory, floor + STORY, 1));
    }
}

void merlons(Turtle tower, int z, Palette palette) {
    foreach (x; LOW .. HIGH + 1) {
        foreach (y; LOW .. HIGH + 1) {
            if ((x == LOW || x == HIGH || y == LOW || y == HIGH) && (x + y) % 2 == 0) {
                tower.paint(palette.trim, boxOf(Span(x, x), Span(y, y), Span(z, z)));
            }
        }
    }
}

void tower(Turtle at, int top, Palette palette) {
    shell(at, top, palette);
    floors(at, top, palette);
    windows(at, top);
    stairs(at, top, palette);
    merlons(at, top + 1, palette);
}

void door(Turtle tower) {
    tower.paint(Material.none, boxOf(Span(LOW, LOW), Span(-1, 0), Span(1, DOOR)));
}

void hut(Turtle at) {
    tower(at, HUT_TOP, TIMBER);
    door(at);
}

void stairRoute(Turtle tower, int firstFloor, int top) {
    float approach = STAIR_START - 0.5f;
    float landing = STAIR_START + STORY - 0.5f;
    for (int floor = firstFloor; floor < top; floor += STORY) {
        float stairLane = lane(floor / STORY) + 1;
        tower.stop(approach, MIDDLE_LANE, floor + 1);
        tower.stop(approach, stairLane, floor + 1);
        foreach (tread; 0 .. STORY - 1) {
            tower.stop(STAIR_START + tread + 0.5f, stairLane, floor + tread + 2);
        }
        tower.stop(landing, stairLane, floor + STORY + 1);
        tower.stop(landing, MIDDLE_LANE, floor + STORY + 1);
    }
}
