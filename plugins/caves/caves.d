module plugins.caves.caves;

import core.stdc.math : asinh, atan2, ceil, cos, fabs, floor, sin, sqrt, tanh;
import plugins.api.api : Api, HorosphereForm, KindTag, Material, Pen, Rhythm, Risen, Rising, Site, SitePart, Span, Spot;
import plugins.api.binding : List, Named, bound, settingsOf;
import plugins.api.content : Content;
import plugins.carve.carve : Choice, Painting, Triad, Vec, WAYS, WAY_COUNT, Way, aimed, along, axisOf, carried, chartOf, degreesOf, dot, edgeHash, emit, fromAlong, isOwnedBy, latticeHash, minus, mixed, noiseAt, normalized, opposite, penCarried, physicalOf, plus, rejected, scaled, slabAt, squared, triadAt, upOf;
import plugins.turtle.turtle : Drawing, Flight, Found, Hashes, Lie, PI, PORT, TURN_TREADS, Tread, Turtle, WELL_TREADS, Winding, between, boxOf, clamped, flightAt, floorMod, higherOf, lieOf, middle, settled, treadAround, unitOf, wellTreadAt, wound;

enum string NAME = "caves";
enum string LOOK = "caves:look";
enum double SURFACE_BAND = 6;
enum double SEALED_TOP = 1.9;
enum double RISEN_DEPTH = 3;
enum double OPEN_UNDER = 0.5;
enum double SEALED_UNDER = 1.5;
enum int WELL_EDGES = 2;
enum int MOST_WELL_EDGES = 5;
enum int LANDING_HALF = 6;
enum double WELL_SLACK = 0.02;
enum double VERTICAL_SLACK = 0.5;
enum double LEAST_CLIMB = 1.37;
enum double WALKABLE_RISE = 47.3;
enum double STEEP_RISE = 65;
enum double RISE_STEP = 0.25;
enum double MOST_DEPTH = 5.2;
enum double ROCK_MARGIN = 0.5;
enum double FIRST_BAND = 1.6;
enum double HALL_DEPTH = 1.95;
enum uint BAND_COUNT = 5;
enum uint MOST_KNOWN = 256;
enum uint MOST_ENTRY_TRIES = 12;
enum uint MOST_FORMATIONS = 16;
enum uint MOST_STOPS = 96;
enum uint MOST_DESCENT = 512;
enum size_t MOST_WELLS = 8;
enum size_t MOST_LAYERS = 8;
enum size_t MOST_STACKS = 16;
enum uint CHANDELIER_ATTEMPTS = 4;
enum ulong CHANDELIER_SALT_STEP = 256;
struct Tuning {
    double[BAND_COUNT] keepOdds;
    double[BAND_COUNT] tubeRadii;
    double[BAND_COUNT] domeSizes;
    double fog;
    double rootOdds;
    double headOdds;
    double hallOdds;
    double drainOdds;
    double breachOdds;
    double drainStairOdds;
    double portOdds;
    double chamberOdds;
    double squareWellOdds;
    double crossOdds;
    double galleryOdds;
    double mouthOdds;
}

__gshared Tuning tuning;

enum Formations : ubyte {
    none,
    icicles,
    dripstone,
    chandelier,
    beams,
    columns,
    pillars,
    roots,
}

struct Rules {
    double floorThreshold;
    Material patched;
    Material elsewhere;
    double ceilingOdds;
    double patchiness;
    double veinOdds;
    Material lit;
    Material veined;
    Material hanging;
    Material standing;
    Material chandelier;
    Material beam;
    Formations formations;
    double dome = 0;
}

struct Layer {
    double from = 0;
    Rules theme;
}

enum Over : ubyte {
    anywhere,
    risen,
}

struct Stack {
    Named ground;
    Over over;
    List!(Layer, MOST_LAYERS) layers;

    bool isUnder(KindTag tag, Rising rising) const {
        return KindTag.of(ground.tag) == tag && (over == Over.anywhere || rising == Rising.risen);
    }
}

struct Well {
    Named ground;
    Material stair;
    Material lining;
    int liningBelow;
}

struct Materials {
    Material stair;
    Material lining;
    Material drain;
    List!(Well, MOST_WELLS) wells;
    Rules opening;
    Stack open;
    Stack sealed;
    List!(Stack, MOST_STACKS) stacks;
}

const(Stack)* stackUnder(KindTag ground, Rising rising, Mouth mouth) {
    uint index = 0;
    while (index < materials.stacks.count && !materials.stacks.items[index].isUnder(ground, rising)) {
        index += 1;
    }
    if (index < materials.stacks.count) {
        return &materials.stacks.items[index];
    } else if (mouth == Mouth.sealed) {
        return &materials.sealed;
    } else {
        return &materials.open;
    }
}

const(Rules)* themeIn(ref const Stack stack, double depth) {
    uint index = 0;
    while (index + 1 < stack.layers.count && depth >= stack.layers.items[index + 1].from) {
        index += 1;
    }
    return &stack.layers.items[index].theme;
}

Well wellUnder(KindTag ground) {
    uint index = 0;
    while (index < materials.wells.count && KindTag.of(materials.wells.items[index].ground.tag) != ground) {
        index += 1;
    }
    if (index < materials.wells.count) {
        return materials.wells.items[index];
    } else {
        return Well(Named.init, materials.stair, materials.lining, 0);
    }
}

__gshared Materials materials;

void resolveCaves(const(Content)* content) {
    materials = content.bound!Materials(NAME ~ ":materials");
    tuning = content.settingsOf!Tuning(NAME);
}
enum double LEAST_RADIUS = 3.5;
enum double MOST_RADIUS = 10.5;
enum double MOST_DOME = 11.2;
enum double TUBE_HEIGHT = 1.15;
enum double LEAST_BULGE = -1;
enum double MOST_BULGE = 2.5;
enum double DOME_SPREAD = 1.5;
enum double LEAST_DOME_HEIGHT = 0.8;
enum double MOST_DOME_HEIGHT = 1.1;
enum double JUNCTION_MARGIN = 0.8;
enum double SHAFT_RADIUS = 8;
enum double WELL_RADIUS = 2.5;
enum double TREAD_MIDDLE = SHAFT_RADIUS - 1.5;
enum double TREAD_THICKNESS = 2;
enum double MOUTH_LOW = -8;
enum double MOUTH_HIGH = 6;
enum double MOUTH_ROOM = 3;
enum double SKIN = 1.5;
enum double STONE_RING = 10.5;
enum double STONE_REACH = 1.3;
enum double STONE_FOOT = 3;
enum double STONE_GATE = 0.5;
enum uint LEAST_STONES = 3;
enum uint STONE_CHOICES = 4;
enum ulong STONE_SALT = 0x53_544F_4E45;
enum double RIM_STOP = SHAFT_RADIUS + 2;
enum double DOOR_OUT = SHAFT_RADIUS + 1.5;
enum double CLEARANCE = 1.5;
enum double COLUMN_STEP = 1;
enum double LEAST_TIP_HEIGHT = 2.5;
enum double BEAM_FLOOR = 4.2;
enum double NOISE_SCALE = 4.5;
enum ulong ROOT_SALT = 0x52_4F4F_54;
enum ulong HEAD_SALT = 0x48_4541_44;
enum ulong HALL_SALT = 0x48_414C_4C;
enum ulong DRAIN_SALT = 0x44_5241_494E;
enum ulong BREACH_SALT = 0x42_5245_4143;
enum ulong CROSS_SALT = 0x43_524F_5353;
enum ulong GALLERY_SALT = 0x47_414C_4C59;
enum ulong MOUTH_SALT = 0x4D_4F55_5448;
enum double GALLERY_GRADE = 0.5;
enum Span GALLERY_WIDE = Span(-3, 2);
enum Span GALLERY_NARROW = Span(-2, 1);
enum double BREACH_BAND = 0.25;
enum double DRAIN_CLEAR = 0;
enum int DRAIN_SHORT = 3;
enum int CHUTE_HALF = 3;
enum ulong KEEP_SALT = 0x4B_4545_50;
enum ulong BULGE_SALT = 0x42_554C_47;
enum ulong DOME_SALT = 0x44_4F4D_45;
enum ulong FORM_SALT = 0x46_4F52_4D;
enum ulong CELL_SALT = 0x43_454C_4C;
enum ulong FLOOR_SALT = 0x46_4C4F_52;
enum ulong WELL_SALT = 0x57_454C_4C;
enum double WELL_LOWEST = -1;
enum double WELL_HIGHEST = MOUTH_HIGH;
enum int WELL_ROOM = 3;
enum int SQUARE_INNER = 2;
enum int SQUARE_SIDES = 2;
enum int SQUARE_TREADS = 4 * (SQUARE_SIDES + 1);
enum double RING_STOP = SHAFT_RADIUS + 1.5;
immutable int[3] TUBE_STOPS = [13, 17, 21];
immutable int[2] LINING_SIDES = [-PORT - 1, PORT];
static assert(MOST_WELL_EDGES == cast(int) MOST_DEPTH);

enum Openness : ubyte {
    closed,
    open,
}

enum Form : ubyte {
    passage,
    shaft,
}

