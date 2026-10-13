module plugins.box.box;

import plugins.api.api : Material, Rhythm;
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

immutable int[2] SIDES = [LOW, HIGH];

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
    tower.paint(palette.wall, boxOf([LOW, HIGH], [LOW, HIGH], [-FOUNDATION, top]));
    tower.paint(palette.trim, boxOf([LOW, HIGH], [LOW, HIGH], [0, top]), FLOORS);
    foreach (x; SIDES) {
        foreach (y; SIDES) {
            tower.paint(palette.trim, boxOf([x, x], [y, y], [0, top]));
        }
    }
}

void floors(Turtle tower, int top, Palette palette) {
    tower.paint(palette.floor, boxOf([LOW + 1, HIGH - 1], [LOW + 1, HIGH - 1], [0, top]), FLOORS);
    tower.paint(Material.none, boxOf([LOW + 1, HIGH - 1], [LOW + 1, HIGH - 1], [0, top]), ROOMS);
}

void windows(Turtle tower, int top) {
    immutable int[2] starts = [LOW + 1 + WINDOW_INSET, HIGH - WINDOW_INSET - WINDOW_WIDTH];
    foreach (start; starts) {
        int[2] window = [start, start + WINDOW_WIDTH - 1];
        tower.paint(Material.none, boxOf([LOW, LOW], window, [0, top - 1]), WINDOW_ROW);
        tower.paint(Material.none, boxOf([HIGH, HIGH], window, [0, top - 1]), WINDOW_ROW);
        tower.paint(Material.none, boxOf(window, [LOW, LOW], [0, top - 1]), WINDOW_ROW);
        tower.paint(Material.none, boxOf(window, [HIGH, HIGH], [0, top - 1]), WINDOW_ROW);
    }
}

void stairs(Turtle tower, int top, Palette palette) {
    int everyOtherStory = 2 * STORY;
    foreach (parity; 0 .. 2) {
        int[2] stairLane = [lane(parity), lane(parity) + 1];
        int floor = parity * STORY;
        foreach (tread; 0 .. STORY - 1) {
            int step = STAIR_START + tread;
            tower.paint(palette.floor, boxOf([step, step], stairLane, [0, top - 1]), Rhythm(everyOtherStory, floor + 1, tread + 1));
        }
        tower.paint(Material.none, boxOf([STAIR_START - 1, STAIR_START + STORY - 2], stairLane, [STORY, top]), Rhythm(everyOtherStory, floor + STORY, 1));
    }
}

void merlons(Turtle tower, int z, Palette palette) {
    foreach (x; LOW .. HIGH + 1) {
        foreach (y; LOW .. HIGH + 1) {
            bool isRing = x == LOW || x == HIGH || y == LOW || y == HIGH;
            if (isRing && (x + y) % 2 == 0) {
                tower.paint(palette.trim, boxOf([x, x], [y, y], [z, z]));
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
    tower.paint(Material.none, boxOf([LOW, LOW], [-1, 0], [1, DOOR]));
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
