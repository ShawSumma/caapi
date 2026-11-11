module plugins.blocks.blocks;

import plugins.api.api : Api, Material, MaybeIndex, Rhythm, Risen, Site, SitePart, Span;
import plugins.api.binding : List, bound, settingsOf;
import plugins.api.content : Content;
import plugins.api.flags : Flags;
import plugins.buildings.building : Bound, Join, Lot, Lots, Palette, STORY, Side, Spec, Traits;
import plugins.buildings.types : resolveBuildings;
import types = plugins.buildings.types;
import plugins.connector.connector : Connection, connect, resolveConnector;
import plugins.turtle.turtle : FACE_CORNERS, PORT, Turtle, boxOf, cornersOf, floorDiv, higherOf, lowerOf, mixed, roll, strongestAround, upright;

enum ulong ISLAND_SALT = 0x51ED270B;
enum ulong DROPPED_SALT = 0x2C1B3C6D;
enum ulong TREES_SALT = 0x297A2D39;
enum ulong DISTRICT_SALT = 0x7B1D0F29;
enum uint AROUND = 4;
enum uint MAX_INSET = 1;
enum Span ROAD = Span(-2, 1);
enum Span SIDEWALK = Span(2, 3);
enum Span FAR_SIDEWALK = Span(-4, -3);
enum int FRONT = 4;
enum int CROSSING = 1;
enum int TREE_SPACING = 8;
enum int CURB = SIDEWALK.low;
enum int PARKING_SPACING = 3;
enum int CROWN_ROOM = 10;
enum int ROUTE_STORIES = 2;
enum int ROUTE_BUILDING_STORIES = 4;
enum size_t MOST_TYPES = 16;
enum size_t MOST_LOT_RULES = 8;
enum size_t MOST_DISTRICTS = 8;
immutable Bound[4] RUN_BOUNDS = [Side.xLow: Bound.joined, Side.yLow: Bound.joined, Side.xHigh: Bound.lot, Side.yHigh: Bound.lot];
immutable Bound[4] ISLAND_BOUNDS = [Side.xLow: Bound.street, Side.yLow: Bound.street, Side.xHigh: Bound.joined, Side.yHigh: Bound.joined];

enum LotShape : ubyte {
    corner,
    run,
}

enum LotMark : ubyte {
    streetBefore,
    streetAfter,
    first,
}

struct LotRule {
    uint lots;
    LotShape shape;
    int mostStories;
    List!(Traits, MOST_TYPES) types;
}

struct District {
    double streetTrees;
    uint parkPercent;
    uint plazaPercent;
    uint parkingPercent;
    List!(LotRule, MOST_LOT_RULES) rules;
    LotRule island;
}

struct Zoning {
    List!(District, MOST_DISTRICTS) districts;
    Traits route;
}

__gshared Zoning zoning;

struct Tuning {
    double droppedStreet;
    double island;
    uint pondPercent;
    uint fountainPercent;
    uint alleyPercent;
}

__gshared Tuning tuning;

const(District)* districtAt(Turtle corner) {
    return &zoning.districts.items[mixed(strongestAround(corner), DISTRICT_SALT) % zoning.districts.count];
}

MaybeIndex!LotRule ruleFor(ref const District district, uint lots) {
    uint index = 0;
    while (index < district.rules.count && district.rules.items[index].lots != lots) {
        index += 1;
    }
    if (index < district.rules.count) {
        return MaybeIndex!LotRule.of(index);
    } else {
        return MaybeIndex!LotRule.init;
    }
}

struct Materials {
    Material road;
    Material sidewalk;
    Material marking;
    Material leaves;
    Material trunk;
    Material basin;
    Material water;
    Material pondBed;
    Material lot;
    Material plaza;
    Material park;
}

__gshared Materials materials;

void resolveBlocks(const(Content)* content) {
    resolveBuildings(content);
    resolveConnector(content);
    materials = content.bound!Materials("blocks:materials");
    zoning = content.bound!Zoning("blocks:zoning");
    resolveStreets(content);
}

void resolveStreets(const(Content)* content) {
    tuning = content.settingsOf!Tuning("blocks");
}

struct Root {
    ulong vertex;
    ulong face;
    Risen risen;
    Connection connection;
    uint tag;

    bool isRisen() const {
        return risen.hasRisen;
    }
}