enum Top : ubyte {
    near,
    far,
}

enum Space : ubyte {
    rock,
    air,
    tread,
}

enum Place : ubyte {
    mouth,
    chamber,
}

enum Shape : ubyte {
    cone,
    beam,
}

enum WellShape : ubyte {
    spiral,
    square,
}

enum Bottom : ubyte {
    chamber,
    landing,
}

struct WellDepth {
    int edges;
    Bottom bottom;
}

struct WellPass {
    Way up;
    int depth;
    WellDepth well;
    Found found;
}

struct Spread {
    double low;
    double high;
}

Choice choiceOf(Material material) {
    if (material == Material.none) {
        return Choice.keep();
    } else {
        return Choice.dress(material);
    }
}

enum Spread HANG_REACH = Spread(0.15, 0.8);
enum Spread HANG_LENGTH = Spread(0.4, 1);
enum Spread STAND_REACH = Spread(0.5, 0.8);
enum Spread STAND_LENGTH = Spread(0.5, 1);
enum Spread CHANDELIER_REACH = Spread(0, 0.6);
enum Spread ARM_TILT = Spread(0.35, 1.1);
enum Spread ARM_LENGTH = Spread(3, 7);
enum Spread ARM_WIDTH = Spread(0.7, 1.1);
enum Spread BEAM_HEIGHT = Spread(0, 0.5);
enum Spread BEAM_TILT = Spread(0, 0.35);
enum Spread BEAM_LENGTH = Spread(10, 18);
enum Spread BEAM_WIDTH = Spread(0.9, 1.9);
enum Spread STONE_HEIGHT = Spread(2, 5.5);
enum Spread MARKER_HEIGHT = Spread(7, 9);
enum double STONE_TOP = 11.5;
enum double MARKER_LIT = 2;
enum Spread ICICLE_WIDTH = Spread(0.9, 1.6);
enum uint LEAST_ARMS = 6;
enum uint ARM_CHOICES = 4;
enum uint LEAST_BEAMS = 3;
enum uint BEAM_CHOICES = 3;
enum double HUB_DROP = 0.5;
enum double BEAM_ROOT = 0.9;
enum double BEAM_SKEW = 0.6;
enum uint ICICLES = 7;
enum uint GLOW_HANGING = 4;
enum uint GLOW_STANDING = 3;
enum uint GYPSUM_HANGING = 3;
enum uint EMBER_STANDING = 4;
enum uint EMBER_HANGING = 3;
enum uint PILLARS = 6;
enum uint ROOTS_HANGING = 7;
enum uint ROOTS_STANDING = 3;
enum double ROOT_LENGTH = 8;
enum Spread ROOT_WIDTH = Spread(0.7, 1.2);
enum double STALK_LENGTH = 5;
enum double STALK_WIDTH = 1.4;
enum double ICICLE_LENGTH = 5;
enum double DRIPSTONE_LENGTH = 4;
enum double DRIPSTONE_WIDTH = 1.3;
enum double PILLAR_WIDTH = 1.6;
enum double MARBLE_LENGTH = 5;
enum double MARBLE_WIDTH = 1.2;
enum double BASALT_LENGTH = 6;
enum double BASALT_WIDTH = 1.8;
enum ulong SALT_STRIDE = 8;
enum ulong ARM_SALT = 16;
enum ulong BEAM_SALT = 64;
enum ulong BEAM_STRIDE = 16;
enum ulong MARBLE_SALT = 128;

double pickIn(ulong hash, ulong salt, Spread spread) {
    return between(hash, salt, spread.low, spread.high);
}

struct Root {
    ulong spawn;
    Hashes blocked;
    Hashes forced;
}

enum Mouth : ubyte {
    none,
    open,
    sealed,
}

struct Bed {
    const(Root)* root;
    const(Stack)* stack;
    double top = 0;
    double bottom = MOST_DEPTH;
    Mouth mouth;

    static Bed ofSurface(const(Root)* root) {
        return Bed(root, stackUnder(KindTag.init, Rising.root, Mouth.open), 0, MOST_DEPTH, Mouth.open);
    }

    static Bed ofGround(const(Root)* root, ref const Risen risen) {
        Bed bed;
        bed.root = root;
        if (risen.form == HorosphereForm.terrain) {
            bed.mouth = Mouth.open;
        } else if (risen.form == HorosphereForm.solid) {
            bed.mouth = Mouth.sealed;
            bed.top = SEALED_TOP;
        }
        if (risen.hasRisen) {
            bed.bottom = RISEN_DEPTH;
        }
        bed.stack = stackUnder(risen.tag, risen.rising, bed.mouth);
        return bed;
    }
}

struct Vertex {
    Turtle frame;
    Drawing pen;
    Vec up;
    double height = 0;
    double[WAY_COUNT] climbs = 0;
}

struct Parent {
    Way way;
    Found found;
}

struct Known {
    ulong hash;
    Openness openness;
}

struct Memo {
    Known[MOST_KNOWN] items;
    uint count;

    void note(ulong hash, Openness openness) {
        if (count < MOST_KNOWN) {
            items[count] = Known(hash, openness);
            count += 1;
        }
    }
}

struct Tube {
    Vec axis;
    Vec upFar;
    Vec start;
    Vec turn;
    double radius = 0;
    double bulge = 0;
    double reach = 0;
    Form form;
    Top top;
}

struct Formation {
    Vec base;
    Vec direction;
    double length = 0;
    double width = 0;
    Material material;
    Shape shape;
}

struct Scene {
    Vertex at;
    Triad triad;
    Tube[WAY_COUNT] tubes;
    Formation[MOST_FORMATIONS] formations;
    WellPass well;
    ulong seed;
    double dome = 0;
    double domeHeight = 0;
    double bowl = 0;
    double edge = 0;
    double mouth = 0;
    double low = 0;
    double high = 0;
    double wide = 0;
    double beams = 0;
    uint count;
    uint formationCount;
    Place place;
    const(Rules)* rule;

    void add(Formation formation) {
        if (formationCount < MOST_FORMATIONS) {
            formations[formationCount] = formation;
            formationCount += 1;
            double far = sqrt(formation.base.squared) + formation.length + formation.width + SKIN;
            if (formation.shape == Shape.beam && far > beams) {
                beams = far;
            }
        }
    }
}

Vertex vertexAt(Turtle frame, Drawing pen) {
    Vertex made;
    made.frame = frame;
    made.pen = pen;
    made.up = upOf(pen);
    made.height = pen.height();
    double edge = frame.edgeCells();
    foreach (way; WAYS) {
        made.climbs[way] = aimed(pen, way).forward(edge).height() - made.height;
    }
    return made;
}

Vertex neighborOf(ref const Vertex at, Way way) {
    return vertexAt(carried(at.frame, way), penCarried(at.pen, way, at.frame.edgeCells()));
}

double riseOf(ref const Vertex at, Way way) {
    return degreesOf(at.up.dot(axisOf(way)));
}

double depthOf(ref const Vertex at) {
    return -at.height / at.frame.edgeCells();
}

bool isSurface(ref const Vertex at) {
    return fabs(at.height) < SURFACE_BAND;
}

uint bandOf(double depth) {
    if (depth < FIRST_BAND) {
        return 0;
    } else {
        uint band = 1 + cast(uint) floor(depth - FIRST_BAND);
        if (band >= BAND_COUNT) {
            return BAND_COUNT - 1;
        } else {
            return band;
        }
    }
}

Place placeOf(ref const Vertex at) {
    if (isSurface(at)) {
        return Place.mouth;
    } else {
        return Place.chamber;
    }
}

const(Rules)* themeOf(ref const Vertex at, ref const Bed bed) {
    final switch (placeOf(at)) {
        case Place.mouth:
            return &materials.opening;
        case Place.chamber:
            return themeIn(*bed.stack, depthOf(at));
    }
}

struct Ways {
    Way[WAY_COUNT] items;
    uint count;

    bool has(Way way) const {
        uint index = 0;
        while (index < count && items[index] != way) {
            index += 1;
        }
        return index < count;
    }
}

Ways waysUpOf(ref const Vertex at) {
    Ways walkable;
    ulong walkableHash = ulong.max;
    Parent steep;
    double steepRise = -1;
    ulong steepHash = ulong.max;
    bool shallow = depthOf(at) < FIRST_BAND;
    foreach (way; WAYS) {
        if (at.climbs[way] > LEAST_CLIMB) {
            double rise = riseOf(at, way);
            ulong hash = edgeHash(at.frame, way);
            if (rise <= WALKABLE_RISE && !shallow) {
                walkable.items[walkable.count] = way;
                walkable.count += 1;
            } else if (rise <= WALKABLE_RISE) {
                if (hash < walkableHash) {
                    walkableHash = hash;
                    walkable.items[0] = way;
                    walkable.count = 1;
                }
            } else {
                double stepped = floor(rise / RISE_STEP);
                if (stepped > steepRise || (stepped == steepRise && hash < steepHash)) {
                    steepRise = stepped;
                    steepHash = hash;
                    steep = Parent(way, Found.some);
                }
            }
        }
    }
    if (walkable.count == 0 && steep.found == Found.some) {
        walkable.items[0] = steep.way;
        walkable.count = 1;
    }
    return walkable;
}

