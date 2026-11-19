module plugins.lattice.lattice;

import core.stdc.math : fabs, sqrt;
import plugins.api.api : Api, Box, KindTag, Material, Rhythm, Risen, Site, SitePart, Span, tagNamed;
import plugins.api.binding : List, bound, settingsOf;
import plugins.api.content : Content;
import plugins.turtle.turtle : Along, FACE_CORNERS, Flight, Found, Lie, Tread, Turtle, boxOf, cornersOf, flightAt, floorMod, lowerOf, mixed, roll, strongestAround, treadAround, upright, wound;

enum int BEAM = 1;
enum int PLATFORM = 6;
enum int ROOT_PLATFORM = 10;
enum int POLE_RING = 3;
enum int POLE_TREADS = 4 * 2;
enum int MOST_FLIGHT_EDGES = 8;
enum ulong PLATFORM_SALT = 0x2F4A7C15;
enum ulong STAIR_SALT = 0x6B43A9B5;
enum ulong DECOR_SALT = 0x5BE0CD19;
enum ulong FLOOR_SALT = 0x1F83D9AB;
enum ulong WEAVE_SALT = 0x57454156;
enum ulong BROKEN_SALT = 0x42524B4E;
enum ulong DOUBLED_SALT = 0x44424C44;
enum ulong KEEP_SALT = 0x4B454550;
enum ulong BREAK_SALT = 0x4252414B;
enum ulong ISLAND_SALT = 0x49534C44;
enum ulong BREAK_ODDS = 81;
enum ulong COLOSSUS_SALT = 0x434F4C4F;
enum ulong HOLLOW_SALT = 0x484F4C4C;
enum ulong HOLLOW_ONE_IN = 3;
enum int HOLLOW_HALF = 3;
enum int LIMB_STEPS = 4;
enum int DOUBLE_GAP = 2;
enum int ISLAND_RADIUS = 9;
enum int ISLAND_DEPTH = 7;
enum int ISLAND_SOIL = 3;
enum int ISLAND_TRUNK = 5;
enum int BRIDGE_HALF = 1;
enum size_t MOST_WEAVES = 16;
enum double HANG_CLEAR = 4;
enum string LOOK = "lattice:look";
enum size_t MOST_FLOORS = 16;
enum ulong STAR_SALT = 0x53544152;
enum ulong STAR_ACROSS_SALT = 0x53544158;
enum ulong STAR_SIDE_SALT = 0x53544159;
enum ulong STAR_HEIGHT_SALT = 0x5354415A;
enum ulong TWIN_SALT = 0x5457494E;
enum ulong SUPPORT_SALT = 0x53555050;
enum ulong CLIMB_SALT = 0x434C494D;
enum int WALK_HALF = 2;
enum int RAFTER_EVERY = 6;
enum ulong SHELF_SALT = 0x53484C46;
enum ulong SHELF_LAYER_SALT = 0x53484C59;
enum ulong DECK_SALT = 0x4445434B;
enum ulong LAMP_SALT = 0x4C414D50;
enum ulong ASTEROID_SALT = 0x41535452;
enum ulong ASTEROID_SIZE_SALT = 0x4153535A;
enum ulong ASTEROID_ROCK_SALT = 0x4153524B;
immutable ulong[2] BOOK_SALTS = [0x424F4F4B, 0x424F4F32];
enum uint MAZE_TAG = tagNamed("lattice:maze");
enum ulong WALK_SALT = 0x57414C4B;
enum ulong SPOKE_SALT = 0x53504F4B;
immutable ulong[6] MAZE_STAR_SALTS = [0x4D535431, 0x4D535432, 0x4D535433, 0x4D535434, 0x4D535435, 0x4D535436];
immutable int[3] MAZE_STAR_SPACINGS = [5, 7, 9];
enum ulong STAR_SPACING_SALT = 0x53544153;
enum uint MAZE_WAYS = 4;
enum Span MAZE_DECK = Span(-1, -1);
enum int MAZE_RAFTER = -2;
enum int MAZE_HUB = 3;
enum int MAZE_SUPPORT_EDGES = 3;
enum int MAZE_ABYSS_EDGES = 3;
enum int MAZE_STAR_NEAREST = 12;
enum int MAZE_STAR_FARTHEST = 35;
enum int SHELF_HALF = 2;
enum int SHELF_DEPTH = 2;
enum int SHELF_EVERY = 6;
enum double ASTEROID_ABOVE = 0.7;
enum double ASTEROID_BELOW = 1.3;

