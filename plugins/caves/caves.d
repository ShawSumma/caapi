module plugins.caves.caves;

import core.stdc.math : asinh, atan2, cos, fabs, floor, sin, sqrt, tanh;
import plugins.api.api : Api, HorosphereForm, KindTag, Material, Pen, Rhythm, Risen, Site, SitePart, Span, Spot;
import plugins.api.binding : bound, kebabOf;
import plugins.api.content : Content, settingAt;
import plugins.carve.carve : Choice, Painting, Triad, Vec, WAYS, WAY_COUNT, Way, aimed, along, axisOf, between, carried, chartOf, degreesOf, dot, edgeHash, emit, fromAlong, isOwnedBy, latticeHash, minus, mixed, noiseAt, normalized, opposite, penCarried, physicalOf, plus, rejected, scaled, slabAt, squared, triadAt, unitOf, upOf;
import plugins.turtle.turtle : Drawing, Hashes, PI, PORT, TURN_TREADS, Tread, Turtle, boxOf, clamped, settled, treadAround;

enum string NAME = "caves";
enum string LOOK = "caves:look";
enum double SURFACE_BAND = 6;
enum double SEALED_TOP = 1.9;
enum double RISEN_DEPTH = 3;
enum double OPEN_UNDER = 0.5;
enum double SEALED_UNDER = 1.5;
enum int WELL_EDGES = 2;
enum int WELL_TREADS = 8;
enum double WELL_SLACK = 0.02;
enum double VERTICAL_SLACK = 0.5;
enum double MIN_CLIMB = 1.37;
enum double WALKABLE_RISE = 47.3;
enum double STEEP_RISE = 65;
enum double RISE_STEP = 0.25;
enum double MAX_DEPTH = 5.2;
enum double ROCK_MARGIN = 0.5;
enum double FIRST_BAND = 1.6;
enum uint BAND_COUNT = 5;
enum uint MOST_KNOWN = 256;
enum uint MOST_CHAIN = 128;
enum uint MOST_ENTRY_TRIES = 12;
enum uint MOST_FORMATIONS = 16;
enum uint MOST_STOPS = 96;
enum uint CHANDELIER_ATTEMPTS = 4;
enum ulong CHANDELIER_SALT_STEP = 256;
struct Tuning {
    double[BAND_COUNT] keepOdds;
    double[BAND_COUNT] radii;
    double[BAND_COUNT] domeBase;
    double fog;
    double rootOdds;
    double headOdds;
    double portOdds;
    double chamberOdds;
}

__gshared Tuning tuning;

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
}

struct Materials {
    Material stair;
}

__gshared Rules[THEME_COUNT] rules;
__gshared Materials materials;

void resolveCaves(const(Content)* content) {
    static foreach (member; __traits(allMembers, Theme)) {
        rules[__traits(getMember, Theme, member)] = content.bound!Rules(NAME ~ ":" ~ kebabOf!member);
    }
    materials = content.bound!Materials(NAME ~ ":materials");
    tuning.fog = content.setting(content, NAME, "fog");
    tuning.rootOdds = content.setting(content, NAME, "root-odds");
    tuning.headOdds = content.setting(content, NAME, "head-odds");
    tuning.portOdds = content.setting(content, NAME, "port-odds");
    tuning.chamberOdds = content.setting(content, NAME, "chamber-odds");
    foreach (band; 0 .. BAND_COUNT) {
        tuning.keepOdds[band] = content.settingAt(NAME, "keep-odds", band);
        tuning.radii[band] = content.settingAt(NAME, "tube-radii", band);
        tuning.domeBase[band] = content.settingAt(NAME, "dome-sizes", band);
    }
}
enum double LEAST_RADIUS = 3.5;
enum double MOST_RADIUS = 10.5;
enum double MOST_DOME = 11.2;
enum double ENTRY_DOME = 10.8;
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
enum double FROST_DEPTH = 1.3;
enum double GLOW_DEPTH = 2.3;
enum double GYPSUM_DEPTH = 3.3;
enum double CRYSTAL_DEPTH = 4.3;
enum ulong ROOT_SALT = 0x52_4F4F_54;
enum ulong HEAD_SALT = 0x48_4541_44;
enum ulong KEEP_SALT = 0x4B_4545_50;
enum ulong BULGE_SALT = 0x42_554C_47;
enum ulong DOME_SALT = 0x44_4F4D_45;
enum ulong FORM_SALT = 0x46_4F52_4D;
enum ulong CELL_SALT = 0x43_454C_4C;
enum ulong FLOOR_SALT = 0x46_4C4F_52;
enum double RING_STOP = SHAFT_RADIUS + 1.5;
immutable int[3] TUBE_STOPS = [13, 17, 21];

