module plugins.blocks.blocks;

import plugins.api.api : Api, Material, NO_KIND, Rhythm, Risen, Site, SitePart;
import plugins.buildings.building : Bound, Join, Lot, Lots, Palette, STORY, Side, Spec;
import plugins.buildings.types : Type, palettes, stories;
import types = plugins.buildings.types;
import plugins.connector.connector : Floor, connect, slabFloor;
import plugins.turtle.turtle : FACE_CORNERS, PERCENT, Turtle, boxOf, cornersOf, floorDiv, lowerOf, upright;

enum ulong MIX = 0x2545F4914F6CDD1D;
enum uint MIX_SHIFT = 24;
enum ulong ISLAND_SALT = 0x51ED270B;
enum ulong DROPPED_SALT = 0x2C1B3C6D;
enum ulong TREES_SALT = 0x297A2D39;
enum uint AROUND = 4;
enum double DROPPED_STREET = 0.5;
enum double ISLAND = 0.05;
enum double STREET_TREES = 0.5;
enum uint PARK_PERCENT = 6;
enum uint PLAZA_PERCENT = 5;
enum uint PARKING_PERCENT = 3;
enum uint POND_PERCENT = 50;
enum uint FOUNTAIN_PERCENT = 60;
enum uint ALLEY_PERCENT = 20;
enum uint MAX_INSET = 1;
enum int[2] ROAD = [-2, 1];
enum int[2] SIDEWALK = [2, 3];
enum int[2] FAR_SIDEWALK = [-4, -3];
enum int FRONT = 4;
enum int CROSSING = 1;
enum int TREE_SPACING = 8;
enum int CURB = SIDEWALK[0];
enum int PARKING_SPACING = 3;
enum int CITY_GROUND = 1;
enum int CROWN_ROOM = 10;
enum int ROUTE_STORIES = 2;
enum int ROUTE_BUILDING_STORIES = 4;

struct Kind {
    bool isCorner;
    immutable(Type)[] types;
    int most;
}

immutable Type[8] CORNER_TYPES = [Type.tenement, Type.tenement, Type.rowhouse, Type.rowhouse, Type.deco, Type.glass, Type.modern, Type.civic];
immutable Type[8] SLAB_TYPES = [Type.brownstone, Type.brownstone, Type.rowhouse, Type.tenement, Type.warehouse, Type.deco, Type.glass, Type.modern];
immutable Type[7] WIDE_TYPES = [Type.deco, Type.glass, Type.glass, Type.tenement, Type.modern, Type.warehouse, Type.civic];
immutable Type[5] AROUND_TYPES = [Type.deco, Type.glass, Type.tenement, Type.modern, Type.civic];
immutable Type[4] ISLAND_TYPES = [Type.deco, Type.glass, Type.modern, Type.civic];

immutable Kind[4] KINDS = [
    Kind(true, CORNER_TYPES[], 22),
    Kind(false, SLAB_TYPES[], 30),
    Kind(false, WIDE_TYPES[], 38),
    Kind(false, AROUND_TYPES[], 38),
];

struct Root {
    ulong vertex;
    ulong face;
    Risen risen;
    Floor lower;
    bool isRisen;
    bool isRouted;
}

struct Area {
    Turtle tower;
    int[2] x;
    int[2] y;
}

ulong mixed(ulong hash, ulong salt) {
    return ((hash ^ salt) * MIX) >> MIX_SHIFT;
}

double roll(ulong hash, ulong salt) {
    return (mixed(hash, salt) % PERCENT) / cast(double) PERCENT;
}

Turtle[AROUND] quartersOf(Turtle corner) {
    Turtle[AROUND] quarters;
    Turtle turtle = corner;
    foreach (index; 0 .. AROUND) {
        quarters[index] = turtle;
        turtle = turtle.right();
    }
    return quarters;
}

bool isOwner(ref const Turtle[AROUND] quarters) {
    ulong mine = quarters[0].hash(SitePart.face);
    uint index = 1;
    while (index < AROUND && quarters[index].hash(SitePart.face) < mine) {
        index += 1;
    }
    return index == AROUND;
}

bool isFoot(Turtle corner, ref const Risen risen) {
    return corner.hash(SitePart.vertex) == Turtle(corner.api, risen.foot).hash(SitePart.vertex);
}

bool ownsFoot(Turtle face, ref const Risen risen) {
    bool isFound = false;
    foreach (corner; cornersOf(face)) {
        Turtle[AROUND] quarters = quartersOf(corner);
        isFound = isFound || (isFoot(corner, risen) && isOwner(quarters));
    }
    return isFound;
}

bool isRisingFrom(Turtle corner) {
    return corner.rising() != NO_KIND;
}

bool isRootVertex(Turtle site, ref const Root root) {
    return site.hash(SitePart.vertex) == root.vertex;
}