enum Pattern : ubyte {
    rolled,
    regular,
}

struct Weave {
    int beam;
    double keep;
    double broken;
    double doubled;
    double platformOdds;
    double stairOdds;
    Pattern regular;
}

struct Materials {
    Material pole;
    Material girder;
    Material joint;
    Material step;
    Material lantern;
    Material leaves;
    Material hut;
    Material roof;
    List!(Material, MOST_FLOORS) floors;
    Material island;
    Material turf;
    Material soil;
    Material bridge;
    Material colossus;
    Material limb;
    List!(Weave, MOST_WEAVES) weaves;
    Material star;
    Material deck;
    Material rafter;
    Material shelf;
    List!(Material, MOST_FLOORS) shelfDecks;
    List!(Material, MOST_FLOORS) books;
    List!(Material, MOST_FLOORS) rocks;
}

__gshared Materials materials;

struct Tuning {
    double fog;
    double lanternOdds;
    double treeOdds;
    double hutOdds;
    double islandOdds;
    int colossusOneIn;
    double starOdds;
    double twinOdds;
    double mazeWalkOdds;
    double mazeSpokeOdds;
    double mazeSupportOdds;
    double mazeStarOdds;
    double shelfKeep;
    double shelfStairOdds;
    double lampOdds;
    double asteroidOdds;
    int asteroidLeast;
    int asteroidMost;
}

struct Band {
    double top;
    double bottom;
}

__gshared Tuning tuning;

void resolveLattice(const(Content)* content) {
    materials = content.bound!Materials("lattice:materials");
    tuning = content.settingsOf!Tuning("lattice");
}

enum Axis : ubyte {
    x,
    y,
    z,
}

immutable Axis[2] CROSS = [Axis.x, Axis.y];
immutable Axis[3] AXES = [Axis.x, Axis.y, Axis.z];
immutable int[2] SIGNS = [1, -1];

struct Root {
    ulong vertex;
}

struct End {
    Turtle frame;
    Axis vertical;
    ulong vertex;
    int sign;
}

Turtle along(Turtle frame, Axis axis, int sign) {
    final switch (axis) {
        case Axis.x:
            if (sign > 0) {
                return frame.right();
            } else {
                return frame.left();
            }
        case Axis.y:
            if (sign > 0) {
                return frame.pitchUp();
            } else {
                return frame.pitchDown();
            }
        case Axis.z:
            if (sign > 0) {
                return frame;
            } else {
                return frame.pitchUp().pitchUp();
            }
    }
}

double riseOf(Turtle frame, Axis axis) {
    final switch (axis) {
        case Axis.x:
            return frame.openPen().turn(90, 0).rise();
        case Axis.y:
            return frame.openPen().turn(0, 90).rise();
        case Axis.z:
            return frame.openPen().rise();
    }
}

Axis verticalOf(Turtle frame) {
    Axis steepest = Axis.z;
    double most = fabs(riseOf(frame, Axis.z));
    foreach (axis; CROSS) {
        double rise = fabs(riseOf(frame, axis));
        if (rise > most) {
            most = rise;
            steepest = axis;
        }
    }
    return steepest;
}

bool isStair(ulong edge, ref const Weave weave) {
    return roll(edge, STAIR_SALT) < weave.stairOdds;
}

bool probePlatform(ref const End end, ref const Root root, ref const Weave weave) {
    bool raised = end.vertex == root.vertex;
    if (!raised) {
        raised = isStair(along(end.frame, end.vertical, 1).probeHash(SitePart.edge), weave);
    }
    if (!raised) {
        raised = isStair(along(end.frame, end.vertical, -1).probeHash(SitePart.edge), weave);
    }
    return raised || roll(end.vertex, PLATFORM_SALT) < weave.platformOdds;
}

bool probeUpward(ref const End end) {
    double rise = riseOf(end.frame, Axis.z);
    return rise * end.sign > 0;
}

