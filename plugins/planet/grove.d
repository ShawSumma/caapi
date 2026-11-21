module plugins.planet.grove;

import plugins.api.api : Material, Rhythm, SitePart, Span;
import plugins.api.binding : bound, settingsOf;
import plugins.api.content : Content;
import plugins.turtle.turtle : FACE_CORNERS, Tread, Turtle, boxOf, cornersOf, middle, roll, treadAround, upright;

enum ulong HUT_SALT = 0x2D7F1E93;
enum ulong CROWN_SALT = 0x6A09E667;
enum ulong VINE_SALT = 0x510E527F;
enum int CANOPY = 15;
enum int TRUNK_TOP = CANOPY + 5;
enum int STAIR_CENTER = 4;
enum int STAIR_INNER = 1;
enum int STAIR_WIDTH = 3;
enum int STAIR_SIDES = 1;
enum int STAIR_TREADS = 4 * (STAIR_SIDES + 1);
enum int STAIR_OPENING = 5;
enum Span TRUNK = Span(STAIR_CENTER - 1, STAIR_CENTER);
enum Span DECK = Span(0, 8);
enum Span WALK = Span(0, 3);
enum Span HUT = Span(1, 7);
enum Span DOOR = Span(2, 3);
enum int HUT_WALLS = 4;
enum int CROWN_LOW = 3;
enum int CROWN_HIGH = 6;
enum int CROWN_TOP = 8;
enum int LANTERN_INSET = 2;
enum int LANTERN_DROP = 2;
enum int LEAST_VINE = 2;
enum int MOST_VINE = 6;
immutable int[2] VINES = [1, 3];

struct Materials {
    Material trunk;
    Material deck;
    Material step;
    Material rail;
    Material vine;
    Material lantern;
    Material chain;
    Material hut;
    Material roof;
    Material leaves;
}

__gshared Materials materials;

struct Tuning {
    double groveHutOdds;
    double groveCrownOdds;
}

__gshared Tuning tuning;

void resolveGrove(const(Content)* content) {
    materials = content.bound!Materials("planet:grove");
    tuning = content.settingsOf!Tuning("planet");
}

enum Crown : ubyte {
    bare,
    hut,
    leaves,
}

Crown crownOf(ulong vertex) {
    if (roll(vertex, HUT_SALT) < tuning.groveHutOdds) {
        return Crown.hut;
    } else if (roll(vertex, CROWN_SALT) < tuning.groveCrownOdds) {
        return Crown.leaves;
    } else {
        return Crown.bare;
    }
}

Tread treadAt(int index) {
    Tread around = treadAround(STAIR_INNER, STAIR_WIDTH, STAIR_SIDES, index);
    return Tread(Span(around.x.low + STAIR_CENTER, around.x.high + STAIR_CENTER), Span(around.y.low + STAIR_CENTER, around.y.high + STAIR_CENTER));
}

void stair(Turtle tower) {
    Span ring = Span(STAIR_CENTER - STAIR_INNER - STAIR_WIDTH, STAIR_CENTER + STAIR_INNER + STAIR_WIDTH - 1);
    tower.paint(Material.none, boxOf(ring, ring, Span(0, CANOPY - 1)));
    foreach (index; 0 .. STAIR_TREADS) {
        Tread tread = treadAt(index);
        tower.paint(materials.step, boxOf(tread.x, tread.y, Span(0, CANOPY - 1)), Rhythm(STAIR_TREADS, index, 1));
    }
    foreach (below; 1 .. STAIR_OPENING + 1) {
        Tread tread = treadAt(CANOPY - below);
        tower.paint(Material.none, boxOf(tread.x, tread.y, Span(CANOPY, CANOPY)));
    }
    tower.paint(materials.trunk, boxOf(TRUNK, TRUNK, Span(0, TRUNK_TOP)));
}

void deck(Turtle tower) {
    int far = tower.column().high;
    Span walkway = Span(DECK.high + 1, far);
    Span rail = Span(CANOPY + 1, CANOPY + 1);
    tower.paint(materials.deck, boxOf(DECK, DECK, Span(CANOPY, CANOPY)));
    tower.paint(materials.deck, boxOf(walkway, WALK, Span(CANOPY, CANOPY)));
    tower.paint(materials.deck, boxOf(WALK, walkway, Span(CANOPY, CANOPY)));
    tower.paint(materials.rail, boxOf(Span(0, far), Span(0, 0), rail));
    tower.paint(materials.rail, boxOf(Span(0, 0), Span(0, far), rail));
    tower.paint(materials.rail, boxOf(walkway, Span(WALK.high, WALK.high), rail));
    tower.paint(materials.rail, boxOf(Span(WALK.high, WALK.high), walkway, rail));
    tower.paint(materials.rail, boxOf(Span(DECK.high, DECK.high), Span(WALK.high + 1, DECK.high), rail));
    tower.paint(materials.rail, boxOf(Span(WALK.high + 1, DECK.high), Span(DECK.high, DECK.high), rail));
}

void lanterns(Turtle tower) {
    int at = tower.column().high - LANTERN_INSET;
    Span hung = Span(WALK.low + 1, WALK.low + 1);
    tower.paint(materials.chain, boxOf(Span(at, at), hung, Span(CANOPY - 1, CANOPY - 1)));
    tower.paint(materials.lantern, boxOf(Span(at, at), hung, Span(CANOPY - LANTERN_DROP, CANOPY - LANTERN_DROP)));
    tower.paint(materials.chain, boxOf(hung, Span(at, at), Span(CANOPY - 1, CANOPY - 1)));
    tower.paint(materials.lantern, boxOf(hung, Span(at, at), Span(CANOPY - LANTERN_DROP, CANOPY - LANTERN_DROP)));
}