bool isIsland(Turtle face, ref const Root root) {
    if (roll(face.hash(SitePart.face), ISLAND_SALT) >= ISLAND) {
        return false;
    } else {
        uint index = 0;
        Turtle[FACE_CORNERS] corners = cornersOf(face);
        while (index < FACE_CORNERS && !isRootVertex(corners[index], root)) {
            index += 1;
        }
        return index == FACE_CORNERS;
    }
}

bool isPlannedStreet(Turtle edge, ref const Root root) {
    if (isRootVertex(edge, root) || isRootVertex(edge.forward(1), root)) {
        return true;
    } else if (isIsland(edge, root) || isIsland(edge.left(), root)) {
        return true;
    } else {
        return roll(edge.hash(SitePart.edge), DROPPED_SALT) >= DROPPED_STREET;
    }
}

bool isKeptForAccess(Turtle edge, ref const Root root) {
    ulong mine = edge.hash(SitePart.edge);
    uint index = 1;
    Turtle turtle = edge.right();
    while (index < AROUND && !isPlannedStreet(turtle, root) && turtle.hash(SitePart.edge) < mine) {
        index += 1;
        turtle = turtle.right();
    }
    return index == AROUND;
}

bool isStreet(Turtle edge, ref const Root root) {
    if (isPlannedStreet(edge, root)) {
        return true;
    } else {
        return isKeptForAccess(edge, root) || isKeptForAccess(edge.forward(1).right().right(), root);
    }
}

bool hasTrees(Turtle edge) {
    return roll(edge.hash(SitePart.edge), TREES_SALT) < STREET_TREES;
}

int between(Turtle site, int low, int high) {
    return low + cast(int) site.pick(high - low + 1);
}

void sidewalk(Turtle edge, int[2] x, bool startsCrossed, bool endsCrossed) {
    int last = edge.edgeCells() - 1;
    int first = 0;
    if (startsCrossed) {
        first = CROSSING + 1;
    }
    if (endsCrossed) {
        last = last - CROSSING - 1;
    }
    edge.paint(Material.concrete, boxOf(x, [-1, 0], [first, last]));
}

void streetTrees(Turtle edge) {
    int last = edge.edgeCells() - 1;
    int[2] planted = [CROSSING + 4, last - CROSSING - 4];
    Rhythm trunk = Rhythm(TREE_SPACING, 6, 1);
    edge.paint(Material.oakLeaves, boxOf([CURB - 1, CURB + 1], [5, 6], planted), Rhythm(TREE_SPACING, 4, 5));
    edge.paint(Material.oakLeaves, boxOf([CURB - 1, CURB + 1], [7, 7], planted), Rhythm(TREE_SPACING, 5, 3));
    edge.paint(Material.oakLeaves, boxOf([CURB, CURB], [8, 8], planted), trunk);
    edge.paint(Material.oakWood, boxOf([CURB, CURB], [1, 5], planted), trunk);
}

void street(Turtle edge, ref const Root root) {
    Turtle finish = edge.forward(1);
    bool nearStart = isStreet(edge.right(), root);
    bool farStart = isStreet(edge.left(), root);
    bool nearFinish = isStreet(finish.right(), root);
    bool farFinish = isStreet(finish.left(), root);
    int last = edge.edgeCells() - 1;
    edge.paint(Material.basalt, boxOf(ROAD, [-1, -1], [0, last]));
    sidewalk(edge, SIDEWALK, nearStart, nearFinish);
    sidewalk(edge, FAR_SIDEWALK, farStart, farFinish);
    if (nearStart || farStart) {
        edge.paint(Material.whiteBrick, boxOf(ROAD, [-1, -1], [CROSSING + 1, CROSSING + 2]));
    }
    if (nearFinish || farFinish) {
        edge.paint(Material.whiteBrick, boxOf(ROAD, [-1, -1], [last - CROSSING - 2, last - CROSSING - 1]));
    }
    if (hasTrees(edge)) {
        streetTrees(edge);
    }
}

void tree(Turtle tower, int x, int y) {
    tower.paint(Material.oakLeaves, boxOf([x - 2, x + 2], [y - 1, y + 1], [5, 7]));
    tower.paint(Material.oakLeaves, boxOf([x - 1, x + 1], [y - 2, y + 2], [5, 7]));
    tower.paint(Material.oakLeaves, boxOf([x - 1, x + 1], [y - 1, y + 1], [8, 9]));
    tower.paint(Material.oakWood, boxOf([x, x], [y, y], [1, 7]));
}