Span near(int sign, int from, int to) {
    if (sign > 0) {
        return Span(from, to);
    } else {
        return Span(-to - 1, -from - 1);
    }
}

Axis acrossOf(Axis vertical) {
    if (vertical == Axis.x) {
        return Axis.y;
    } else {
        return Axis.x;
    }
}

ulong lineHash(Turtle frame, Axis axis) {
    return lowerOf(along(frame, axis, 1).probeHash(SitePart.edge), along(frame, axis, -1).probeHash(SitePart.edge));
}

bool probeDesignated(ref const End end) {
    ulong own = lineHash(end.frame, Axis.z);
    ulong across = lineHash(end.frame, acrossOf(end.vertical));
    return own < across;
}

void platform(ref const End end, ref const Root root) {
    int reach = PLATFORM;
    if (end.vertex == root.vertex) {
        reach = ROOT_PLATFORM;
    }
    Material floor = materials.floors.items[cast(size_t)(roll(end.vertex, FLOOR_SALT) * materials.floors.count)];
    Span wide = Span(-reach, reach - 1);
    Span thin = Span(-BEAM, BEAM - 1);
    Span z = near(end.sign, BEAM, reach - 1);
    if (end.vertical == Axis.y) {
        end.frame.fill(floor, boxOf(wide, thin, z));
    } else {
        end.frame.fill(floor, boxOf(thin, wide, z));
    }
}

void decorate(ref const End end) {
    double choice = roll(end.vertex, DECOR_SALT);
    Turtle frame = end.frame;
    int sign = end.sign;
    if (choice < tuning.lanternOdds) {
        frame.paint(materials.lantern, boxOf(Span(-2, 1), Span(-2, 1), near(sign, 3, 4)));
    } else if (choice < tuning.treeOdds) {
        frame.fill(materials.leaves, boxOf(Span(-4, 3), Span(-4, 3), near(sign, 3, 6)));
        frame.fill(materials.leaves, boxOf(Span(-2, 1), Span(-2, 1), near(sign, 7, 8)));
    } else if (choice < tuning.hutOdds) {
        Span walls = near(sign, 1, 5);
        frame.paint(materials.hut, boxOf(Span(-5, 4), Span(-5, -5), walls));
        frame.paint(materials.hut, boxOf(Span(-5, 4), Span(4, 4), walls));
        frame.paint(materials.hut, boxOf(Span(-5, -5), Span(-4, 3), walls));
        frame.paint(materials.hut, boxOf(Span(4, 4), Span(-4, 3), walls));
        frame.paint(Material.none, boxOf(Span(4, 4), Span(-1, 0), near(sign, 1, 3)));
        frame.paint(materials.roof, boxOf(Span(-6, 5), Span(-6, 5), near(sign, 6, 6)));
    }
}

Turtle upwardOf(Turtle start) {
    if (riseOf(start, Axis.z) > 0) {
        return start;
    } else {
        return start.forward(1).pitchUp().pitchUp();
    }
}

bool isClimbed(ulong edge, ref const Weave weave) {
    final switch (weave.regular) {
        case Pattern.rolled:
            return isStair(edge, weave);
        case Pattern.regular:
            return mixed(edge, BREAK_SALT) % BREAK_ODDS != 0;
    }
}

bool isShelfClimbed(ulong edge) {
    return roll(edge, CLIMB_SALT) < tuning.shelfStairOdds;
}

void spiral(alias climbs)(Turtle start, int length, int inner) {
    Turtle up = upwardOf(start);
    int below = 1;
    while (below <= MOST_FLIGHT_EDGES && climbs(up.forward(-below).probeHash(SitePart.edge))) {
        below += 1;
    }
    if (below <= MOST_FLIGHT_EDGES) {
        int under = below - 1;
        Flight flight = flightAt(up.forward(-under));
        Turtle frame = flight.frame.forward(under);
        foreach (index; 0 .. POLE_TREADS) {
            Tread tread = wound(treadAround(inner, POLE_RING, 1, index), flight.winding);
            frame.paint(materials.step, boxOf(tread.x, tread.y, Span(1, length - 2)), Rhythm(POLE_TREADS, floorMod(index - under * length, POLE_TREADS), 1));
        }
    }
}