bool isRolledMouth(ulong hash, ref const Root root) {
    return hash == root.spawn || root.forced.contains(hash) || unitOf(hash, ROOT_SALT) < tuning.rootOdds;
}

bool isHall(ref const Vertex at, ulong hash, ref const Bed bed) {
    return bed.mouth == Mouth.open && depthOf(at) >= HALL_DEPTH && (unitOf(hash, HALL_SALT) < tuning.hallOdds || isOverVoid(at));
}

bool isOverVoid(ref const Vertex at) {
    Way down = downOf(at);
    double edge = at.frame.edgeCells();
    if (!(at.climbs[down] < VERTICAL_SLACK - edge)) {
        return false;
    } else {
        return at.height + at.climbs[down] < -(along(at.frame, down).forward(1).probeCrust() * edge + DRAIN_CLEAR);
    }
}

bool probeSunk(ref const Vertex at, ulong hash, ref const Bed bed) {
    const(Root)* root = bed.root;
    if (hash == root.spawn || root.forced.contains(hash)) {
        return true;
    } else if (root.blocked.contains(hash) || !(unitOf(hash, ROOT_SALT) < tuning.rootOdds)) {
        return false;
    } else {
        bool rising = at.frame.probeRising().exists;
        if (rising) {
            return false;
        } else {
            double relief = at.frame.probeRelief();
            if (relief > MOUTH_LOW && relief < MOUTH_HIGH) {
                Vertex bottom = neighborOf(at, downOf(at));
                return keeps(bottom, bottom.frame.probeHash(SitePart.vertex), bed);
            } else {
                return false;
            }
        }
    }
}

double mouthOf(ref const Vertex at) {
    return clamped(at.frame.probeRelief(), MOUTH_LOW, MOUTH_HIGH);
}

bool isRolledKept(ref const Vertex at, ulong hash, ref const Bed bed) {
    double depth = depthOf(at);
    return depth <= bed.bottom && depth >= bed.top && unitOf(hash, KEEP_SALT) < tuning.keepOdds[bandOf(depth)];
}

bool keepsInRock(ref const Vertex at, ulong hash, ref const Bed bed) {
    return isRolledKept(at, hash, bed) && depthOf(at) <= at.frame.probeCrust() - ROCK_MARGIN;
}

bool isUnderKept(ref const Vertex at, ref const Bed bed) {
    Ways ups = waysUpOf(at);
    uint index = 0;
    while (index < ups.count && !isAboveKept(at, ups.items[index], bed)) {
        index += 1;
    }
    return index < ups.count;
}

bool isAboveKept(ref const Vertex at, Way way, ref const Bed bed) {
    Vertex above = neighborOf(at, way);
    return keepsInRock(above, above.frame.probeHash(SitePart.vertex), bed);
}

bool keeps(ref const Vertex at, ulong hash, ref const Bed bed) {
    if (!isRolledKept(at, hash, bed)) {
        return false;
    } else {
        double depth = depthOf(at);
        double crust = at.frame.probeCrust();
        if (depth <= crust - ROCK_MARGIN) {
            return true;
        } else if (bed.mouth == Mouth.open && depth <= crust + BREACH_BAND && unitOf(hash, BREACH_SALT) < tuning.breachOdds) {
            return isUnderKept(at, bed);
        } else {
            return false;
        }
    }
}

bool isAboveBed(ref const Vertex at, ref const Bed bed) {
    return bed.mouth == Mouth.sealed && depthOf(at) < bed.top;
}

bool isWellMouth(Turtle vertex, ref const Bed bed) {
    bool port = vertex.probePort();
    if (!port) {
        return false;
    } else if (bed.mouth == Mouth.sealed) {
        return true;
    } else {
        double relief = vertex.probeRelief();
        return relief > WELL_LOWEST && relief < WELL_HIGHEST;
    }
}

WellDepth wellDepthOf(Turtle mouth, ref const Bed bed) {
    int deepest = cast(int) floor(bed.bottom);
    double crust = mouth.probeCrust();
    if (crust <= deepest) {
        return WellDepth(higherOf(WELL_EDGES, cast(int) ceil(crust)), Bottom.landing);
    } else {
        return WellDepth(deepest, Bottom.chamber);
    }
}

bool isOnPlane(Turtle vertex) {
    return fabs(vertex.openPen().height()) < WELL_SLACK * vertex.edgeCells();
}

WellPass probeWell(ref const Vertex at, ref const Bed bed) {
    double edge = at.frame.edgeCells();
    double depth = depthOf(at);
    int level = cast(int) floor(depth + 0.5);
    if (bed.mouth == Mouth.none || level < 1 || level > MOST_WELL_EDGES || fabs(depth - level) > WELL_SLACK) {
        return WellPass.init;
    } else {
        Parent up;
        foreach (way; WAYS) {
            if (at.climbs[way] > edge - VERTICAL_SLACK) {
                up = Parent(way, Found.some);
            }
        }
        if (up.found == Found.none) {
            return WellPass.init;
        } else {
            Turtle mouth = along(at.frame, up.way).forward(level);
            if (!isOnPlane(mouth) || !isWellMouth(mouth, bed)) {
                return WellPass.init;
            } else {
                WellDepth well = wellDepthOf(mouth, bed);
                if (level > well.edges) {
                    return WellPass.init;
                } else {
                    return WellPass(up.way, level, well, Found.some);
                }
            }
        }
    }
}

bool isOpenedBy(WellPass pass, ref const Bed bed) {
    if (pass.found == Found.none) {
        return false;
    } else if (pass.depth == pass.well.edges) {
        return pass.well.bottom == Bottom.chamber;
    } else {
        return bed.mouth == Mouth.sealed && pass.depth >= bed.top;
    }
}

bool isAlongWell(ref const WellPass pass, Way way) {
    return pass.found == Found.some && (way == pass.up || (way == opposite(pass.up) && pass.depth < pass.well.edges));
}

bool isOpenWell(ref const Vertex at, ref const Bed bed) {
    return bed.mouth == Mouth.open && isOpenedBy(probeWell(at, bed), bed);
}

bool holds(ref const Vertex at, ref const Bed bed) {
    return keeps(at, at.frame.probeHash(SitePart.vertex), bed) || isOpenWell(at, bed);
}

Openness opennessOf(ref const Vertex at, ref const Bed bed, ref Memo memo) {
    ulong hash = at.frame.probeHash(SitePart.vertex);
    uint index = 0;
    while (index < memo.count && memo.items[index].hash != hash) {
        index += 1;
    }
    if (index < memo.count) {
        return memo.items[index].openness;
    } else {
        Openness result = judgedOpenness(at, hash, bed, memo);
        memo.note(hash, result);
        return result;
    }
}

Openness judgedOpenness(ref const Vertex at, ulong hash, ref const Bed bed, ref Memo memo) {
    if (isSurface(at)) {
        if (bed.mouth == Mouth.open && probeSunk(at, hash, bed)) {
            return Openness.open;
        } else {
            return Openness.closed;
        }
    } else if (!(at.height < 0)) {
        return Openness.closed;
    } else if (isOpenedBy(probeWell(at, bed), bed)) {
        return Openness.open;
    } else if (!keeps(at, hash, bed)) {
        return Openness.closed;
    } else if (isHall(at, hash, bed)) {
        return Openness.open;
    } else {
        return opennessUnder(at, hash, bed, memo);
    }
}

Openness opennessUnder(ref const Vertex at, ulong hash, ref const Bed bed, ref Memo memo) {
    Ways ups = waysUpOf(at);
    foreach (way; ups.items[0 .. ups.count]) {
        Vertex above = neighborOf(at, way);
        if (isAboveBed(above, bed)) {
            if (unitOf(hash, HEAD_SALT) < tuning.headOdds) {
                return Openness.open;
            }
        } else if (opennessOf(above, bed, memo) == Openness.open && !isOpenWell(above, bed)) {
            return Openness.open;
        }
    }
    return Openness.closed;
}

bool isCrossing(ref const Vertex at, ref const Vertex to, Way way, ref const Bed bed) {
    return !isSurface(at) && unitOf(edgeHash(at.frame, way), CROSS_SALT) < tuning.crossOdds && !isSurface(to) && to.height < 0 && !isAboveBed(to, bed) && !isOpenWell(to, bed) && !isOpenWell(at, bed);
}

double radiusOf(ref const Vertex near, ref const Vertex far) {
    double depth = depthOf(near);
    if (depthOf(far) > depth) {
        depth = depthOf(far);
    }
    return tuning.tubeRadii[bandOf(depth)];
}

