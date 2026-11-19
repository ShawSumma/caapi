module plugins.box.box;

import plugins.api.api : Material, Rhythm, Span;
import plugins.api.binding : List, bound;
import plugins.api.content : Content;
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
enum Rhythm SILL_ROW = Rhythm(STORY, STORY / 2 - 1, 1);
enum int PINNACLE = 3;
enum int LOW = -HALF_WIDTH;
enum int HIGH = HALF_WIDTH - 1;
enum int HUT_STORIES = 2;
enum int HUT_TOP = HUT_STORIES * STORY;
enum size_t MOST_PALETTES = 16;

struct Palette {
    Material wall;
    Material floor;
    Material trim;
}

struct Palettes {
    List!(Palette, MOST_PALETTES) palettes;
    Palette timber;
    Material bench;
    Material lamp;
}

__gshared Palettes palettes;

void resolveBox(const(Content)* content) {
    palettes = content.bound!Palettes("box:palettes");
}

immutable int[2] SIDES = [LOW, HIGH];
immutable int[2] WINDOW_STARTS = [LOW + 1 + WINDOW_INSET, HIGH - WINDOW_INSET - WINDOW_WIDTH];

Palette palette(Turtle site) {
    return palettes.palettes.items[site.pick(palettes.palettes.count)];
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

void shell(Turtle tower, int top, Palette palette, int foundation) {
    tower.paint(palette.wall, boxOf(Span(LOW, HIGH), Span(LOW, HIGH), Span(-foundation, top)));
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

void sills(Turtle tower, int top, Palette palette) {
    foreach (start; WINDOW_STARTS) {
        Span window = Span(start, start + WINDOW_WIDTH - 1);
        tower.fill(palette.trim, boxOf(Span(LOW - 1, LOW - 1), window, Span(0, top - 1)), SILL_ROW);
        tower.fill(palette.trim, boxOf(Span(HIGH + 1, HIGH + 1), window, Span(0, top - 1)), SILL_ROW);
        tower.fill(palette.trim, boxOf(window, Span(LOW - 1, LOW - 1), Span(0, top - 1)), SILL_ROW);
        tower.fill(palette.trim, boxOf(window, Span(HIGH + 1, HIGH + 1), Span(0, top - 1)), SILL_ROW);
    }
}

void ledge(Turtle tower, Material material, int jut, Span z) {
    tower.fill(material, boxOf(Span(LOW - jut, HIGH + jut), Span(LOW - jut, LOW - 1), z));
    tower.fill(material, boxOf(Span(LOW - jut, HIGH + jut), Span(HIGH + 1, HIGH + jut), z));
    tower.fill(material, boxOf(Span(LOW - jut, LOW - 1), Span(LOW, HIGH), z));
    tower.fill(material, boxOf(Span(HIGH + 1, HIGH + jut), Span(LOW, HIGH), z));
}

void pinnacles(Turtle tower, int z, Palette palette) {
    foreach (x; SIDES) {
        foreach (y; SIDES) {
            tower.paint(palette.trim, boxOf(Span(x, x), Span(y, y), Span(z, z + PINNACLE - 1)));
        }
    }
}

void buttresses(Turtle tower, int top, Palette palette, int foundation = FOUNDATION) {
    immutable Span[2] corners = [Span(LOW - 1, LOW), Span(HIGH, HIGH + 1)];
    foreach (x; corners) {
        foreach (y; corners) {
            tower.fill(palette.trim, boxOf(x, y, Span(-foundation, top / 2)));
        }
    }
    ledge(tower, palette.wall, 1, Span(-foundation, 0));
}

void roof(Turtle tower, int z, Palette palette) {
    foreach (step; 0 .. HALF_WIDTH + 1) {
        int half = HALF_WIDTH + 1 - step;
        tower.paint(palette.trim, boxOf(Span(-half, half - 1), Span(-half, half - 1), Span(z + step, z + step)));
    }
}

void storeys(Turtle at, int top, Palette palette, int foundation) {
    shell(at, top, palette, foundation);
    floors(at, top, palette);
    windows(at, top);
    sills(at, top, palette);
    stairs(at, top, palette);
}

void tower(Turtle at, int top, Palette palette, int foundation = FOUNDATION) {
    storeys(at, top, palette, foundation);
    ledge(at, palette.trim, 1, Span(top, top));
    merlons(at, top + 1, palette);
    pinnacles(at, top + 1, palette);
}

void door(Turtle tower) {
    tower.paint(Material.none, boxOf(Span(LOW, LOW), Span(-1, 0), Span(1, DOOR)));
    tower.paint(Material.none, boxOf(Span(LOW - 1, LOW - 1), Span(-1, 0), Span(0, DOOR)));
}

void hut(Turtle at) {
    storeys(at, HUT_TOP, palettes.timber, FOUNDATION);
    roof(at, HUT_TOP + 1, palettes.timber);
    door(at);
    at.paint(palettes.bench, boxOf(Span(HIGH - 1, HIGH - 1), Span(0, 0), Span(1, 1)));
    at.paint(palettes.lamp, boxOf(Span(HIGH - 1, HIGH - 1), Span(-1, -1), Span(DOOR, DOOR)));
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