End endAt(Turtle frame, int sign) {
    return End(frame, verticalOf(frame), frame.probeHash(SitePart.vertex), sign);
}

void edge(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    beam(Turtle(api, site), *cast(const(Root)*) data, materials.weaves.items[0]);
}

const(Weave)* weaveAt(Turtle start) {
    return &materials.weaves.items[mixed(strongestAround(start), WEAVE_SALT) % materials.weaves.count];
}

struct Strut {
    Span length;
    Material material;
    Found doubled;
    Found stair;
}

Strut strutOf(Turtle start, ref const Weave weave, Axis vertical, int length) {
    ulong hash = start.probeHash(SitePart.edge);
    Strut strut = Strut(Span(1, length - 2), materials.girder, Found.none, Found.none);
    if (vertical == Axis.z) {
        strut.material = materials.pole;
    }
    final switch (weave.regular) {
        case Pattern.rolled:
            if (roll(hash, BROKEN_SALT) < weave.broken) {
                strut.length = Span(1, length / 2);
            }
            if (roll(hash, DOUBLED_SALT) < weave.doubled) {
                strut.doubled = Found.some;
            }
            if (vertical == Axis.z && isStair(hash, weave)) {
                strut.stair = Found.some;
            }
            break;
        case Pattern.regular:
            bool wrong = mixed(strongestAround(start), BREAK_SALT) % BREAK_ODDS == 0 || mixed(hash, BREAK_SALT) % BREAK_ODDS == 0;
            if (vertical == Axis.z && !wrong) {
                strut.stair = Found.some;
            } else if (vertical == Axis.x && !wrong) {
                strut.doubled = Found.some;
            } else if (wrong && vertical != Axis.z) {
                strut.length = Span(1, length / 2);
            }
            break;
    }
    return strut;
}

bool isKept(Turtle start, ref const Weave weave) {
    return weave.keep >= 1 || roll(start.probeHash(SitePart.edge), KEEP_SALT) < weave.keep;
}

void beam(Turtle start, ref const Root root, ref const Weave weave) {
    if (isKept(start, weave)) {
        lay(start, root, weave);
    }
}

void lay(Turtle start, ref const Root root, ref const Weave weave) {
    int length = start.edgeCells();
    Span cross = Span(-weave.beam, weave.beam - 1);
    End[2] ends = [endAt(start, 1), endAt(start.forward(1), -1)];
    Strut strut = strutOf(start, weave, ends[0].vertical, length);
    foreach (end; ends) {
        bool raised = probePlatform(end, root, weave);
        if (raised && end.vertical == Axis.z && strut.stair == Found.none) {
            bool upward = probeUpward(end);
            if (upward) {
                decorate(end);
            }
        }
    }
    start.fill(strut.material, boxOf(cross, cross, strut.length));
    if (strut.doubled == Found.some) {
        Span beside = Span(weave.beam + DOUBLE_GAP, 2 * weave.beam + DOUBLE_GAP - 1);
        start.fill(strut.material, boxOf(beside, cross, strut.length));
    }
    start.fill(materials.joint, boxOf(cross, cross, Span(0, 0)));
    start.fill(materials.joint, boxOf(cross, cross, Span(length - 1, length - 1)));
    if (strut.stair == Found.some) {
        bool climbs(ulong edge) {
            return isClimbed(edge, weave);
        }
        spiral!climbs(start, length, BEAM);
    }
    foreach (end; ends) {
        bool raised = probePlatform(end, root, weave);
        if (raised && end.vertical != Axis.z) {
            bool designated = probeDesignated(end);
            if (designated) {
                platform(end, root);
            }
        }
    }
}

bool probeOpen(Turtle end, double height) {
    if (!(height < -HANG_CLEAR)) {
        return false;
    } else {
        return height < -(end.probeCrust() * end.edgeCells() + HANG_CLEAR);
    }
}

void hang(Turtle start, Lie lie, double abyss) {
    double bottom = -abyss * start.edgeCells();
    bool open = probeOpen(start, lie.near);
    if (!open) {
        open = probeOpen(start.forward(1), lie.far);
    }
    if (open && (lie.near > bottom || lie.far > bottom)) {
        Root root;
        beam(start, root, *weaveAt(start));
    }
}