Area groundOf(ref const Lot lot) {
    Turtle tower = upright(lot.site);
    int far = tower.column().high;
    int xLow = 0;
    int yLow = 0;
    if (lot.bounds[Side.xLow] == Bound.street) {
        xLow = FRONT;
    }
    if (lot.bounds[Side.yLow] == Bound.street) {
        yLow = FRONT;
    }
    return Area(tower, [xLow, far], [yLow, far]);
}

void pave(ref const Lots lots, Material material) {
    foreach (ref lot; lots.slice()) {
        Area area = groundOf(lot);
        area.tower.paint(material, boxOf(area.x, area.y, [-1, 0]));
    }
}

bool isRoomy(Area area) {
    return area.x[1] - area.x[0] >= 4 && area.y[1] - area.y[0] >= 4;
}

int centre(int[2] span) {
    return floorDiv(span[0] + span[1] + 1, 2);
}

void plant(ref const Lots lots) {
    foreach (ref lot; lots.slice()) {
        Area area = groundOf(lot);
        if (isRoomy(area)) {
            tree(area.tower, centre(area.x), centre(area.y));
        }
    }
}

void fountain(Turtle tower, int x, int y) {
    tower.paint(Material.marble, boxOf([x - 2, x + 2], [y - 2, y + 2], [1, 1]));
    tower.paint(Material.water, boxOf([x - 1, x + 1], [y - 1, y + 1], [1, 1]));
    tower.paint(Material.marble, boxOf([x, x], [y, y], [1, 2]));
    tower.paint(Material.water, boxOf([x, x], [y, y], [3, 3]));
}

void fountains(ref const Lots lots) {
    foreach (ref lot; lots.slice()) {
        Area area = groundOf(lot);
        if (isRoomy(area)) {
            fountain(area.tower, centre(area.x), centre(area.y));
        }
    }
}

void ponds(ref const Lots lots) {
    foreach (ref lot; lots.slice()) {
        Area area = groundOf(lot);
        if (isRoomy(area)) {
            int[2] x = [area.x[0] + 1, area.x[1] - 1];
            int[2] y = [area.y[0] + 1, area.y[1] - 1];
            area.tower.paint(Material.water, boxOf(x, y, [-1, 0]));
            area.tower.paint(Material.sand, boxOf(x, y, [-2, -2]));
        }
    }
}

void parking(ref const Lots lots) {
    foreach (ref lot; lots.slice()) {
        Area area = groundOf(lot);
        area.tower.paint(Material.basalt, boxOf(area.x, area.y, [0, 0]));
        for (int x = area.x[0] + 1; x <= area.x[1]; x += PARKING_SPACING) {
            area.tower.paint(Material.whiteBrick, boxOf([x, x], [area.y[0] + 1, area.y[0] + 3], [0, 0]));
        }
    }
}

struct Chosen {
    Type type;
    Spec spec;
}

Chosen chosenFor(Turtle site, ref const Kind kind, immutable(Type)[] choices) {
    Type type = choices[site.pick(cast(uint) choices.length)];
    int[2] range = stories(type);
    int most = lowerOf(range[1], kind.most);
    int count = between(site, range[0], most);
    int gap = 0;
    if (!kind.isCorner && site.chance(ALLEY_PERCENT)) {
        gap = 1;
    }
    int front = FRONT;
    if (!kind.isCorner) {
        front = FRONT + cast(int) site.pick(MAX_INSET + 1);
    }
    immutable(Palette)[] options = palettes(type);
    return Chosen(type, Spec(count, options[site.pick(cast(uint) options.length)], front, gap, 0));
}

int fit(Turtle site, int stories) {
    int room = CROWN_ROOM + 1;
    int fitting = floorDiv(site.balance(stories * STORY + room) - room, STORY);
    return lowerOf(stories, fitting);
}

Chosen fitted(Chosen chosen, Turtle site, ref const Root root) {
    Chosen result = chosen;
    if (root.isRisen) {
        result.spec.stories = fit(site, chosen.spec.stories);
    }
    return result;
}

void build(ref const Lots lots, Chosen chosen) {
    pave(lots, Material.concrete);
    types.build(chosen.type, lots, chosen.spec);
}

void lotAt(ref const Lots lots, bool isRoute, bool isPlaza, ref const Root root) {
    Turtle site = lots.items[0].site;
    if (isPlaza) {
        pave(lots, Material.granite);
        plant(lots);
    } else if (isRoute) {
        build(lots, Chosen(Type.tenement, Spec(ROUTE_BUILDING_STORIES, palettes(Type.tenement)[0], FRONT, 0, ROUTE_STORIES)));
    } else if (site.chance(PARK_PERCENT)) {
        pave(lots, Material.grass);
        if (site.chance(POND_PERCENT)) {
            ponds(lots);
        } else {
            plant(lots);
        }
    } else if (site.chance(PLAZA_PERCENT)) {
        pave(lots, Material.granite);
        if (site.chance(FOUNTAIN_PERCENT)) {
            fountains(lots);
        } else {
            plant(lots);
        }
    } else if (site.chance(PARKING_PERCENT)) {
        parking(lots);
    } else {
        Kind kind = KINDS[lots.count - 1];
        Chosen chosen = fitted(chosenFor(site, kind, kind.types), site, root);
        if (chosen.spec.stories >= 1) {
            build(lots, chosen);
        } else {
            pave(lots, Material.granite);
            plant(lots);
        }
    }
}