enum Found : ubyte {
    none,
    some,
}

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

enum Theme : ubyte {
    opening,
    frost,
    glow,
    gypsum,
    crystal,
    ember,
}

enum Shape : ubyte {
    cone,
    beam,
}

enum uint THEME_COUNT = Theme.max + 1;

struct Spread {
    double low;
    double high;
}

Choice choiceOf(Material material) {
    if (material == Material.none) {
        return Choice.keep();
    } else {
        return Choice.of(material);
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
}

enum Mouth : ubyte {
    none,
    open,
    sealed,
}

struct Bed {
    const(Root)* root;
    double top = 0;
    double bottom = MAX_DEPTH;
    Mouth mouth;

    static Bed ofSurface(const(Root)* root) {
        return Bed(root, 0, MAX_DEPTH, Mouth.open);
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

    bool isWay(Way other) const {
        return found == Found.some && way == other;
    }
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
    Parent well;
    ulong seed;
    double dome = 0;
    double domeHeight = 0;
    double bowl = 0;
    double edge = 0;
    double mouth = 0;
    uint count;
    uint formationCount;
    Theme theme;

    void add(Formation formation) {
        if (formationCount < MOST_FORMATIONS) {
            formations[formationCount] = formation;
            formationCount += 1;
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

Theme themeOf(ref const Vertex at) {
    double depth = depthOf(at);
    if (isSurface(at)) {
        return Theme.opening;
    } else if (depth < FROST_DEPTH) {
        return Theme.frost;
    } else if (depth < GLOW_DEPTH) {
        return Theme.glow;
    } else if (depth < GYPSUM_DEPTH) {
        return Theme.gypsum;
    } else if (depth < CRYSTAL_DEPTH) {
        return Theme.crystal;
    } else {
        return Theme.ember;
    }
}

Parent parentOf(ref const Vertex at) {
    Parent walkable;
    ulong walkableHash = ulong.max;
    Parent steep;
    double steepRise = -1;
    ulong steepHash = ulong.max;
    foreach (way; WAYS) {
        if (at.climbs[way] > MIN_CLIMB) {
            double rise = riseOf(at, way);
            ulong hash = edgeHash(at.frame, way);
            if (rise <= WALKABLE_RISE) {
                if (hash < walkableHash) {
                    walkableHash = hash;
                    walkable = Parent(way, Found.some);
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
    if (walkable.found == Found.some) {
        return walkable;
    } else {
        return steep;
    }
}

bool probeSunk(ref const Vertex at, ulong hash, ref const Root root) {
    if (hash == root.spawn) {
        return true;
    } else if (root.blocked.contains(hash) || !(unitOf(hash, ROOT_SALT) < tuning.rootOdds)) {
        return false;
    } else {
        bool rising = at.frame.probeRising().exists;
        if (rising) {
            return false;
        } else {
            double relief = at.frame.probeRelief();
            return relief > MOUTH_LOW && relief < MOUTH_HIGH;
        }
    }
}

double mouthOf(ref const Vertex at) {
    return clamped(at.frame.probeRelief(), MOUTH_LOW, MOUTH_HIGH);
}

bool keeps(ref const Vertex at, ulong hash, ref const Bed bed) {
    double depth = depthOf(at);
    return depth <= bed.bottom && depth >= bed.top && unitOf(hash, KEEP_SALT) < tuning.keepOdds[bandOf(depth)] && depth <= at.frame.probeCrust() - ROCK_MARGIN;
}

bool isAboveBed(ref const Vertex at, ref const Bed bed) {
    return bed.mouth == Mouth.sealed && depthOf(at) < bed.top;
}

Parent probeWell(ref const Vertex at, ref const Bed bed) {
    double edge = at.frame.edgeCells();
    if (bed.mouth != Mouth.sealed || fabs(depthOf(at) - WELL_EDGES) > WELL_SLACK) {
        return Parent.init;
    } else {
        Parent up;
        foreach (way; WAYS) {
            if (at.climbs[way] > edge - VERTICAL_SLACK) {
                up = Parent(way, Found.some);
            }
        }
        if (up.found == Found.none) {
            return up;
        } else {
            bool port = along(at.frame, up.way).forward(WELL_EDGES).probePort();
            if (port) {
                return up;
            } else {
                return Parent.init;
            }
        }
    }
}

Parent linkedParentOf(ref const Vertex at, ref const Bed bed) {
    Parent parent = parentOf(at);
    if (parent.found == Found.none) {
        return parent;
    } else {
        Vertex above = neighborOf(at, parent.way);
        if (isAboveBed(above, bed)) {
            return Parent.init;
        } else {
            return parent;
        }
    }
}

Openness opennessOf(ref const Vertex start, ref const Bed bed, ref Memo memo) {
    ulong[MOST_CHAIN] chain;
    uint length = 0;
    Vertex at = start;
    Openness result = Openness.closed;
    Found decided = Found.none;
    while (decided == Found.none) {
        ulong hash = at.frame.probeHash(SitePart.vertex);
        uint index = 0;
        while (index < memo.count && memo.items[index].hash != hash) {
            index += 1;
        }
        decided = Found.some;
        if (index < memo.count) {
            result = memo.items[index].openness;
        } else {
            if (length < MOST_CHAIN) {
                chain[length] = hash;
                length += 1;
            }
            if (isSurface(at)) {
                if (bed.mouth == Mouth.open) {
                    bool sunk = probeSunk(at, hash, *bed.root);
                    if (sunk) {
                        result = Openness.open;
                    }
                }
            } else if (at.height < 0) {
                Parent well = probeWell(at, bed);
                if (well.found == Found.some) {
                    result = Openness.open;
                } else if (keeps(at, hash, bed)) {
                    Parent parent = parentOf(at);
                    if (parent.found == Found.some) {
                        Vertex above = neighborOf(at, parent.way);
                        if (!isAboveBed(above, bed)) {
                            at = above;
                            decided = Found.none;
                        } else if (unitOf(hash, HEAD_SALT) < tuning.headOdds) {
                            result = Openness.open;
                        }
                    }
                }
            }
        }
    }
    foreach (hash; chain[0 .. length]) {
        memo.note(hash, result);
    }
    return result;
}

double radiusOf(ref const Vertex near, ref const Vertex far) {
    double depth = depthOf(near);
    if (depthOf(far) > depth) {
        depth = depthOf(far);
    }
    return tuning.radii[bandOf(depth)];
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

bool isLinked(ref const Vertex at, Parent parent, ref const Vertex to, Way way, ref const Bed bed) {
    if (parent.isWay(way)) {
        return true;
    } else if (isSurface(to) || !(to.height < at.height)) {
        return false;
    } else {
        Parent back = parentOf(to);
        return back.isWay(opposite(way)) && keeps(to, to.frame.probeHash(SitePart.vertex), bed);
    }
}

double bowlOf(ref const Vertex at) {
    Pen pen = at.pen.pen;
    double sinh = pen.ground[0] * pen.frame[12] + pen.ground[1] * pen.frame[13] + pen.ground[2] * pen.frame[14] - pen.ground[3] * pen.frame[15];
    double depth = asinh(sinh);
    return fabs(tanh(depth)) / 2 * depth / at.height;
}

Scene sceneAt(ref const Vertex at, ref const Bed bed) {
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
    scene.theme = themeOf(at);
    Parent parent;
    if (!isSurface(at)) {
        parent = linkedParentOf(at, bed);
        scene.well = probeWell(at, bed);
    }
    double widest = 0;
    uint shafts = 0;
    foreach (way; WAYS) {
        Vertex to = neighborOf(at, way);
        if (isLinked(at, parent, to, way, bed)) {
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
    if (scene.theme != Theme.opening) {
        uint band = bandOf(depthOf(at));
        double dome = widest + JUNCTION_MARGIN;
        if (scene.count >= 3 || unitOf(scene.seed, DOME_SALT) < tuning.chamberOdds) {
            dome = tuning.domeBase[band] + between(scene.seed, DOME_SALT + 1, -DOME_SPREAD, DOME_SPREAD);
        }
        if (scene.theme == Theme.frost) {
            dome = ENTRY_DOME;
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
        addFormations(scene);
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
                scene.add(Formation(hub, direction, length, pickIn(scene.seed, armSalt + 5, ARM_WIDTH), rules[scene.theme].chandelier, Shape.cone));
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
    scene.add(Formation(base, direction, length, pickIn(scene.seed, salt + 6, BEAM_WIDTH), rules[scene.theme].beam, Shape.beam));
}

void addFormations(ref Scene scene) {
    Rules rule = rules[scene.theme];
    final switch (scene.theme) {
        case Theme.opening:
            break;
        case Theme.frost:
            foreach (index; 0 .. ICICLES) {
                ulong salt = FORM_SALT + index * SALT_STRIDE;
                hang(scene, salt, rule.hanging, ICICLE_LENGTH, pickIn(scene.seed, salt + 5, ICICLE_WIDTH));
            }
            break;
        case Theme.glow:
            foreach (index; 0 .. GLOW_HANGING) {
                hang(scene, FORM_SALT + index * SALT_STRIDE, rule.hanging, DRIPSTONE_LENGTH, DRIPSTONE_WIDTH);
            }
            foreach (index; GLOW_HANGING .. GLOW_HANGING + GLOW_STANDING) {
                stand(scene, FORM_SALT + index * SALT_STRIDE, rule.standing, DRIPSTONE_LENGTH, PILLAR_WIDTH);
            }
            break;
        case Theme.gypsum:
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
        case Theme.crystal:
            uint beams = LEAST_BEAMS + cast(uint)(unitOf(scene.seed, FORM_SALT) * BEAM_CHOICES);
            foreach (index; 0 .. beams) {
                crystal(scene, FORM_SALT + BEAM_SALT + index * BEAM_STRIDE);
            }
            break;
        case Theme.ember:
            foreach (index; 0 .. EMBER_STANDING) {
                stand(scene, FORM_SALT + index * SALT_STRIDE, rule.standing, BASALT_LENGTH, BASALT_WIDTH);
            }
            foreach (index; EMBER_STANDING .. EMBER_STANDING + EMBER_HANGING) {
                hang(scene, FORM_SALT + index * SALT_STRIDE, rule.hanging, DRIPSTONE_LENGTH, DRIPSTONE_WIDTH);
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
                double height = floorHeight(tube, point, up, edge);
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
    return scene.theme == Theme.opening && height > scene.mouth;
}

Space spaceAt(ref const Scene scene, Vec point) {
    double raw = point.dot(scene.at.up);
    double across = point.squared - raw * raw;
    double height = raw - scene.bowl * across;
    Space found = Space.rock;
    if (scene.theme == Theme.opening) {
        if (height > 0 && height < scene.mouth + MOUTH_ROOM && across < SHAFT_RADIUS * SHAFT_RADIUS) {
            found = mouthSpace(scene, point, height, across);
        }
    } else if (height >= 0 && across / (scene.dome * scene.dome) + height * height / (scene.domeHeight * scene.domeHeight) < 1) {
        found = Space.air;
    }
    if (found == Space.tread) {
        return Space.tread;
    }
    foreach (index; 0 .. scene.count) {
        Space inside = tubeSpace(scene.tubes[index], point, scene.at.up, scene.edge);
        if (inside == Space.tread && !isOverMouth(scene, height)) {
            return Space.tread;
        } else if (inside != Space.rock) {
            found = Space.air;
        }
    }
    if (found == Space.air && isUnderRamp(scene, point)) {
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
    Rules rule = rules[scene.theme];
    if (patchAt(scene, point) > rule.floorThreshold) {
        return choiceOf(rule.patched);
    } else {
        return choiceOf(rule.elsewhere);
    }
}

Choice ceilingChoice(ref const Scene scene, Vec point) {
    Rules rule = rules[scene.theme];
    double odds = rule.ceilingOdds * (1 - rule.patchiness + rule.patchiness * patchAt(scene, point));
    double roll = cellRoll(scene, point);
    if (roll < odds) {
        return Choice.of(rule.lit);
    } else if (roll < odds + rule.veinOdds) {
        return Choice.of(rule.veined);
    } else {
        return Choice.keep();
    }
}

bool isInWell(ref const Scene scene, Vec point) {
    if (scene.well.found == Found.none) {
        return false;
    } else {
        Vec axis = axisOf(scene.well.way);
        double height = point.dot(axis);
        Vec side = point.minus(axis.scaled(height));
        return height > 0 && fabs(side.x) < PORT && fabs(side.y) < PORT && fabs(side.z) < PORT;
    }
}

Choice choiceAt(ref const Scene scene, Vec point) {
    if (isInWell(scene, point)) {
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
            double top = scene.mouth + pickIn(scene.seed, salt + 3, STONE_HEIGHT);
            if (side.dot(gate) < STONE_GATE && offset.squared - height * height < STONE_REACH * STONE_REACH && height > scene.mouth - STONE_FOOT && height < top) {
                if (index == 0 && height >= top - 1) {
                    return Choice.of(rules[Theme.opening].lit);
                } else {
                    return Choice.of(materials.stair);
                }
            }
        }
        return Choice.keep();
    }
}

Choice chosenAt(ref const Scene scene, Vec point) {
    if (scene.theme != Theme.opening) {
        return carvedAt(scene, point);
    } else {
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
                    return Choice.of(scene.formations[index].material);
                }
            }
            return Choice.of(Material.none);
        case Space.rock:
            foreach (index; 0 .. scene.formationCount) {
                if (scene.formations[index].shape == Shape.beam && isInside(scene.formations[index], point)) {
                    return Choice.of(scene.formations[index].material);
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
                Scene scene = sceneAt(at, bed);
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
    if (bed.mouth == Mouth.sealed) {
        well(Turtle(api, site));
    }
}

void well(Turtle start) {
    double edge = start.edgeCells();
    Drawing pen = start.openPen();
    double near = pen.height();
    double far = pen.forward(edge).height();
    if (fabs(fabs(far - near) - edge) < VERTICAL_SLACK) {
        Turtle down = start;
        double top = near;
        if (far > near) {
            down = start.forward(1).pitchUp().pitchUp();
            top = far;
        }
        int above = cast(int) floor(-top / edge + 0.5);
        if (above >= 0 && above < WELL_EDGES) {
            Turtle mouth = down.forward(-above);
            bool port = mouth.probePort();
            if (port) {
                stairDown(settled(mouth).forward(above));
            }
        }
    }
}

void stairDown(Turtle top) {
    Span port = Span(-PORT, PORT - 1);
    Span newel = Span(-1, 0);
    Span whole = Span(0, top.edgeCells() - 1);
    top.paint(Material.none, boxOf(port, port, whole));
    top.paint(materials.stair, boxOf(newel, newel, whole));
    foreach (index; 0 .. WELL_TREADS) {
        Tread tread = treadAround(1, PORT - 1, 1, index);
        top.paint(materials.stair, boxOf(tread.x, tread.y, whole), Rhythm(WELL_TREADS, index, 1));
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
    Way branch;
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
    Entry entry;
    entry.surface = vertexAt(frame, frame.openPen());
    entry.down = downOf(entry.surface);
    Vertex bottom = neighborOf(entry.surface, entry.down);
    if (parentOf(bottom).isWay(opposite(entry.down))) {
        Bed bed = Bed.ofSurface(null);
        foreach (way; WAYS) {
            if (entry.found == Found.none && way != entry.down && way != opposite(entry.down)) {
                Vertex child = neighborOf(bottom, way);
                if (isLinked(bottom, Parent(opposite(entry.down), Found.some), child, way, bed)) {
                    entry.branch = way;
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
    Vec branch = toAlong(entry.down, axisOf(entry.branch));
    Vec outward = onCircle(helix, RING_STOP, wedgeAngle(TURN_TREADS - 1));
    stops.add(shaft, outward.x, outward.y, edge);
    double from = atan2(outward.dot(helix.turn), outward.dot(helix.start));
    double to = atan2(branch.dot(helix.turn), branch.dot(helix.start));
    double sweep = to - from;
    if (sweep > PI) {
        sweep -= 2 * PI;
    } else if (sweep < -PI) {
        sweep += 2 * PI;
    }
    uint arcStops = 1 + cast(uint)(fabs(sweep) * RING_STOP / 2);
    foreach (index; 1 .. arcStops + 1) {
        Vec arc = onCircle(helix, RING_STOP, from + sweep * index / arcStops);
        stops.add(shaft, arc.x, arc.y, edge);
    }
    Turtle bottom = carried(entry.surface.frame, entry.down);
    Turtle tube = along(bottom, entry.branch);
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