Tube tubeTo(ref const Vertex at, ref const Vertex to, Way way) {
    Tube tube;
    ulong hash = edgeHash(at.frame, way);
    tube.axis = axisOf(way);
    tube.upFar = to.up;
    tube.radius = radiusOf(at, to);
    tube.bulge = between(hash, BULGE_SALT, LEAST_BULGE, MOST_BULGE);
    if (tube.radius + tube.bulge > MOST_RADIUS) {
        tube.bulge = MOST_RADIUS - tube.radius;
    } else if (tube.radius + tube.bulge < LEAST_RADIUS) {
        tube.bulge = LEAST_RADIUS - tube.radius;
    }
    double nearRise = fabs(riseOf(at, way));
    double farRise = fabs(riseOf(to, opposite(way)));
    tube.form = Form.passage;
    if (nearRise > STEEP_RISE || farRise > STEEP_RISE) {
        tube.form = Form.shaft;
        tube.radius = SHAFT_RADIUS;
        tube.bulge = 0;
        Helix helix = helixOf(along(at.frame, way));
        tube.start = fromAlong(way, helix.start);
        tube.turn = fromAlong(way, helix.turn);
    }
    tube.top = Top.far;
    if (at.height > to.height) {
        tube.top = Top.near;
    }
    tube.reach = TUBE_HEIGHT * (tube.radius + fabs(tube.bulge)) + SKIN;
    return tube;
}

struct Helix {
    Vec start;
    Vec turn;
}

immutable Vec[4] PENTAGON_DIRECTIONS = [Vec(1, 0, 0), Vec(0, -1, 0), Vec(-1, 0, 0), Vec(0, 1, 0)];

Helix helixOf(Turtle shaft) {
    ulong[4] hashes;
    Turtle rolled = shaft;
    foreach (index; 0 .. 4) {
        hashes[index] = rolled.probeHash(SitePart.face);
        rolled = rolled.rollRight();
    }
    uint least = 0;
    foreach (index; 1 .. 4) {
        if (hashes[index] < hashes[least]) {
            least = index;
        }
    }
    uint next = (least + 1) % 4;
    uint previous = (least + 3) % 4;
    uint turn = next;
    if (hashes[previous] < hashes[next]) {
        turn = previous;
    }
    return Helix(PENTAGON_DIRECTIONS[least], PENTAGON_DIRECTIONS[turn]);
}

bool isLinked(ref const Vertex at, ref const Vertex to, Way way, ref const Bed bed, ref Memo memo) {
    return isTreeLinked(at, to, way, bed, memo) || (isCrossing(at, to, way, bed) && opennessOf(to, bed, memo) == Openness.open);
}

bool isTreeLinked(ref const Vertex at, ref const Vertex to, Way way, ref const Bed bed, ref Memo memo) {
    if (to.height > at.height) {
        return !isSurface(at) && waysUpOf(at).has(way) && !isAboveBed(to, bed) && opennessOf(to, bed, memo) == Openness.open;
    } else if (isSurface(to) || !(to.height < at.height)) {
        return false;
    } else {
        return waysUpOf(to).has(opposite(way)) && holds(to, bed) && (!isOpenWell(at, bed) || opennessOf(to, bed, memo) == Openness.open);
    }
}

double bowlOf(ref const Vertex at) {
    Pen pen = at.pen.pen;
    double sinh = pen.ground[0] * pen.frame[12] + pen.ground[1] * pen.frame[13] + pen.ground[2] * pen.frame[14] - pen.ground[3] * pen.frame[15];
    double depth = asinh(sinh);
    return fabs(tanh(depth)) / 2 * depth / at.height;
}

Scene sceneAt(ref const Vertex at, ref const Bed bed, ref Memo memo) {
    Scene scene;
    scene.at = at;
    scene.edge = at.frame.edgeCells();
    if (isSurface(at)) {
        scene.mouth = mouthOf(at);
    } else {
        scene.bowl = bowlOf(at);
    }
    scene.triad = triadAt(at.frame);
    scene.seed = at.frame.probeHash(SitePart.vertex);
    scene.place = placeOf(at);
    scene.rule = themeOf(at, bed);
    if (!isSurface(at)) {
        scene.well = probeWell(at, bed);
    }
    double widest = 0;
    uint shafts = 0;
    foreach (way; WAYS) {
        Vertex to = neighborOf(at, way);
        if (!isAlongWell(scene.well, way) && isLinked(at, to, way, bed, memo)) {
            Tube tube = tubeTo(at, to, way);
            if (tube.form == Form.shaft) {
                shafts += 1;
            } else if (tube.radius + tube.bulge > widest) {
                widest = tube.radius + tube.bulge;
            }
            scene.tubes[scene.count] = tube;
            scene.count += 1;
        }
    }
    if (scene.place == Place.chamber) {
        uint band = bandOf(depthOf(at));
        double dome = widest + JUNCTION_MARGIN;
        if (scene.count >= 3 || unitOf(scene.seed, DOME_SALT) < tuning.chamberOdds || isOpenedBy(scene.well, bed)) {
            dome = tuning.domeSizes[band] + between(scene.seed, DOME_SALT + 1, -DOME_SPREAD, DOME_SPREAD);
        }
        if (scene.rule.dome > 0) {
            dome = scene.rule.dome;
        }
        if (dome < widest + JUNCTION_MARGIN) {
            dome = widest + JUNCTION_MARGIN;
        }
        if (dome > MOST_DOME) {
            dome = MOST_DOME;
        }
        scene.dome = dome;
        scene.domeHeight = dome * between(scene.seed, DOME_SALT + 2, LEAST_DOME_HEIGHT, MOST_DOME_HEIGHT);
        double highest = MOST_DOME - scene.bowl * dome * dome;
        if (scene.domeHeight > highest) {
            scene.domeHeight = highest;
        }
        scene.low = -SKIN;
        scene.high = MOST_DOME + SKIN;
        scene.wide = (dome + SKIN) * (dome + SKIN);
        addFormations(scene);
    } else {
        scene.low = MOUTH_LOW - STONE_FOOT - SKIN;
        scene.high = STONE_TOP + SKIN;
        scene.wide = (STONE_RING + STONE_REACH + SKIN) * (STONE_RING + STONE_REACH + SKIN);
    }
    return scene;
}

Vec horizontalOf(ref const Scene scene, ulong salt) {
    Vec physical = Vec(between(scene.seed, salt, -1, 1), between(scene.seed, salt + 1, -1, 1), between(scene.seed, salt + 2, -1, 1));
    return chartOf(scene.triad, physical).rejected(scene.at.up).normalized;
}

double rayDistance(Vec point, Vec axis) {
    double along = point.dot(axis);
    if (along <= 0) {
        return sqrt(point.squared);
    } else {
        return sqrt(point.minus(axis.scaled(along)).squared);
    }
}

bool isClear(ref const Scene scene, Vec floorPoint) {
    foreach (index; 0 .. scene.count) {
        Tube tube = scene.tubes[index];
        if (rayDistance(floorPoint, tube.axis) < tube.radius + tube.bulge + CLEARANCE) {
            return false;
        }
    }
    return true;
}

bool isClearOverhead(ref const Scene scene, Vec foot) {
    Vec floor = floorAt(scene, foot);
    double top = ceilingAt(scene, sqrt(foot.squared)) + CLEARANCE;
    foreach (index; 0 .. scene.count) {
        Tube tube = scene.tubes[index];
        double height = 0;
        while (tube.top == Top.far && height <= top) {
            if (tubeSpace(tube, floor.plus(scene.at.up.scaled(height)), scene.at.up, scene.edge) != Space.rock) {
                return false;
            }
            height += COLUMN_STEP;
        }
    }
    return true;
}

double ceilingAt(ref const Scene scene, double across) {
    double share = across / scene.dome;
    return scene.domeHeight * sqrt(1 - share * share);
}

Vec floorAt(ref const Scene scene, Vec foot) {
    return foot.plus(scene.at.up.scaled(scene.bowl * foot.squared));
}

void hang(ref Scene scene, ulong salt, Material material, double longest, double width) {
    Vec side = horizontalOf(scene, salt);
    double across = scene.dome * pickIn(scene.seed, salt + 3, HANG_REACH);
    Vec foot = side.scaled(across);
    if (isClearOverhead(scene, foot)) {
        double ceiling = ceilingAt(scene, across);
        double length = pickIn(scene.seed, salt + 4, HANG_LENGTH) * longest;
        if (length > ceiling - LEAST_TIP_HEIGHT) {
            length = ceiling - LEAST_TIP_HEIGHT;
        }
        if (length > 1) {
            Vec base = floorAt(scene, foot).plus(scene.at.up.scaled(ceiling + 1));
            scene.add(Formation(base, scene.at.up.scaled(-1), length + 1, width, material, Shape.cone));
        }
    }
}

void stand(ref Scene scene, ulong salt, Material material, double longest, double width) {
    Vec side = horizontalOf(scene, salt);
    double across = scene.dome * pickIn(scene.seed, salt + 3, STAND_REACH);
    Vec foot = side.scaled(across);
    if (isClear(scene, foot)) {
        double length = pickIn(scene.seed, salt + 4, STAND_LENGTH) * longest;
        if (length > ceilingAt(scene, across) - 1) {
            length = ceilingAt(scene, across) - 1;
        }
        scene.add(Formation(floorAt(scene, foot).minus(scene.at.up), scene.at.up, length + 1, width, material, Shape.cone));
    }
}