struct Area {
    Turtle tower;
    Span x;
    Span y;
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

bool probeOwner(ref const Turtle[AROUND] quarters) {
    ulong mine = quarters[0].probeHash(SitePart.face);
    foreach (quarter; quarters[1 .. $]) {
        ulong theirs = quarter.probeHash(SitePart.face);
        if (!(theirs < mine)) {
            return false;
        }
    }
    return true;
}

bool probeFoot(Turtle corner, ref const Risen risen) {
    ulong own = corner.probeHash(SitePart.vertex);
    ulong foot = Turtle(corner.api, risen.foot).probeHash(SitePart.vertex);
    return own == foot;
}

bool probeTaken(Turtle corner, ref const Risen risen) {
    bool taken = corner.probeRising().exists;
    if (!taken && risen.hasRisen) {
        taken = probeFoot(corner, risen);
    }
    return taken;
}

bool probeOwnsFoot(Turtle face, ref const Risen risen) {
    foreach (corner; cornersOf(face)) {
        Turtle[AROUND] quarters = quartersOf(corner);
        bool foot = probeFoot(corner, risen);
        if (foot) {
            bool owner = probeOwner(quarters);
            if (owner) {
                return true;
            }
        }
    }
    return false;
}

bool probeRootVertex(Turtle site, ref const Root root) {
    ulong own = site.probeHash(SitePart.vertex);
    return own == root.vertex;
}

bool probeIsland(Turtle face, ref const Root root) {
    double rolled = roll(face.probeHash(SitePart.face), ISLAND_SALT);
    if (rolled >= tuning.island) {
        return false;
    } else {
        foreach (corner; cornersOf(face)) {
            bool rooted = probeRootVertex(corner, root);
            if (!rooted) {
                rooted = corner.probePort();
            }
            if (rooted) {
                return false;
            }
        }
        return true;
    }
}

bool probePlannedStreet(Turtle edge, ref const Root root) {
    bool planned = probeRootVertex(edge, root);
    if (!planned) {
        planned = probeRootVertex(edge.forward(1), root);
    }
    if (!planned) {
        planned = probeIsland(edge, root);
    }
    if (!planned) {
        planned = probeIsland(edge.left(), root);
    }
    if (!planned) {
        double rolled = roll(edge.probeHash(SitePart.edge), DROPPED_SALT);
        planned = rolled >= tuning.droppedStreet;
    }
    return planned;
}

bool probeKeptForAccess(Turtle edge, ref const Root root) {
    ulong mine = edge.probeHash(SitePart.edge);
    Turtle turtle = edge.right();
    foreach (index; 1 .. AROUND) {
        bool planned = probePlannedStreet(turtle, root);
        if (planned) {
            return false;
        }
        ulong theirs = turtle.probeHash(SitePart.edge);
        if (!(theirs < mine)) {
            return false;
        }
        turtle = turtle.right();
    }
    return true;
}

bool probeStreet(Turtle edge, ref const Root root) {
    bool paved = probePlannedStreet(edge, root);
    if (!paved) {
        paved = probeKeptForAccess(edge, root);
    }
    if (!paved) {
        paved = probeKeptForAccess(edge.forward(1).right().right(), root);
    }
    return paved;
}

bool probeTrees(Turtle edge) {
    double rolled = roll(edge.probeHash(SitePart.edge), TREES_SALT);
    return rolled < districtAt(edge).streetTrees;
}

int crossingGap(Turtle corner, ref const Root root) {
    bool paved = probeStreet(corner, root);
    if (paved) {
        return CROSSING + 1;
    } else {
        return 0;
    }
}

void sidewalk(Turtle edge, Span x, int startGap, int endGap) {
    edge.paint(materials.sidewalk, boxOf(x, Span(-1, 0), Span(startGap, edge.edgeCells() - 1 - endGap)));
}

void streetTrees(Turtle edge) {
    int last = edge.edgeCells() - 1;
    Span planted = Span(CROSSING + 4, last - CROSSING - 4);
    Rhythm trunk = Rhythm(TREE_SPACING, 6, 1);
    edge.paint(materials.leaves, boxOf(Span(CURB - 1, CURB + 1), Span(5, 6), planted), Rhythm(TREE_SPACING, 4, 5));
    edge.paint(materials.leaves, boxOf(Span(CURB - 1, CURB + 1), Span(7, 7), planted), Rhythm(TREE_SPACING, 5, 3));
    edge.paint(materials.leaves, boxOf(Span(CURB, CURB), Span(8, 8), planted), trunk);
    edge.paint(materials.trunk, boxOf(Span(CURB, CURB), Span(1, 5), planted), trunk);
}

int portGap(Turtle corner) {
    bool port = corner.probePort();
    if (port) {
        return PORT;
    } else {
        return 0;
    }
}

void street(Turtle edge, ref const Root root) {
    Turtle finish = edge.forward(1);
    int last = edge.edgeCells() - 1;
    int startPort = portGap(edge);
    int endPort = portGap(finish);
    edge.paint(materials.road, boxOf(ROAD, Span(-1, -1), Span(startPort, last - endPort)));
    sidewalk(edge, SIDEWALK, higherOf(startPort, crossingGap(edge.right(), root)), higherOf(endPort, crossingGap(finish.right(), root)));
    sidewalk(edge, FAR_SIDEWALK, higherOf(startPort, crossingGap(edge.left(), root)), higherOf(endPort, crossingGap(finish.left(), root)));
    bool crossedAtStart = probeStreet(edge.right(), root);
    if (!crossedAtStart) {
        crossedAtStart = probeStreet(edge.left(), root);
    }
    if (crossedAtStart && startPort == 0) {
        edge.paint(materials.marking, boxOf(ROAD, Span(-1, -1), Span(CROSSING + 1, CROSSING + 2)));
    }
    bool crossedAtEnd = probeStreet(finish.right(), root);
    if (!crossedAtEnd) {
        crossedAtEnd = probeStreet(finish.left(), root);
    }
    if (crossedAtEnd && endPort == 0) {
        edge.paint(materials.marking, boxOf(ROAD, Span(-1, -1), Span(last - CROSSING - 2, last - CROSSING - 1)));
    }
    bool trees = probeTrees(edge);
    if (trees) {
        streetTrees(edge);
    }
}

void tree(Turtle tower, int x, int y) {
    tower.paint(materials.leaves, boxOf(Span(x - 2, x + 2), Span(y - 1, y + 1), Span(5, 7)));
    tower.paint(materials.leaves, boxOf(Span(x - 1, x + 1), Span(y - 2, y + 2), Span(5, 7)));
    tower.paint(materials.leaves, boxOf(Span(x - 1, x + 1), Span(y - 1, y + 1), Span(8, 9)));
    tower.paint(materials.trunk, boxOf(Span(x, x), Span(y, y), Span(1, 7)));
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
    return Area(tower, Span(xLow, far), Span(yLow, far));
}

void pave(ref const Lots lots, Material material) {
    foreach (ref lot; lots.slice()) {
        Area area = groundOf(lot);
        area.tower.paint(material, boxOf(area.x, area.y, Span(-1, 0)));
    }
}

void paveAroundPort(ref const Lots lots, Material material) {
    foreach (ref lot; lots.slice()) {
        Area area = groundOf(lot);
        area.tower.paint(material, boxOf(Span(higherOf(area.x.low, PORT), area.x.high), area.y, Span(-1, 0)));
        if (area.x.low < PORT) {
            area.tower.paint(material, boxOf(Span(area.x.low, PORT - 1), Span(higherOf(area.y.low, PORT), area.y.high), Span(-1, 0)));
        }
    }
}

bool isRoomy(Area area) {
    return area.x.high - area.x.low >= 4 && area.y.high - area.y.low >= 4;
}

int centre(Span span) {
    return floorDiv(span.low + span.high + 1, 2);
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
    tower.paint(materials.basin, boxOf(Span(x - 2, x + 2), Span(y - 2, y + 2), Span(1, 1)));
    tower.paint(materials.water, boxOf(Span(x - 1, x + 1), Span(y - 1, y + 1), Span(1, 1)));
    tower.paint(materials.basin, boxOf(Span(x, x), Span(y, y), Span(1, 2)));
    tower.paint(materials.water, boxOf(Span(x, x), Span(y, y), Span(3, 3)));
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
            Span x = Span(area.x.low + 1, area.x.high - 1);
            Span y = Span(area.y.low + 1, area.y.high - 1);
            area.tower.paint(materials.water, boxOf(x, y, Span(-1, 0)));
            area.tower.paint(materials.pondBed, boxOf(x, y, Span(-2, -2)));
        }
    }
}

