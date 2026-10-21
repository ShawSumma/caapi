module plugins.connector.connector;

import plugins.api.api : Box, Material, Rhythm, Sky;
import plugins.turtle.turtle : Turtle, boxOf, floorMod, higherOf;

enum int STORY = 4;
enum int HALF_WIDTH = 4;
enum int INNER = HALF_WIDTH - 1;
enum int CORE = 2 * INNER;
enum int TURN = 8;
enum int FLIP_CLEARANCE = 1;
enum int FLIP_SLACK = 2;
enum int FOOTING = 8;
enum int DOOR_TOP = 3;
enum int[2] DOOR = [-1, 0];
enum int[2] STOOP = [-2, 1];
enum Material LANDING = Material.concrete;
immutable int[2][2] GLASS = [[-3, -2], [1, 2]];
enum int[2] WELL = [2, 3];
immutable int[2][TURN] SEGMENTS = [
    [0, 2],
    [0, 4],
    [2, 4],
    [4, 4],
    [4, 2],
    [4, 0],
    [2, 0],
    [0, 0],
];

struct Palette {
    Material wall;
    Material trim;
    Material floor;
}

immutable Palette[4] PALETTES = [
    Palette(Material.whiteBrick, Material.limestone, Material.woodPlanks),
    Palette(Material.redSandstone, Material.whiteBrick, Material.woodPlanks),
    Palette(Material.limestone, Material.steel, Material.concrete),
    Palette(Material.greyBrick, Material.whiteBrick, Material.woodPlanks),
];

struct Layout {
    int below;
    int stoop;
    int base;
    int top;
    int split;
    int flip;
}

Box cells(int[2] along, int[2] across, int[2] z) {
    return boxOf([along[0] - INNER, along[1] - INNER], [across[0] - INNER, across[1] - INNER], z);
}

void windows(Turtle tower, int[2] z, Rhythm rows) {
    foreach (run; GLASS) {
        tower.paint(Material.glass, boxOf([-HALF_WIDTH, -HALF_WIDTH], run, z), rows);
        tower.paint(Material.glass, boxOf([HALF_WIDTH - 1, HALF_WIDTH - 1], run, z), rows);
        tower.paint(Material.glass, boxOf(run, [-HALF_WIDTH, -HALF_WIDTH], z), rows);
        tower.paint(Material.glass, boxOf(run, [HALF_WIDTH - 1, HALF_WIDTH - 1], z), rows);
    }
}

void shell(Turtle tower, Palette palette, Layout layout) {
    int base = layout.base;
    int top = layout.top;
    int split = layout.split;
    int[2] square = [-HALF_WIDTH, HALF_WIDTH - 1];
    tower.paint(palette.wall, boxOf(square, square, [base, base + top]));
    tower.paint(palette.trim, boxOf(square, square, [base, base + top]), Rhythm(STORY, floorMod(base, STORY), 1));
    windows(tower, [base + 1, base + split], Rhythm(STORY, floorMod(base + 1, STORY), 2));
    windows(tower, [base + split + 1, base + top - 1], Rhythm(STORY, floorMod(base + top - 2, STORY), 2));
    tower.paint(palette.floor, cells([0, CORE - 1], [0, CORE - 1], [base, base]));
    tower.paint(palette.floor, cells([0, CORE - 1], [0, CORE - 1], [base + top, base + top]));
}

int landingLayer(int flip) {
    return flip - FLIP_SLACK + 1 + TURN;
}

void helix(Turtle tower, Material material, Layout layout) {
    int base = layout.base;
    int top = layout.top;
    int flip = layout.flip;
    int landing = base + landingLayer(flip);
    tower.paint(Material.none, cells([0, CORE - 1], [0, CORE - 1], [base + 1, base + top - 1]));
    tower.paint(material, cells(WELL, WELL, [landing, landing + 1]));
    foreach (index, segment; SEGMENTS) {
        int i = cast(int) index;
        int[2] along = [segment[0], segment[0] + 1];
        int[2] across = [segment[1], segment[1] + 1];
        int last = flip - floorMod(flip - i, TURN);
        if (last >= 0) {
            tower.paint(material, cells(along, across, [base, base + last]), Rhythm(TURN, floorMod(base + i - 1, TURN), 2));
        }
        if (last + TURN <= top) {
            tower.paint(material, cells(along, across, [base + last + TURN, base + top]), Rhythm(TURN, floorMod(base + i, TURN), 2));
        }
    }
}