void chandelier(ref Scene scene, ulong salt) {
    Vec side = horizontalOf(scene, salt);
    double across = scene.dome * pickIn(scene.seed, salt + 3, CHANDELIER_REACH);
    Vec foot = side.scaled(across);
    if (isClearOverhead(scene, foot)) {
        double ceiling = ceilingAt(scene, across);
        double lowest = ceiling - LEAST_TIP_HEIGHT - HUB_DROP;
        Vec hub = floorAt(scene, foot).plus(scene.at.up.scaled(ceiling - HUB_DROP));
        uint arms = LEAST_ARMS + cast(uint)(unitOf(scene.seed, salt + 4) * ARM_CHOICES);
        foreach (arm; 0 .. arms) {
            ulong armSalt = salt + ARM_SALT + arm * SALT_STRIDE;
            Vec outward = horizontalOf(scene, armSalt);
            double tilt = pickIn(scene.seed, armSalt + 3, ARM_TILT);
            Vec direction = scene.at.up.scaled(-1).plus(outward.scaled(tilt)).normalized;
            double length = pickIn(scene.seed, armSalt + 4, ARM_LENGTH);
            double sinking = -direction.dot(scene.at.up);
            if (sinking * length > lowest) {
                length = lowest / sinking;
            }
            if (length > 1) {
                scene.add(Formation(hub, direction, length, pickIn(scene.seed, armSalt + 5, ARM_WIDTH), scene.rule.chandelier, Shape.cone));
            }
        }
    }
}

void crystal(ref Scene scene, ulong salt) {
    Vec side = horizontalOf(scene, salt);
    Vec across = horizontalOf(scene, salt + SALT_STRIDE);
    double height = BEAM_FLOOR + pickIn(scene.seed, salt + 3, BEAM_HEIGHT) * (scene.domeHeight - BEAM_FLOOR);
    double tilt = pickIn(scene.seed, salt + 4, BEAM_TILT);
    Vec base = floorAt(scene, side.scaled(scene.dome * BEAM_ROOT)).plus(scene.at.up.scaled(height));
    Vec direction = side.scaled(-1).plus(across.scaled(BEAM_SKEW)).plus(scene.at.up.scaled(tilt)).normalized;
    double length = pickIn(scene.seed, salt + 5, BEAM_LENGTH);
    scene.add(Formation(base, direction, length, pickIn(scene.seed, salt + 6, BEAM_WIDTH), scene.rule.beam, Shape.beam));
}

void addFormations(ref Scene scene) {
    Rules rule = *scene.rule;
    final switch (rule.formations) {
        case Formations.none:
            break;
        case Formations.icicles:
            foreach (index; 0 .. ICICLES) {
                ulong salt = FORM_SALT + index * SALT_STRIDE;
                hang(scene, salt, rule.hanging, ICICLE_LENGTH, pickIn(scene.seed, salt + 5, ICICLE_WIDTH));
            }
            break;
        case Formations.dripstone:
            foreach (index; 0 .. GLOW_HANGING) {
                hang(scene, FORM_SALT + index * SALT_STRIDE, rule.hanging, DRIPSTONE_LENGTH, DRIPSTONE_WIDTH);
            }
            foreach (index; GLOW_HANGING .. GLOW_HANGING + GLOW_STANDING) {
                stand(scene, FORM_SALT + index * SALT_STRIDE, rule.standing, DRIPSTONE_LENGTH, PILLAR_WIDTH);
            }
            break;
        case Formations.chandelier:
            uint attempt = 0;
            uint before = scene.formationCount;
            while (attempt < CHANDELIER_ATTEMPTS && scene.formationCount == before) {
                chandelier(scene, FORM_SALT + attempt * CHANDELIER_SALT_STEP);
                attempt += 1;
            }
            foreach (index; 0 .. GYPSUM_HANGING) {
                hang(scene, FORM_SALT + MARBLE_SALT + index * SALT_STRIDE, rule.hanging, MARBLE_LENGTH, MARBLE_WIDTH);
            }
            break;
        case Formations.beams:
            uint beams = LEAST_BEAMS + cast(uint)(unitOf(scene.seed, FORM_SALT) * BEAM_CHOICES);
            foreach (index; 0 .. beams) {
                crystal(scene, FORM_SALT + BEAM_SALT + index * BEAM_STRIDE);
            }
            break;
        case Formations.columns:
            foreach (index; 0 .. EMBER_STANDING) {
                stand(scene, FORM_SALT + index * SALT_STRIDE, rule.standing, BASALT_LENGTH, BASALT_WIDTH);
            }
            foreach (index; EMBER_STANDING .. EMBER_STANDING + EMBER_HANGING) {
                hang(scene, FORM_SALT + index * SALT_STRIDE, rule.hanging, DRIPSTONE_LENGTH, DRIPSTONE_WIDTH);
            }
            break;
        case Formations.pillars:
            foreach (index; 0 .. PILLARS) {
                stand(scene, FORM_SALT + index * SALT_STRIDE, rule.standing, MOST_DOME, PILLAR_WIDTH);
            }
            break;
        case Formations.roots:
            foreach (index; 0 .. ROOTS_HANGING) {
                ulong salt = FORM_SALT + index * SALT_STRIDE;
                hang(scene, salt, rule.hanging, ROOT_LENGTH, pickIn(scene.seed, salt + 5, ROOT_WIDTH));
            }
            foreach (index; ROOTS_HANGING .. ROOTS_HANGING + ROOTS_STANDING) {
                stand(scene, FORM_SALT + index * SALT_STRIDE, rule.standing, STALK_LENGTH, STALK_WIDTH);
            }
            break;
    }
}

double floorHeight(ref const Tube tube, Vec point, Vec up, double edge) {
    double along = point.dot(tube.axis);
    Vec across = point.minus(tube.axis.scaled(along));
    Vec upHere = mixed(up, tube.upFar, along / edge).normalized;
    return across.dot(upHere.rejected(tube.axis).normalized);
}

bool isUnderRamp(ref const Scene scene, Vec point) {
    foreach (index; 0 .. scene.count) {
        Tube tube = scene.tubes[index];
        if (tube.form == Form.passage && tube.top == Top.far) {
            double along = point.dot(tube.axis);
            double reach = tube.radius + tube.bulge + 1;
            if (along > 0 && point.minus(tube.axis.scaled(along)).squared < reach * reach && floorHeight(tube, point, scene.at.up, scene.edge) < 0) {
                return true;
            }
        }
    }
    return false;
}

Space tubeSpace(ref const Tube tube, Vec point, Vec up, double edge) {
    double along = point.dot(tube.axis);
    if (along < 0) {
        return Space.rock;
    } else {
        Vec across = point.minus(tube.axis.scaled(along));
        final switch (tube.form) {
            case Form.passage:
                double share = along / edge;
                double height = -1;
                if (across.squared < tube.reach * tube.reach) {
                    height = floorHeight(tube, point, up, edge);
                }
                if (height < 0) {
                    return Space.rock;
                } else {
                    double radius = tube.radius + tube.bulge * sin(PI * share);
                    double side = across.squared - height * height;
                    double tall = radius * TUBE_HEIGHT;
                    if (side / (radius * radius) + height * height / (tall * tall) < 1) {
                        return Space.air;
                    } else {
                        return Space.rock;
                    }
                }
            case Form.shaft:
                double reach = across.squared;
                if (reach >= SHAFT_RADIUS * SHAFT_RADIUS) {
                    return Space.rock;
                } else if (reach < WELL_RADIUS * WELL_RADIUS) {
                    return Space.air;
                } else {
                    double down = along;
                    if (tube.top == Top.far) {
                        down = edge - along;
                    }
                    return treadSpace(tube, across, down);
                }
        }
    }
}

Space treadSpace(ref const Tube tube, Vec across, double down) {
    double angle = atan2(across.dot(tube.turn), across.dot(tube.start));
    if (angle < 0) {
        angle += 2 * PI;
    }
    double wedge = floor(angle / (2 * PI) * TURN_TREADS);
    if (down >= wedge && down < wedge + TREAD_THICKNESS) {
        return Space.tread;
    } else {
        return Space.air;
    }
}

uint shaftOf(ref const Scene scene) {
    uint index = 0;
    while (index < scene.count && scene.tubes[index].form != Form.shaft) {
        index += 1;
    }
    return index;
}

Space mouthSpace(ref const Scene scene, Vec point, double height, double across) {
    uint shaft = shaftOf(scene);
    if (shaft == scene.count || across < WELL_RADIUS * WELL_RADIUS || height > scene.mouth) {
        return Space.air;
    } else {
        Tube tube = scene.tubes[shaft];
        return treadSpace(tube, point.minus(tube.axis.scaled(point.dot(tube.axis))), TURN_TREADS - height);
    }
}

bool isOverMouth(ref const Scene scene, double height) {
    return scene.place == Place.mouth && height > scene.mouth;
}