void parking(ref const Lots lots) {
    foreach (ref lot; lots.slice()) {
        Area area = groundOf(lot);
        area.tower.paint(materials.road, boxOf(area.x, area.y, Span(0, 0)));
        for (int x = area.x.low + 1; x <= area.x.high; x += PARKING_SPACING) {
            area.tower.paint(materials.marking, boxOf(Span(x, x), Span(area.y.low + 1, area.y.low + 3), Span(0, 0)));
        }
    }
}

struct Chosen {
    const(Traits)* traits;
    Spec spec;
}

Chosen chosenFor(Turtle site, ref const LotRule rule) {
    const(Traits)* traits = &rule.types.items[site.pick(rule.types.count)];
    Span range = traits.stories;
    int most = lowerOf(range.high, rule.mostStories);
    int count = site.pickBetween(range.low, most);
    int gap = 0;
    if (rule.shape == LotShape.run) {
        bool alley = site.rollChance(tuning.alleyPercent);
        if (alley) {
            gap = 1;
        }
    }
    int front = FRONT;
    if (rule.shape == LotShape.run) {
        front = FRONT + cast(int) site.pick(MAX_INSET + 1);
    }
    const(Palette)[] options = traits.palettes.slice();
    Spec spec = {stories: count, palette: options[site.pick(cast(uint) options.length)], front: front, gap: gap};
    return Chosen(traits, spec);
}