Lot lotOf(Turtle quarter, bool isStreetBefore, bool isStreetAfter, bool isFirst) {
    Lot lot;
    lot.site = quarter;
    lot.bounds = [Bound.joined, Bound.joined, Bound.lot, Bound.lot];
    if (isStreetAfter) {
        lot.bounds[Side.xLow] = Bound.street;
    }
    if (isStreetBefore) {
        lot.bounds[Side.yLow] = Bound.street;
    }
    if (isFirst && isStreetBefore) {
        lot.front = Side.yLow;
        lot.hasFront = true;
    }
    return lot;
}

void join(ref Lots run) {
    foreach (index; 0 .. run.count) {
        if (run.items[index].bounds[Side.xLow] == Bound.joined) {
            uint next = cast(uint)((index + 1) % run.count);
            run.items[index].joins[Side.xLow] = Join(next, Side.yLow, true);
            run.items[next].joins[Side.yLow] = Join(cast(uint) index, Side.xLow, true);
        }
    }
}

void lotsAt(ref const Turtle[AROUND] quarters, ref const Root root) {
    bool[AROUND] streets;
    bool[AROUND] islands;
    bool isAny = false;
    foreach (index; 0 .. AROUND) {
        streets[index] = isStreet(quarters[index], root);
        islands[index] = isIsland(quarters[index], root);
        isAny = isAny || streets[index];
    }
    bool isRoot = isRootVertex(quarters[0], root);
    bool isFootOfRisen = isRoot && root.isRisen;
    if (isFootOfRisen) {
        connect(quarters[0], root.risen, slabFloor(CITY_GROUND), root.lower, root.isRouted);
    }
    bool isPlaza = isFootOfRisen || isRisingFrom(quarters[0]);
    uint start = 0;
    while (start < AROUND && !streets[start]) {
        start += 1;
    }
    if (!isAny) {
        start = 0;
    }
    Lots run;
    bool isRoute = false;
    foreach (step; 0 .. AROUND) {
        uint index = (start + step) % AROUND;
        uint after = (index + 1) % AROUND;
        if (!islands[index]) {
            run.add(lotOf(quarters[index], streets[index], streets[after], run.count == 0));
            isRoute = isRoute || (isRoot && quarters[index].hash(SitePart.face) == root.face);
        }
        if (streets[after] || step == AROUND - 1) {
            if (run.count > 0) {
                join(run);
                lotAt(run, isRoute, isPlaza, root);
            }
            run = Lots.init;
            isRoute = false;
        }
    }
}

void island(ref const Turtle[FACE_CORNERS] corners, ref const Root root) {
    Lots parts;
    foreach (corner; corners) {
        Lot lot;
        lot.site = corner;
        lot.bounds = [Bound.street, Bound.street, Bound.joined, Bound.joined];
        parts.add(lot);
    }
    parts.items[0].front = Side.yLow;
    parts.items[0].hasFront = true;
    Chosen chosen = fitted(chosenFor(corners[0], KINDS[KINDS.length - 1], ISLAND_TYPES[]), corners[0], root);
    if (chosen.spec.stories >= 1) {
        build(parts, chosen);
    } else {
        pave(parts, Material.granite);
        plant(parts);
    }
}

Root rootAt(Turtle site, bool isRouted) {
    return Root(site.hash(SitePart.vertex), site.hash(SitePart.face), Risen.init, Floor.init, false, isRouted);
}

Root risenRootAt(Turtle foot, ref const Risen risen, Floor lower, bool isRouted) {
    return Root(foot.hash(SitePart.vertex), foot.hash(SitePart.face), risen, lower, true, isRouted);
}

void tile(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    tileAt(Turtle(api, site), *cast(const(Root)*) data);
}

void tileAt(Turtle face, ref const Root root) {
    Turtle[FACE_CORNERS] corners = cornersOf(face);
    ulong mine = face.hash(SitePart.face);
    foreach (edge; corners) {
        if (isStreet(edge, root) && mine > edge.left().hash(SitePart.face)) {
            street(edge, root);
        }
    }
    foreach (corner; corners) {
        Turtle[AROUND] quarters = quartersOf(corner);
        if (isOwner(quarters)) {
            lotsAt(quarters, root);
        }
    }
    if (isIsland(face, root)) {
        island(corners, root);
    }
}