Space spaceAt(ref const Scene scene, Vec point) {
    double raw = point.dot(scene.at.up);
    double across = point.squared - raw * raw;
    double height = raw - scene.bowl * across;
    Space found = Space.rock;
    if (scene.place == Place.mouth) {
        if (height > 0 && height < scene.mouth + MOUTH_ROOM && across < SHAFT_RADIUS * SHAFT_RADIUS) {
            found = mouthSpace(scene, point, height, across);
        }
    } else if (height >= 0 && across / (scene.dome * scene.dome) + height * height / (scene.domeHeight * scene.domeHeight) < 1) {
        found = Space.air;
    }
    if (found == Space.tread) {
        return Space.tread;
    }
    Found ramped = Found.none;
    foreach (index; 0 .. scene.count) {
        Tube tube = scene.tubes[index];
        Space inside = tubeSpace(tube, point, scene.at.up, scene.edge);
        if (inside == Space.tread && !isOverMouth(scene, height)) {
            return Space.tread;
        } else if (inside != Space.rock) {
            found = Space.air;
            if (tube.form == Form.passage && tube.top == Top.far) {
                ramped = Found.some;
            }
        }
    }
    if (found == Space.air && ramped == Found.none && isUnderRamp(scene, point)) {
        return Space.rock;
    } else {
        return found;
    }
}

bool isInside(ref const Formation formation, Vec point) {
    Vec offset = point.minus(formation.base);
    double along = offset.dot(formation.direction);
    if (along < 0 || along > formation.length) {
        return false;
    } else {
        double side = offset.squared - along * along;
        double width = formation.width;
        final switch (formation.shape) {
            case Shape.cone:
                width = formation.width * (1 - along / formation.length);
                break;
            case Shape.beam:
                double tip = (formation.length - along) / formation.width;
                if (tip < 1) {
                    width = formation.width * tip;
                }
                break;
        }
        return side < width * width;
    }
}

ulong cellKey(ref const Scene scene, Vec point) {
    Vec physical = physicalOf(scene.triad, point);
    return latticeHash(scene.seed ^ CELL_SALT, cast(long) floor(physical.x), cast(long) floor(physical.y), cast(long) floor(physical.z));
}

double patchAt(ref const Scene scene, Vec point) {
    return noiseAt(scene.seed ^ FLOOR_SALT, physicalOf(scene.triad, point), NOISE_SCALE);
}

double cellRoll(ref const Scene scene, Vec point) {
    return unitOf(cellKey(scene, point), CELL_SALT);
}

Choice floorChoice(ref const Scene scene, Vec point) {
    Rules rule = *scene.rule;
    if (patchAt(scene, point) > rule.floorThreshold) {
        return choiceOf(rule.patched);
    } else {
        return choiceOf(rule.elsewhere);
    }
}

Choice ceilingChoice(ref const Scene scene, Vec point) {
    Rules rule = *scene.rule;
    double odds = rule.ceilingOdds * (1 - rule.patchiness + rule.patchiness * patchAt(scene, point));
    double roll = cellRoll(scene, point);
    if (roll < odds) {
        return Choice.dress(rule.lit);
    } else if (roll < odds + rule.veinOdds) {
        return Choice.dress(rule.veined);
    } else {
        return Choice.keep();
    }
}

bool isInWell(ref const Scene scene, Vec point) {
    if (scene.well.found == Found.none) {
        return false;
    } else {
        Vec axis = axisOf(scene.well.up);
        double height = point.dot(axis);
        Vec side = point.minus(axis.scaled(height));
        return (height > 0 || scene.well.depth < scene.well.well.edges) && fabs(side.x) < PORT && fabs(side.y) < PORT && fabs(side.z) < PORT;
    }
}

bool isNear(ref const Tube tube, Vec point, double far) {
    double along = point.dot(tube.axis);
    return along > -SKIN && far - along * along < tube.reach * tube.reach;
}

bool isBeyond(ref const Scene scene, Vec point) {
    double far = point.squared;
    double raw = point.dot(scene.at.up);
    if (raw > scene.low && raw < scene.high && far - raw * raw < scene.wide) {
        return false;
    } else if (far < scene.beams * scene.beams) {
        return false;
    } else {
        uint index = 0;
        while (index < scene.count && !isNear(scene.tubes[index], point, far)) {
            index += 1;
        }
        return index == scene.count;
    }
}

Choice choiceAt(ref const Scene scene, Vec point) {
    if (isBeyond(scene, point) || isInWell(scene, point)) {
        return Choice.keep();
    } else {
        return chosenAt(scene, point);
    }
}

Choice stoneAt(ref const Scene scene, Vec point) {
    double raw = point.dot(scene.at.up);
    double inner = STONE_RING - STONE_REACH;
    uint shaft = shaftOf(scene);
    if (shaft == scene.count || point.squared - raw * raw < inner * inner) {
        return Choice.keep();
    } else {
        Vec gate = scene.tubes[shaft].start;
        uint stones = LEAST_STONES + cast(uint)(unitOf(scene.seed, STONE_SALT) * STONE_CHOICES);
        foreach (index; 0 .. stones) {
            ulong salt = STONE_SALT + 1 + index * SALT_STRIDE;
            Vec side = horizontalOf(scene, salt);
            Vec offset = point.minus(side.scaled(STONE_RING));
            double height = offset.dot(scene.at.up);
            Spread tall = STONE_HEIGHT;
            if (index == 0) {
                tall = MARKER_HEIGHT;
            }
            double top = clamped(scene.mouth + pickIn(scene.seed, salt + 3, tall), scene.mouth, STONE_TOP);
            if (side.dot(gate) < STONE_GATE && offset.squared - height * height < STONE_REACH * STONE_REACH && height > scene.mouth - STONE_FOOT && height < top) {
                if (height >= top - 1 || (index == 0 && height >= top - MARKER_LIT)) {
                    return Choice.of(materials.opening.lit);
                } else {
                    return Choice.of(materials.stair);
                }
            }
        }
        return Choice.keep();
    }
}

Choice chosenAt(ref const Scene scene, Vec point) {
    final switch (scene.place) {
        case Place.chamber:
            return carvedAt(scene, point);
        case Place.mouth:
            Choice stone = stoneAt(scene, point);
            if (stone.painting == Painting.painted) {
                return stone;
            } else {
                return carvedAt(scene, point);
            }
    }
}

Choice carvedAt(ref const Scene scene, Vec point) {
    Space here = spaceAt(scene, point);
    final switch (here) {
        case Space.tread:
            return Choice.of(materials.stair);
        case Space.air:
            foreach (index; 0 .. scene.formationCount) {
                if (isInside(scene.formations[index], point)) {
                    return Choice.dress(scene.formations[index].material);
                }
            }
            return Choice.of(Material.none);
        case Space.rock:
            foreach (index; 0 .. scene.formationCount) {
                if (scene.formations[index].shape == Shape.beam && isInside(scene.formations[index], point)) {
                    return Choice.dress(scene.formations[index].material);
                }
            }
            if (spaceAt(scene, point.plus(scene.at.up)) == Space.air) {
                return floorChoice(scene, point);
            } else if (spaceAt(scene, point.minus(scene.at.up)) == Space.air) {
                return ceilingChoice(scene, point);
            } else {
                return Choice.keep();
            }
    }
}

void paintEnd(Turtle frame, Way own, ref const Bed bed, ref Memo memo) {
    Drawing pen = frame.openPen();
    double height = pen.height();
    double edge = frame.edgeCells();
    if (height < SURFACE_BAND && height > -(bed.bottom + 1) * edge) {
        Triad triad = triadAt(frame);
        if (isOwnedBy(triad, own)) {
            Vertex at = vertexAt(frame, pen);
            if (opennessOf(at, bed, memo) == Openness.open) {
                Scene scene = sceneAt(at, bed, memo);
                Choice choose(Vec point) {
                    return choiceAt(scene, point);
                }
                emit!choose(slabAt(frame, own));
            }
        }
    }
}

void tile(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    Bed bed = Bed.ofGround(cast(const(Root)*) data, *risen);
    if (bed.mouth != Mouth.none) {
        Turtle start = Turtle(api, site);
        Memo memo;
        paintEnd(start, Way.zPlus, bed, memo);
        paintEnd(start.forward(1), Way.zMinus, bed, memo);
    }
    if (bed.mouth != Mouth.none) {
        Turtle start = Turtle(api, site);
        Lie lie = lieOf(start);
        Well kind = wellUnder(risen.tag);
        Found sunk = well(start, lie, kind, bed);
        if (bed.mouth == Mouth.open) {
            Memo memo;
            if (sunk == Found.none) {
                drain(start, lie, bed, memo, materials.drain);
            }
            gallery(start, lie);
            mouth(start, lie, bed, memo);
            wellMouth(start, lie, kind, bed);
        }
    }
}

bool isGalleryEnd(Turtle vertex, double height) {
    double edge = vertex.edgeCells();
    double depth = -height / edge;
    double crust = vertex.probeCrust();
    return crust < double.infinity && depth >= HALL_DEPTH && depth <= crust - ROCK_MARGIN;
}

void gallery(Turtle start, Lie lie) {
    double edge = start.edgeCells();
    if (unitOf(start.probeHash(SitePart.line), GALLERY_SALT) < tuning.galleryOdds && fabs(lie.far - lie.near) < GALLERY_GRADE * edge && isGalleryEnd(start, lie.near) && isGalleryEnd(start.forward(1), lie.far)) {
        tunnel(start);
    }
}