int fit(Turtle site, int stories) {
    int room = CROWN_ROOM + 1;
    int fitting = floorDiv(site.probeBalance(stories * STORY + room) - room, STORY);
    return lowerOf(stories, fitting);
}

Chosen fitted(Chosen chosen, Turtle site, ref const Root root) {
    Chosen result = chosen;
    if (root.isRisen()) {
        result.spec.stories = fit(site, chosen.spec.stories);
    }
    return result;
}

void build(ref const Lots lots, Chosen chosen) {
    pave(lots, materials.lot);
    types.build(*chosen.traits, lots, chosen.spec);
}

bool probePlaza(Turtle corner, ref const Root root) {
    bool plaza = probeRootVertex(corner, root) && root.isRisen();
    if (!plaza) {
        plaza = corner.probeRising().exists;
    }
    return plaza;
}

bool probeRoute(Turtle corner, ref const Lots lots, ref const Root root) {
    bool rooted = probeRootVertex(corner, root);
    if (rooted) {
        foreach (ref lot; lots.slice()) {
            ulong face = lot.site.probeHash(SitePart.face);
            if (face == root.face) {
                return true;
            }
        }
    }
    return false;
}

void lotAt(Turtle corner, ref const Lots lots, ref const Root root) {
    Turtle site = lots.items[0].site;
    bool plaza = probePlaza(corner, root);
    bool port = false;
    if (!plaza) {
        port = corner.probePort();
    }
    if (plaza) {
        pave(lots, materials.plaza);
        plant(lots);
    } else if (port) {
        paveAroundPort(lots, materials.plaza);
        plant(lots);
    } else {
        bool route = probeRoute(corner, lots, root);
        if (route) {
            Spec spec = {stories: ROUTE_BUILDING_STORIES, palette: zoning.route.palettes.items[0], front: FRONT, routeStories: ROUTE_STORIES};
            build(lots, Chosen(&zoning.route, spec));
        } else {
            rolledLot(site, lots, root);
        }
    }
}

void rolledLot(Turtle site, ref const Lots lots, ref const Root root) {
    const(District)* district = districtAt(site);
    bool park = site.rollChance(district.parkPercent);
    if (park) {
        pave(lots, materials.park);
        bool pond = site.rollChance(tuning.pondPercent);
        if (pond) {
            ponds(lots);
        } else {
            plant(lots);
        }
    } else {
        bool plaza = site.rollChance(district.plazaPercent);
        if (plaza) {
            pave(lots, materials.plaza);
            bool fountain = site.rollChance(tuning.fountainPercent);
            if (fountain) {
                fountains(lots);
            } else {
                plant(lots);
            }
        } else {
            bool parked = site.rollChance(district.parkingPercent);
            MaybeIndex!LotRule rule = ruleFor(*district, cast(uint) lots.count);
            if (parked) {
                parking(lots);
            } else if (!rule.exists) {
                pave(lots, materials.plaza);
                plant(lots);
            } else {
                Chosen chosen = fitted(chosenFor(site, district.rules.items[rule.value]), site, root);
                if (chosen.spec.stories >= 1) {
                    build(lots, chosen);
                } else {
                    pave(lots, materials.plaza);
                    plant(lots);
                }
            }
        }
    }
}