bool isIsland(ulong vertex) {
    return roll(vertex, ISLAND_SALT) < tuning.islandOdds;
}

void octagon(Turtle frame, Material material, int half, Span z) {
    if (half > 0) {
        int cut = (half * 10 + 8) / 17;
        frame.fill(material, boxOf(Span(-half, half - 1), Span(cut - half, half - cut - 1), z));
        frame.fill(material, boxOf(Span(cut - half, half - cut - 1), Span(-half, half - 1), z));
    }
}

void island(Turtle down) {
    int top = ISLAND_TRUNK + 5;
    foreach (step; 0 .. ISLAND_DEPTH) {
        int half = ISLAND_RADIUS - (step * step * ISLAND_RADIUS) / (ISLAND_DEPTH * ISLAND_DEPTH);
        Material material = materials.island;
        if (step == 0) {
            material = materials.turf;
        } else if (step < ISLAND_SOIL) {
            material = materials.soil;
        }
        octagon(down, material, half, Span(top + step, top + step));
    }
    down.fill(materials.joint, boxOf(Span(-1, 0), Span(-1, 0), Span(top - ISLAND_TRUNK, top - 1)));
    down.fill(materials.leaves, boxOf(Span(-3, 2), Span(-3, 2), Span(top - ISLAND_TRUNK - 3, top - ISLAND_TRUNK)));
    down.fill(materials.leaves, boxOf(Span(-2, 1), Span(-2, 1), Span(top - ISLAND_TRUNK - 4, top - ISLAND_TRUNK - 4)));
}

void drift(Turtle start, Lie lie, double abyss) {
    double bottom = -abyss * start.edgeCells();
    bool open = probeOpen(start, lie.near) && probeOpen(start.forward(1), lie.far);
    if (open && (lie.near > bottom || lie.far > bottom)) {
        ulong first = start.probeHash(SitePart.vertex);
        ulong second = start.forward(1).probeHash(SitePart.vertex);
        if (verticalOf(start) == Axis.z) {
            Turtle down = start;
            ulong top = first;
            if (riseOf(start, Axis.z) > 0) {
                down = start.forward(1).pitchUp().pitchUp();
                top = second;
            }
            if (isIsland(top)) {
                island(down);
            }
        } else if (isIsland(first) && isIsland(second)) {
            Span walk = Span(-BRIDGE_HALF, BRIDGE_HALF - 1);
            start.fill(materials.bridge, boxOf(walk, walk, Span(ISLAND_RADIUS / 2, start.edgeCells() - ISLAND_RADIUS / 2)));
        }
    }
}

struct Neighbor {
    Turtle frame;
    ulong vertex;
}

Neighbor highestAround(Turtle frame) {
    Neighbor best = Neighbor(frame, 0);
    foreach (axis; AXES) {
        foreach (sign; SIGNS) {
            Turtle next = along(frame, axis, sign).forward(1);
            ulong vertex = next.probeHash(SitePart.vertex);
            if (vertex > best.vertex) {
                best = Neighbor(next, vertex);
            }
        }
    }
    return best;
}

int stepsToTrunk(Turtle frame, ulong vertex) {
    Turtle at = frame;
    ulong here = vertex;
    Neighbor up = highestAround(at);
    int steps = 0;
    while (steps < LIMB_STEPS && up.vertex > here) {
        at = up.frame;
        here = up.vertex;
        up = highestAround(at);
        steps += 1;
    }
    return steps;
}

void branch(Turtle start, Lie lie, double abyss) {
    if (probeOpenEdge(start, lie, abyss)) {
        int length = start.edgeCells();
        Turtle end = start.forward(1);
        ulong first = start.probeHash(SitePart.vertex);
        ulong second = end.probeHash(SitePart.vertex);
        Turtle child = start;
        ulong childVertex = first;
        ulong other = second;
        if (second < first) {
            child = end;
            childVertex = second;
            other = first;
        }
        if (highestAround(child).vertex == other) {
            int half = LIMB_STEPS + 1 - stepsToTrunk(child, childVertex);
            Span limb = Span(-half, half - 1);
            start.fill(materials.limb, boxOf(limb, limb, Span(0, length - 1)));
        }
    }
}