void mouth(Turtle start, Lie lie, ref const Bed bed, ref Memo memo) {
    double edge = start.edgeCells();
    Turtle end = start.forward(1);
    if (unitOf(start.probeHash(SitePart.edge), MOUTH_SALT) < tuning.mouthOdds && fabs(lie.far - lie.near) < GALLERY_GRADE * edge && (isMouthFrom(start, end, lie.far, bed, memo) || isMouthFrom(end, start, lie.near, bed, memo))) {
        tunnel(start);
    }
}

bool isMouthFrom(Turtle chamber, Turtle open, double openHeight, ref const Bed bed, ref Memo memo) {
    if (!isInOpen(open, openHeight)) {
        return false;
    } else {
        Vertex at = vertexAt(chamber, chamber.openPen());
        return opennessOf(at, bed, memo) == Openness.open;
    }
}

void tunnel(Turtle start) {
    Span along = Span(0, start.edgeCells() - 1);
    start.replace(Material.none, boxOf(GALLERY_WIDE, GALLERY_NARROW, along));
    start.replace(Material.none, boxOf(GALLERY_NARROW, GALLERY_WIDE, along));
}

bool isInOpen(Turtle vertex, double height) {
    double edge = vertex.edgeCells();
    return height < -(vertex.probeCrust() * edge + DRAIN_CLEAR);
}

void drain(Turtle start, Lie lie, ref const Bed bed, ref Memo memo, Material stair) {
    double edge = start.edgeCells();
    double near = lie.near;
    double far = lie.far;
    if (fabs(fabs(far - near) - edge) < VERTICAL_SLACK && near < -SURFACE_BAND && far < -SURFACE_BAND) {
        Turtle top = start;
        Turtle bottom = start.forward(1);
        double topHeight = near;
        double bottomHeight = far;
        if (far > near) {
            top = start.forward(1).pitchUp().pitchUp();
            bottom = start;
            topHeight = far;
            bottomHeight = near;
        }
        ulong hash = start.probeHash(SitePart.edge);
        if (unitOf(hash, DRAIN_SALT) < tuning.drainOdds && isInOpen(bottom, bottomHeight)) {
            Vertex upper = vertexAt(top, top.openPen());
            if (opennessOf(upper, bed, memo) == Openness.open) {
                if (unitOf(hash, DRAIN_SALT + 1) < tuning.drainStairOdds) {
                    stairDown(Flight(top, Winding.straight), 0, stair, WellShape.spiral);
                } else {
                    Span chute = Span(-CHUTE_HALF, CHUTE_HALF - 1);
                    top.paint(Material.none, boxOf(chute, chute, Span(0, cast(int) edge - DRAIN_SHORT)));
                }
                landing(top, stair);
            }
        }
    }
}

Found well(Turtle start, Lie lie, ref const Well kind, ref const Bed bed) {
    double edge = start.edgeCells();
    double near = lie.near;
    double far = lie.far;
    if (!(fabs(fabs(far - near) - edge) < VERTICAL_SLACK)) {
        return Found.none;
    } else {
        Turtle down = start;
        double top = near;
        if (far > near) {
            down = start.forward(1).pitchUp().pitchUp();
            top = far;
        }
        int above = cast(int) floor(-top / edge + 0.5);
        if (above < 0 || above >= MOST_WELL_EDGES || fabs(top + above * edge) > WELL_SLACK * edge) {
            return Found.none;
        } else {
            Turtle mouth = down.forward(-above);
            if (!isOnPlane(mouth) || !isWellMouth(mouth, bed)) {
                return Found.none;
            } else {
                WellDepth depth = wellDepthOf(mouth, bed);
                if (above >= depth.edges) {
                    return Found.none;
                } else {
                    sink(mouth, above, depth, kind, bed);
                    return Found.some;
                }
            }
        }
    }
}

void sink(Turtle mouth, int above, WellDepth depth, ref const Well kind, ref const Bed bed) {
    Flight flight = flightAt(mouth);
    WellShape shape = shapeOf(mouth, bed);
    Material stair = stairOf(kind, shape);
    Turtle top = flight.frame.forward(above);
    stairDown(flight, above, stair, shape);
    lining(top, kind, liningOf(kind, bed, above, top.edgeCells()));
    if (above == depth.edges - 1 && depth.bottom == Bottom.landing) {
        landing(top, stair);
    }
}

void landing(Turtle top, Material stair) {
    int last = top.edgeCells() - 1;
    Span deck = Span(-LANDING_HALF, LANDING_HALF - 1);
    top.paint(stair, boxOf(deck, deck, Span(last, last)));
}

void wellMouth(Turtle start, Lie lie, ref const Well kind, ref const Bed bed) {
    double edge = start.edgeCells();
    double near = lie.near;
    double far = lie.far;
    if (fabs(fabs(far - near) - edge) < VERTICAL_SLACK) {
        Turtle up = start;
        double low = near;
        if (far < near) {
            up = start.forward(1).pitchUp().pitchUp();
            low = far;
        }
        if (fabs(low) < WELL_SLACK * edge && isWellMouth(up, bed)) {
            int ground = cast(int) ceil(up.probeRelief());
            Turtle column = settled(up);
            Span port = Span(-PORT, PORT - 1);
            column.paint(Material.none, boxOf(port, port, Span(0, ground + WELL_ROOM)));
            lining(column, kind, Span(0, ground - 1));
        }
    }
}

Span liningOf(ref const Well kind, ref const Bed bed, int above, int edge) {
    if (above >= WELL_EDGES || (bed.mouth == Mouth.open && above > 0)) {
        return Span(0, -1);
    } else {
        return Span(higherOf(0, kind.liningBelow - above * edge), edge - 1);
    }
}

WellShape shapeOf(Turtle mouth, ref const Bed bed) {
    if (bed.mouth == Mouth.open && unitOf(mouth.probeHash(SitePart.vertex), WELL_SALT) < tuning.squareWellOdds) {
        return WellShape.square;
    } else {
        return WellShape.spiral;
    }
}

Material stairOf(ref const Well kind, WellShape shape) {
    final switch (shape) {
        case WellShape.spiral:
            return kind.stair;
        case WellShape.square:
            return materials.drain;
    }
}

void lining(Turtle top, ref const Well kind, Span z) {
    if (z.low <= z.high) {
        Span across = Span(-PORT - 1, PORT);
        foreach (side; LINING_SIDES) {
            Span wall = Span(side, side);
            top.replace(kind.lining, boxOf(wall, across, z));
            top.replace(kind.lining, boxOf(across, wall, z));
        }
    }
}

void stairDown(Flight flight, int above, Material stair, WellShape shape) {
    Turtle top = flight.frame.forward(above);
    int edge = top.edgeCells();
    int descended = above * edge;
    Span port = Span(-PORT, PORT - 1);
    Span whole = Span(0, edge - 1);
    top.paint(Material.none, boxOf(port, port, whole));
    final switch (shape) {
        case WellShape.spiral:
            Span newel = Span(-1, 0);
            top.paint(stair, boxOf(newel, newel, whole));
            break;
        case WellShape.square:
            break;
    }
    int treads = treadsOf(shape);
    foreach (index; 0 .. treads) {
        Tread tread = wound(treadOf(shape, index), flight.winding);
        top.paint(stair, boxOf(tread.x, tread.y, whole), Rhythm(treads, floorMod(index - descended, treads), 1));
    }
}

int treadsOf(WellShape shape) {
    final switch (shape) {
        case WellShape.spiral:
            return WELL_TREADS;
        case WellShape.square:
            return SQUARE_TREADS;
    }
}

Tread treadOf(WellShape shape, int index) {
    final switch (shape) {
        case WellShape.spiral:
            return wellTreadAt(index);
        case WellShape.square:
            return treadAround(SQUARE_INNER, PORT - SQUARE_INNER, SQUARE_SIDES, index);
    }
}

void flightStops(Turtle mouth, WellShape shape, int edges) {
    Flight flight = flightAt(mouth);
    foreach (step; 0 .. edges * mouth.edgeCells()) {
        Tread tread = wound(treadOf(shape, step), flight.winding);
        flight.frame.stop(middle(tread.x), middle(tread.y), step);
    }
}

void carve(const(Api)* api) {
    Root root;
    api.tileEdges(api, &tile, &root, Root.sizeof);
    api.edgeCeiling(api, SURFACE_BAND);
}

void darken(const(Api)* api, KindTag ground, double depth) {
    api.under(api, ground, LOOK, depth, tuning.fog);
}

void underlie(const(Api)* api) {
    carve(api);
    api.ports(api, tuning.portOdds);
    darken(api, KindTag.init, SEALED_UNDER);
}

struct Entry {
    Vertex surface;
    Way down;
    Ways branches;
    Found found;
}

Way downOf(ref const Vertex at) {
    Way lowest = Way.zPlus;
    foreach (way; WAYS) {
        if (at.up.dot(axisOf(way)) < at.up.dot(axisOf(lowest))) {
            lowest = way;
        }
    }
    return lowest;
}

Entry entryAt(Turtle frame) {
    Vertex surface = vertexAt(frame, frame.openPen());
    return entryUnder(surface);
}