Lot lotOf(Turtle quarter, Flags!LotMark marks) {
    Lot lot;
    lot.site = quarter;
    lot.bounds = RUN_BOUNDS;
    if (marks.has(LotMark.streetAfter)) {
        lot.bounds[Side.xLow] = Bound.street;
    }
    if (marks.has(LotMark.streetBefore)) {
        lot.bounds[Side.yLow] = Bound.street;
    }
    if (marks.has(LotMark.first) && marks.has(LotMark.streetBefore)) {
        lot.front = Side.yLow;
    }
    return lot;
}

void join(ref Lots run) {
    foreach (index; 0 .. run.count) {
        if (run.items[index].bounds[Side.xLow] == Bound.joined) {
            uint next = cast(uint)((index + 1) % run.count);
            run.items[index].joins[Side.xLow] = Join(MaybeIndex!Lot.of(next), Side.yLow);
            run.items[next].joins[Side.yLow] = Join(MaybeIndex!Lot.of(cast(uint) index), Side.xLow);
        }
    }
}

void lotsAt(ref const Turtle[AROUND] quarters, ref const Root root) {
    bool foot = probeRootVertex(quarters[0], root);
    if (foot && root.isRisen()) {
        connect(quarters[0], root.risen, root.tag, root.connection);
    }
    uint start = 0;
    bool paved = false;
    while (start < AROUND && !paved) {
        paved = probeStreet(quarters[start], root);
        if (!paved) {
            start += 1;
        }
    }
    Lots run;
    foreach (step; 0 .. AROUND) {
        uint index = (start + step) % AROUND;
        uint after = (index + 1) % AROUND;
        bool isolated = probeIsland(quarters[index], root);
        bool streetAfter = probeStreet(quarters[after], root);
        if (!isolated) {
            bool streetBefore = probeStreet(quarters[index], root);
            Flags!LotMark marks;
            marks.put(LotMark.streetBefore, streetBefore);
            marks.put(LotMark.streetAfter, streetAfter);
            marks.put(LotMark.first, run.count == 0);
            run.add(lotOf(quarters[index], marks));
        }
        if (streetAfter || step == AROUND - 1) {
            if (run.count > 0) {
                join(run);
                lotAt(quarters[0], run, root);
            }
            run = Lots.init;
        }
    }
}

void island(ref const Turtle[FACE_CORNERS] corners, ref const Root root) {
    Lots parts;
    foreach (corner; corners) {
        Lot lot;
        lot.site = corner;
        lot.bounds = ISLAND_BOUNDS;
        parts.add(lot);
    }
    parts.items[0].front = Side.yLow;
    Chosen chosen = fitted(chosenFor(corners[0], districtAt(corners[0]).island), corners[0], root);
    if (chosen.spec.stories >= 1) {
        build(parts, chosen);
    } else {
        pave(parts, materials.plaza);
        plant(parts);
    }
}

Root rootAt(Turtle site) {
    return Root(site.probeHash(SitePart.vertex), site.probeHash(SitePart.face));
}

Root risenRootAt(Turtle foot, ref const Risen risen, uint tag, Connection how) {
    return Root(foot.probeHash(SitePart.vertex), foot.probeHash(SitePart.face), risen, how, tag);
}

void tile(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    tileAt(Turtle(api, site), *cast(const(Root)*) data);
}

void tileAt(Turtle face, ref const Root root) {
    Turtle[FACE_CORNERS] corners = cornersOf(face);
    ulong mine = face.probeHash(SitePart.face);
    foreach (edge; corners) {
        bool paved = probeStreet(edge, root);
        if (paved) {
            ulong beside = edge.left().probeHash(SitePart.face);
            if (mine > beside) {
                street(edge, root);
            }
        }
    }
    foreach (corner; corners) {
        Turtle[AROUND] quarters = quartersOf(corner);
        bool owner = probeOwner(quarters);
        if (owner) {
            lotsAt(quarters, root);
        }
    }
    bool isolated = probeIsland(face, root);
    if (isolated) {
        island(corners, root);
    }
}