bool isColossal(ulong line) {
    return mixed(line, COLOSSUS_SALT) % cast(ulong) tuning.colossusOneIn == 0;
}

void colossus(Turtle start, Lie lie, double abyss) {
    ulong line = start.probeHash(SitePart.line);
    if (isColossal(line)) {
        int length = start.edgeCells();
        if (probeOpenEdge(start, lie, abyss)) {
            Span whole = start.column();
            start.fill(materials.colossus, boxOf(whole, whole, Span(0, length - 1)));
            if (mixed(line, HOLLOW_SALT) % HOLLOW_ONE_IN == 0) {
                Span hollow = Span(-HOLLOW_HALF, HOLLOW_HALF - 1);
                start.paint(Material.none, boxOf(hollow, hollow, Span(0, length - 1)));
            }
        }
    }
}

bool probeOpenEdge(Turtle start, Lie lie, double abyss) {
    double bottom = -abyss * start.edgeCells();
    if (!(lie.near > bottom || lie.far > bottom)) {
        return false;
    } else {
        return probeOpen(start, lie.near) && probeOpen(start.forward(1), lie.far);
    }
}

void stars(Turtle start, Lie lie, double abyss) {
    ulong edge = start.probeHash(SitePart.edge);
    if (roll(edge, STAR_SALT) < tuning.starOdds && probeOpenEdge(start, lie, abyss)) {
        Span column = start.column();
        ulong width = column.high - column.low + 1;
        int x = column.low + cast(int)(mixed(edge, STAR_ACROSS_SALT) % width);
        int y = column.low + cast(int)(mixed(edge, STAR_SIDE_SALT) % width);
        int z = cast(int)(mixed(edge, STAR_HEIGHT_SALT) % cast(ulong)(start.edgeCells() - 1));
        int twin = 0;
        if (roll(edge, TWIN_SALT) < tuning.twinOdds) {
            twin = 1;
        }
        start.fill(materials.star, boxOf(Span(x, x), Span(y, y), Span(z, z + twin)));
    }
}

bool isWalked(ulong edge) {
    return roll(edge, WALK_SALT) < tuning.mazeWalkOdds;
}

bool isSpoke(ulong edge) {
    return roll(edge, SPOKE_SALT) < tuning.mazeSpokeOdds;
}

Turtle[MAZE_WAYS] waysAt(Turtle corner) {
    return [corner, corner.right(), corner.right().right(), corner.left()];
}

bool probeSupport(Turtle corner) {
    if (!(roll(corner.probeHash(SitePart.vertex), SUPPORT_SALT) < tuning.mazeSupportOdds)) {
        return false;
    } else {
        Turtle[MAZE_WAYS] ways = waysAt(corner);
        uint index = 0;
        while (index < MAZE_WAYS && !isWalked(ways[index].probeHash(SitePart.edge))) {
            index += 1;
        }
        return index < MAZE_WAYS;
    }
}

void deck(Turtle quarter, Box area) {
    quarter.fill(materials.deck, area);
}

void rafters(Turtle quarter, Along along) {
    int far = quarter.column().high;
    Span walk = Span(0, WALK_HALF - 1);
    Span under = Span(MAZE_RAFTER, MAZE_RAFTER);
    int at = 0;
    while (at <= far) {
        if (along == Along.x) {
            quarter.fill(materials.rafter, boxOf(Span(at, at), walk, under));
        } else {
            quarter.fill(materials.rafter, boxOf(walk, Span(at, at), under));
        }
        at += RAFTER_EVERY;
    }
}

void mazeStar(Turtle quarter, ulong hash, ulong salt) {
    if (roll(hash, salt) < tuning.mazeStarOdds) {
        ulong width = quarter.column().high + 1;
        int x = cast(int)(mixed(hash, salt ^ STAR_ACROSS_SALT) % width);
        int y = cast(int)(mixed(hash, salt ^ STAR_SIDE_SALT) % width);
        int every = MAZE_STAR_SPACINGS[mixed(hash, salt ^ STAR_SPACING_SALT) % MAZE_STAR_SPACINGS.length];
        int from = cast(int)(mixed(hash, salt ^ STAR_HEIGHT_SALT) % cast(ulong) every);
        quarter.fill(materials.star, boxOf(Span(x, x), Span(y, y), Span(-MAZE_STAR_FARTHEST, -MAZE_STAR_NEAREST)), Rhythm(every, from, 1));
    }
}