Entry entryUnder(ref const Vertex surface) {
    Entry entry;
    entry.surface = surface;
    entry.down = downOf(entry.surface);
    Vertex bottom = neighborOf(entry.surface, entry.down);
    if (waysUpOf(bottom).has(opposite(entry.down))) {
        Bed bed = Bed.ofSurface(null);
        Memo memo;
        foreach (way; WAYS) {
            if (way != entry.down && way != opposite(entry.down)) {
                Vertex child = neighborOf(bottom, way);
                if (child.height < bottom.height && isTreeLinked(bottom, child, way, bed, memo)) {
                    entry.branches.items[entry.branches.count] = way;
                    entry.branches.count += 1;
                    entry.found = Found.some;
                }
            }
        }
    }
    return entry;
}

Entry clearEntryAt(Turtle frame, ref const Hashes blocked) {
    Entry entry = entryAt(frame);
    if (entry.found == Found.some) {
        bool taken = blocked.contains(frame.probeHash(SitePart.vertex));
        if (!taken) {
            taken = frame.probeRising().exists;
        }
        if (taken) {
            entry.found = Found.none;
        }
    }
    return entry;
}

Entry entryNear(Turtle start, ref const Hashes blocked) {
    Turtle frame = start;
    Entry entry = clearEntryAt(frame, blocked);
    uint tries = 1;
    while (entry.found == Found.none && tries < MOST_ENTRY_TRIES) {
        frame = frame.forward(1);
        if (tries % 3 == 0) {
            frame = frame.right();
        }
        entry = clearEntryAt(frame, blocked);
        tries += 1;
    }
    return entry;
}

struct Stop {
    Turtle site;
    Spot spot;
}

struct Stops {
    Stop[MOST_STOPS] items;
    uint count;

    void add(Turtle site, double x, double y, double z) {
        assert(count < MOST_STOPS);
        items[count] = Stop(site, Spot(cast(float) x, cast(float) y, cast(float) z));
        count += 1;
    }
}

Vec onCircle(Helix helix, double radius, double angle) {
    return helix.start.scaled(radius * cos(angle)).plus(helix.turn.scaled(radius * sin(angle)));
}

double wedgeAngle(double wedge) {
    return (wedge + 0.5) * 2 * PI / TURN_TREADS;
}

Vec toAlong(Way way, Vec chart) {
    Vec x = fromAlong(way, Vec(1, 0, 0));
    Vec y = fromAlong(way, Vec(0, 1, 0));
    Vec z = fromAlong(way, Vec(0, 0, 1));
    return Vec(chart.dot(x), chart.dot(y), chart.dot(z));
}

double sweepTo(Helix helix, double from, Way down, Way way) {
    Vec branch = toAlong(down, axisOf(way));
    double sweep = atan2(branch.dot(helix.turn), branch.dot(helix.start)) - from;
    if (sweep > PI) {
        return sweep - 2 * PI;
    } else if (sweep < -PI) {
        return sweep + 2 * PI;
    } else {
        return sweep;
    }
}

void route(ref const Entry entry) {
    Turtle shaft = along(entry.surface.frame, entry.down);
    Helix helix = helixOf(shaft);
    int edge = shaft.edgeCells();
    Stops stops;
    Vec rim = onCircle(helix, RIM_STOP, wedgeAngle(0));
    stops.add(shaft, rim.x, rim.y, 0);
    foreach (tread; 0 .. TURN_TREADS) {
        Vec at = onCircle(helix, TREAD_MIDDLE, wedgeAngle(tread));
        stops.add(shaft, at.x, at.y, tread);
    }
    Vec outward = onCircle(helix, RING_STOP, wedgeAngle(TURN_TREADS - 1));
    stops.add(shaft, outward.x, outward.y, edge);
    double from = atan2(outward.dot(helix.turn), outward.dot(helix.start));
    Way branch = entry.branches.items[0];
    foreach (way; entry.branches.items[1 .. entry.branches.count]) {
        if (fabs(sweepTo(helix, from, entry.down, way)) < fabs(sweepTo(helix, from, entry.down, branch))) {
            branch = way;
        }
    }
    double sweep = sweepTo(helix, from, entry.down, branch);
    uint arcStops = 1 + cast(uint)(fabs(sweep) * RING_STOP / 2);
    foreach (index; 1 .. arcStops + 1) {
        Vec arc = onCircle(helix, RING_STOP, from + sweep * index / arcStops);
        stops.add(shaft, arc.x, arc.y, edge);
    }
    Turtle bottom = carried(entry.surface.frame, entry.down);
    Turtle tube = along(bottom, branch);
    foreach (cell; TUBE_STOPS) {
        stops.add(tube, 0, 0, cell);
    }
    foreach (index; 0 .. stops.count) {
        Stop stop = stops.items[index];
        stop.site.stop(stop.spot.x, stop.spot.y, stop.spot.z);
    }
    foreach_reverse (index; 0 .. stops.count - 1) {
        Stop stop = stops.items[index];
        stop.site.stop(stop.spot.x, stop.spot.y, stop.spot.z);
    }
}

struct Descent {
    Vertex at;
    uint parent;
    Way way;
}

bool hasChuteBelow(ref const Vertex at, ref const Bed bed, ref Memo memo) {
    Turtle down = along(at.frame, downOf(at));
    Lie lie = lieOf(down);
    double edge = down.edgeCells();
    ulong hash = down.probeHash(SitePart.edge);
    if (!(fabs(fabs(lie.far - lie.near) - edge) < VERTICAL_SLACK && lie.near < -SURFACE_BAND && lie.far < -SURFACE_BAND && lie.far < lie.near)) {
        return false;
    } else if (!(unitOf(hash, DRAIN_SALT) < tuning.drainOdds) || unitOf(hash, DRAIN_SALT + 1) < tuning.drainStairOdds) {
        return false;
    } else {
        return isInOpen(down.forward(1), lie.far) && keeps(at, at.frame.probeHash(SitePart.vertex), bed) && probeWell(at, bed).found == Found.none && opennessOf(at, bed, memo) == Openness.open;
    }
}

void linkStops(ref const Vertex upper, ref const Vertex lower, Way way, bool first) {
    Turtle link = along(upper.frame, way);
    Tube tube = tubeTo(upper, lower, way);
    final switch (tube.form) {
        case Form.passage:
            foreach (cell; TUBE_STOPS) {
                link.stop(0, 0, cell);
            }
            break;
        case Form.shaft:
            Helix helix = helixOf(link);
            if (first) {
                Vec rim = onCircle(helix, RIM_STOP, wedgeAngle(0));
                link.stop(rim.x, rim.y, 0);
            }
            foreach (tread; 0 .. TURN_TREADS) {
                Vec on = onCircle(helix, TREAD_MIDDLE, wedgeAngle(tread));
                link.stop(on.x, on.y, tread);
            }
            break;
    }
}

Found routeToDrain(ref const Entry entry, ref const Root root) {
    Bed bed = Bed.ofSurface(&root);
    Memo memo;
    Descent[MOST_DESCENT] reached;
    reached[0] = Descent(neighborOf(entry.surface, entry.down), 0, entry.down);
    if (!probeSunk(entry.surface, entry.surface.frame.probeHash(SitePart.vertex), bed) || isOverVoid(reached[0].at)) {
        return Found.none;
    }
    uint count = 1;
    uint next = 0;
    while (next < count && !hasChuteBelow(reached[next].at, bed, memo)) {
        foreach (way; WAYS) {
            Vertex child = neighborOf(reached[next].at, way);
            if (count < MOST_DESCENT && child.height < reached[next].at.height && isTreeLinked(reached[next].at, child, way, bed, memo) && (!isOverVoid(child) || hasChuteBelow(child, bed, memo))) {
                reached[count] = Descent(child, next, way);
                count += 1;
            }
        }
        next += 1;
    }
    if (!(next < count && next > 0)) {
        return Found.none;
    } else {
        uint[MOST_DESCENT] path;
        uint steps = 0;
        uint at = next;
        while (at != 0) {
            path[steps] = at;
            steps += 1;
            at = reached[at].parent;
        }
        foreach_reverse (index; 0 .. steps) {
            Descent step = reached[path[index]];
            linkStops(reached[step.parent].at, step.at, step.way, index == steps - 1);
        }
        Turtle chute = along(reached[next].at.frame, downOf(reached[next].at));
        chute.stop(0, 0, 0);
        chute.stop(0, 0, chute.edgeCells() - 1);
        return Found.some;
    }
}

void enter(ref const Entry entry) {
    Way rising = opposite(entry.down);
    Turtle upright = along(entry.surface.frame, rising);
    Helix helix = helixOf(along(entry.surface.frame, entry.down));
    Vec start = fromAlong(entry.down, helix.start);
    Vec inUpright = toAlong(rising, start);
    Turtle door = upright;
    Vec x = Vec(1, 0, 0);
    uint turns = 0;
    while (turns < 4 && x.dot(inUpright) > -0.5) {
        door = door.rollRight();
        x = Vec(x.y, -x.x, 0);
        turns += 1;
    }
    door.entrance(-DOOR_OUT, 0, 0);
}