void planetDoor(Turtle tower, Palette palette, Layout layout) {
    int base = layout.base;
    int below = layout.below;
    tower.paint(Material.none, boxOf([-HALF_WIDTH, -HALF_WIDTH], DOOR, [base + 1, base + DOOR_TOP]));
    foreach (distance; 1 .. layout.stoop + 2) {
        int[2] x = [-HALF_WIDTH - distance, -HALF_WIDTH - distance];
        int surface = higherOf(below, base + 1 - distance);
        tower.fill(palette.trim, boxOf(x, STOOP, [below - FOOTING, below - 2]));
        tower.paint(palette.trim, boxOf(x, STOOP, [below - 1, surface - 1]));
        tower.paint(Material.none, boxOf(x, STOOP, [surface, base + DOOR_TOP]));
    }
}

void skyDoor(Turtle tower, Layout layout) {
    int floor = layout.base + layout.top;
    int[2] x = [-HALF_WIDTH - 1, -HALF_WIDTH - 1];
    tower.paint(Material.none, boxOf([-HALF_WIDTH, -HALF_WIDTH], DOOR, [floor - DOOR_TOP, floor - 1]));
    tower.fill(LANDING, boxOf(x, STOOP, [floor + 1, floor + FOOTING]));
    tower.paint(LANDING, boxOf(x, STOOP, [floor, floor]));
    tower.paint(Material.none, boxOf(x, STOOP, [floor - DOOR_TOP, floor - 1]));
}

void tread(Turtle tower, int layer, int z) {
    int[2] segment = SEGMENTS[floorMod(layer, TURN)];
    tower.stop(segment[0] + 1 - INNER, segment[1] + 1 - INNER, z);
}

void route(Turtle tower, Layout layout) {
    int base = layout.base;
    int top = layout.top;
    int flip = layout.flip;
    tower.stop(-HALF_WIDTH - layout.stoop - 0.5f, 0, layout.below);
    tower.stop(0.5f - INNER, 0, base + 1);
    foreach (layer; 1 .. flip - FLIP_SLACK + 1) {
        tread(tower, layer, base + layer + 1);
    }
    foreach (layer; landingLayer(flip) .. top + 1) {
        tread(tower, layer, base + layer);
    }
    tower.stop(0.5f - INNER, 0, base + top);
    tower.stop(-HALF_WIDTH - 0.5f, 0, base + top);
}

Layout layoutOf(Turtle site, ref const Sky sky, int ground) {
    int length = sky.edges * site.edgeCells();
    int skyFloor = length - ground;
    int stoop = floorMod(skyFloor - sky.below + 1, TURN);
    int base = sky.below - 1 + stoop;
    int split = length - sky.balance - base - 1;
    return Layout(sky.below, stoop, base, skyFloor - base, split, split + 1 - FLIP_CLEARANCE);
}

void connect(Turtle site, ref const Sky sky, int ground, bool isRouted) {
    Layout layout = layoutOf(site, sky, ground);
    if (layout.split >= STORY && layout.top - layout.split > STORY && layout.top >= 2 * TURN) {
        Palette palette = PALETTES[site.pick(PALETTES.length)];
        Turtle tower = site.pitchUp().rollRight().forward(sky.edges).pitchUp().pitchUp().rollRight();
        int[2] square = [-HALF_WIDTH, HALF_WIDTH - 1];
        tower.fill(palette.trim, boxOf(square, square, [layout.below - FOOTING, layout.base - 1]));
        tower.fill(palette.trim, boxOf(square, square, [layout.base + layout.top + 1, layout.base + layout.top + FOOTING]));
        shell(tower, palette, layout);
        helix(tower, palette.floor, layout);
        planetDoor(tower, palette, layout);
        skyDoor(tower, layout);
        if (isRouted) {
            route(tower, layout);
        }
    }
}