int mazeAbove(Turtle at) {
    return MAZE_SUPPORT_EDGES * at.edgeCells();
}

void maze(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    Turtle face = Turtle(api, site);
    ulong faceHash = face.probeHash(SitePart.face);
    Turtle[FACE_CORNERS] corners = cornersOf(face);
    ulong[FACE_CORNERS] edges;
    Found hub = Found.none;
    foreach (index, corner; corners) {
        edges[index] = corner.probeHash(SitePart.edge);
        if (isSpoke(edges[index])) {
            hub = Found.some;
        }
    }
    foreach (index, corner; corners) {
        Turtle quarter = upright(corner);
        int far = quarter.column().high;
        Span walk = Span(0, WALK_HALF - 1);
        Span inner = Span(far - WALK_HALF + 1, far);
        Span whole = Span(0, far);
        ulong after = edges[index];
        ulong before = edges[(index + FACE_CORNERS - 1) % FACE_CORNERS];
        if (isWalked(after)) {
            deck(quarter, boxOf(whole, walk, MAZE_DECK));
            rafters(quarter, Along.x);
        }
        if (isWalked(before)) {
            deck(quarter, boxOf(walk, whole, MAZE_DECK));
            rafters(quarter, Along.y);
        }
        if (isSpoke(after)) {
            deck(quarter, boxOf(inner, whole, MAZE_DECK));
        }
        if (isSpoke(before)) {
            deck(quarter, boxOf(whole, inner, MAZE_DECK));
        }
        if (hub == Found.some) {
            Span middle = Span(far - MAZE_HUB + 1, far);
            deck(quarter, boxOf(middle, middle, MAZE_DECK));
        }
        if (probeSupport(corner)) {
            quarter.fill(materials.rafter, boxOf(Span(0, 0), Span(0, 0), Span(0, mazeAbove(quarter) - 1)));
        }
        ulong spot = corner.probeHash(SitePart.vertex) ^ faceHash;
        foreach (salt; MAZE_STAR_SALTS) {
            mazeStar(quarter, spot, salt);
        }
    }
}

void hangMaze(const(Api)* api, KindTag ground) {
    api.tileReach(api, ground, MAZE_SUPPORT_EDGES * api.edgeCells(api), MAZE_STAR_FARTHEST + 1);
    api.abyss(api, ground, MAZE_ABYSS_EDGES);
}

Material pickOf(ref const List!(Material, MOST_FLOORS) list, ulong hash, ulong salt) {
    return list.items[mixed(hash, salt) % list.count];
}

Axis upOf(Turtle start) {
    if (fabs(riseOf(start, Axis.x)) > fabs(riseOf(start, Axis.y))) {
        return Axis.x;
    } else {
        return Axis.y;
    }
}

int downOf(Turtle start, Axis up) {
    if (riseOf(start, up) < 0) {
        return 1;
    } else {
        return -1;
    }
}

void bookcase(Turtle start, ulong edge) {
    int length = start.edgeCells();
    Span core = Span(-SHELF_HALF, SHELF_HALF - 1);
    Span inner = Span(1 - SHELF_HALF, SHELF_HALF - 2);
    Span along = Span(0, length - 1);
    start.fill(materials.shelf, boxOf(core, core, along));
    foreach (index, salt; BOOK_SALTS) {
        Material book = pickOf(materials.books, edge, salt);
        Rhythm row = Rhythm(2 * SHELF_EVERY, 1 + cast(int) index * SHELF_EVERY, SHELF_EVERY - 1);
        start.fill(book, boxOf(core, inner, along), row);
        start.fill(book, boxOf(inner, core, along), row);
    }
    if (isShelfClimbed(edge)) {
        spiral!isShelfClimbed(start, length, SHELF_HALF);
    }
}

Box acrossOf(Axis up, Span wide, Span height, Span along) {
    if (up == Axis.y) {
        return boxOf(wide, height, along);
    } else {
        return boxOf(height, wide, along);
    }
}