void vines(Turtle tower, ulong vertex) {
    foreach (index, offset; VINES) {
        int x = DECK.high + offset;
        int length = LEAST_VINE + cast(int)(roll(vertex, VINE_SALT + index) * (MOST_VINE - LEAST_VINE + 1));
        Span hanging = Span(CANOPY - length, CANOPY - 1);
        tower.fill(materials.vine, boxOf(Span(x, x), Span(WALK.high, WALK.high), hanging));
        tower.fill(materials.vine, boxOf(Span(WALK.high, WALK.high), Span(x, x), hanging));
    }
}

void hut(Turtle tower) {
    Span walls = Span(CANOPY + 1, CANOPY + HUT_WALLS);
    tower.paint(Material.none, boxOf(Span(HUT.low + 1, HUT.high - 1), Span(HUT.low + 1, HUT.high - 1), walls));
    tower.paint(materials.hut, boxOf(HUT, Span(HUT.low, HUT.low), walls));
    tower.paint(materials.hut, boxOf(HUT, Span(HUT.high, HUT.high), walls));
    tower.paint(materials.hut, boxOf(Span(HUT.low, HUT.low), HUT, walls));
    tower.paint(materials.hut, boxOf(Span(HUT.high, HUT.high), HUT, walls));
    tower.paint(Material.none, boxOf(Span(HUT.high, HUT.high), DOOR, Span(CANOPY + 1, CANOPY + HUT_WALLS - 1)));
    tower.paint(Material.none, boxOf(DOOR, Span(HUT.high, HUT.high), Span(CANOPY + 2, CANOPY + 2)));
    tower.paint(materials.roof, boxOf(DECK, DECK, Span(CANOPY + HUT_WALLS + 1, CANOPY + HUT_WALLS + 1)));
    tower.paint(materials.trunk, boxOf(TRUNK, TRUNK, Span(CANOPY + 1, CANOPY + HUT_WALLS)));
}

void leafCrown(Turtle tower) {
    Span wide = Span(DECK.low + 1, DECK.high - 2);
    Span narrow = Span(DECK.low + 2, DECK.high - 3);
    tower.fill(materials.leaves, boxOf(wide, wide, Span(CANOPY + CROWN_LOW, CANOPY + CROWN_HIGH)));
    tower.fill(materials.leaves, boxOf(narrow, narrow, Span(CANOPY + CROWN_HIGH + 1, CANOPY + CROWN_TOP)));
}

enum Foot : ubyte {
    free,
    risen,
}

Foot footOf(Turtle corner) {
    if (corner.probeRising().exists) {
        return Foot.risen;
    } else {
        return Foot.free;
    }
}

bool isStairBefore(Turtle corner, Turtle other) {
    Foot own = footOf(corner);
    Foot theirs = footOf(other);
    if (own != theirs) {
        return own < theirs;
    } else {
        return corner.probeHash(SitePart.vertex) < other.probeHash(SitePart.vertex);
    }
}

size_t stairCorner(ref const Turtle[FACE_CORNERS] corners) {
    size_t least = 0;
    foreach (index; 1 .. FACE_CORNERS) {
        if (isStairBefore(corners[index], corners[least])) {
            least = index;
        }
    }
    return least;
}

void aboveCorner(Turtle corner) {
    Turtle[FACE_CORNERS] corners = cornersOf(corner);
    Turtle tower = upright(corner);
    ulong vertex = corner.probeHash(SitePart.vertex);
    tower.paint(materials.trunk, boxOf(TRUNK, TRUNK, Span(0, TRUNK_TOP)));
    deck(tower);
    lanterns(tower);
    vines(tower, vertex);
    if (stairCorner(corners) == 0) {
        stair(tower);
    } else {
        final switch (crownOf(vertex)) {
            case Crown.hut:
                hut(tower);
                break;
            case Crown.leaves:
                leafCrown(tower);
                break;
            case Crown.bare:
                break;
        }
    }
}

void belowCorner(Turtle corner) {
    Turtle[FACE_CORNERS] corners = cornersOf(corner);
    Turtle tower = upright(corner);
    Span footing = Span(-tower.edgeCells(), -1);
    tower.fill(materials.trunk, boxOf(TRUNK, TRUNK, footing));
    if (stairCorner(corners) == 0) {
        foreach (index; 0 .. STAIR_TREADS) {
            Tread tread = treadAt(index);
            tower.fill(materials.step, boxOf(tread.x, tread.y, footing), Rhythm(STAIR_TREADS, index, 1));
        }
    }
}

void grove(Turtle face) {
    foreach (corner; cornersOf(face)) {
        belowCorner(corner);
        aboveCorner(corner);
    }
}

void stopOnTread(Turtle tower, int index, int standing) {
    Tread tread = treadAt(index);
    tower.stop(middle(tread.x), middle(tread.y), standing);
}

void stairRoute(Turtle face) {
    Turtle[FACE_CORNERS] corners = cornersOf(face);
    Turtle tower = upright(corners[stairCorner(corners)]);
    foreach (index; 0 .. CANOPY + 1) {
        stopOnTread(tower, index, index + 1);
    }
}

void stairEntrance(Turtle face) {
    Turtle[FACE_CORNERS] corners = cornersOf(face);
    Tread first = treadAt(0);
    upright(corners[stairCorner(corners)]).entrance(middle(first.x) + STAIR_WIDTH, middle(first.y), 0);
}