void shelf(Turtle start, ulong edge) {
    int length = start.edgeCells();
    Axis up = upOf(start);
    int down = downOf(start, up);
    Span wide = Span(-SHELF_HALF, SHELF_HALF - 1);
    Span along = Span(0, length - 1);
    Span body = near(down, 1, SHELF_DEPTH);
    start.fill(pickOf(materials.shelfDecks, edge, DECK_SALT), acrossOf(up, wide, near(down, 0, 0), along));
    start.fill(materials.shelf, acrossOf(up, wide, body, along));
    foreach (index, salt; BOOK_SALTS) {
        Rhythm row = Rhythm(2 * SHELF_EVERY, 1 + cast(int) index * SHELF_EVERY, SHELF_EVERY - 1);
        start.fill(pickOf(materials.books, edge, salt), acrossOf(up, wide, body, along), row);
    }
    start.fill(materials.shelf, acrossOf(up, wide, near(down, 0, SHELF_DEPTH), Span(0, 0)));
    start.fill(materials.shelf, acrossOf(up, wide, near(down, 0, SHELF_DEPTH), Span(length - 1, length - 1)));
    if (roll(edge, LAMP_SALT) < tuning.lampOdds) {
        int middle = length / 2;
        start.fill(materials.lantern, acrossOf(up, Span(-1, 0), near(down, SHELF_DEPTH + 1, SHELF_DEPTH + 1), Span(middle, middle)));
    }
}

void shelves(Turtle start, Lie lie, double abyss) {
    ulong edge = start.probeHash(SitePart.edge);
    double bottom = -abyss * start.edgeCells();
    if (roll(edge, SHELF_SALT) < tuning.shelfKeep && (lie.near > bottom || lie.far > bottom)) {
        bool open = probeOpen(start, lie.near) || probeOpen(start.forward(1), lie.far);
        if (open && verticalOf(start) == Axis.z) {
            bookcase(start, edge);
        } else if (open) {
            shelf(start, edge);
        }
    }
}

int halfAt(int radius, int reach, int level) {
    double share = cast(double) level / (reach + 1);
    return cast(int)(radius * sqrt(1 - share * share) + 0.5);
}

void lump(Turtle end, Material rock, int radius, double squash) {
    int reach = lowerOf(cast(int)(radius * squash), end.edgeCells() - 1);
    int from = 0;
    int half = radius;
    foreach (level; 1 .. reach + 1) {
        int next = halfAt(radius, reach, level);
        if (next != half) {
            octagon(end, rock, half, Span(from, level - 1));
            from = level;
            half = next;
        }
    }
    octagon(end, rock, half, Span(from, reach));
}

void asteroidAt(Turtle end, double height, Band band) {
    ulong vertex = end.probeHash(SitePart.vertex);
    if (roll(vertex, ASTEROID_SALT) < tuning.asteroidOdds && verticalOf(end) == Axis.z) {
        double depth = -height / end.edgeCells() - end.probeCrust();
        if (depth >= band.top && depth < band.bottom) {
            ulong sizes = tuning.asteroidMost - tuning.asteroidLeast + 1;
            int radius = tuning.asteroidLeast + cast(int)(mixed(vertex, ASTEROID_SIZE_SALT) % sizes);
            double squash = ASTEROID_BELOW;
            if (riseOf(end, Axis.z) > 0) {
                squash = ASTEROID_ABOVE;
            }
            lump(end, pickOf(materials.rocks, vertex, ASTEROID_ROCK_SALT), radius, squash);
        }
    }
}

void asteroids(Turtle start, Lie lie, Band band) {
    asteroidAt(start, lie.near, band);
    asteroidAt(start.forward(1).pitchUp().pitchUp(), lie.far, band);
}

void bookVoid(Turtle start, Lie lie, double shelfLayer, double abyss) {
    double below = -lowerOf(lie.near, lie.far) / start.edgeCells() - start.probeCrust();
    double shift = roll(start.probeHash(SitePart.edge), SHELF_LAYER_SALT) - 0.5;
    if (below < shelfLayer + shift) {
        shelves(start, lie, abyss);
    }
    asteroids(start, lie, Band(shelfLayer, abyss));
    stars(start, lie, abyss);
}

void deepen(const(Api)* api, KindTag ground) {
    api.underCrust(api, ground, LOOK, 0, tuning.fog);
}

