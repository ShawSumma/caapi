module plugins.planet.plugin;

import core.stdc.math : fabs, floor;
import plugins.api.api : Api, Box, KindId, KindTag, Material, Registry, Rhythm, Risen, Site, SitePart, Span, Spot, Turn, dataOf, entryOf, tagNamed;
import plugins.api.binding : List, Named, Text, bound, settingsOf;
import plugins.api.content : BASE, Content, Dependency, FIRST_VERSION, Manifest, dependencyOn;
import box = plugins.box.box;
import caves = plugins.caves.caves;
import plugins.connector.connector : Connection;
import plugins.horospheres.horospheres : Kinds, WILD_LOOK, WILD_TAG, addKinds, resolveHorospheres;
import lattice = plugins.lattice.lattice;
import palace = plugins.palace.palace;
import plugins.planet.grove : grove, resolveGrove, stairEntrance, stairRoute;
import plugins.turtle.turtle : Cell, FACE_CORNERS, Found, Hashes, Lie, Turtle, boxOf, cornersOf, higherOf, lieOf, lowerOf, mixed, roll, upright;

enum ulong LAYER_SALT = 0x4C41_5952;
enum ulong TOWER_SALT = 0x544F_5752;
enum ulong TRAIL_SALT = 0x5452_4149;
enum int TRAIL_STEPS = 3;
enum int TRAIL_SHORT = 7;
enum int TRAIL_MOUTH = 12;
enum int TRAIL_HALF = 2;
enum int TRAIL_DEEP = 2;
enum int TRAIL_OVER = 1;
enum double TRAIL_SPAN = 6;
enum int CAIRN_HEIGHT = 3;
enum ulong CROWN_SALT = 0x4352_4F57;
enum double CROWN_LEVEL = 5;
enum Span CROWN_OUTER = Span(5, 11);
enum Span CROWN_INNER = Span(6, 10);
enum int CROWN_SIDE = 4;
enum int CROWN_RING = 4 * CROWN_SIDE;
enum int CROWN_DECK = 12;
enum int CROWN_TOP = 16;
enum int CROWN_FOOTING = 9;
enum Span CROWN_APPROACH = Span(2, 4);
enum int CROWN_LEVEL_CELLS = 6;
enum Span CROWN_DOOR = Span(7, 8);
enum int CROWN_DOOR_HEIGHT = 3;
enum Span CROWN_WALK = Span(2, 4);
enum ulong PALACE_SALT = 0x5041_4C41;
enum double PALACE_DEEPEST = -4;
enum double PALACE_HIGHEST = 4;
enum double PALACE_DOOR_LOWEST = -0.5;
enum uint GROUND_EDGES = 4;
enum double TOWER_RAISED = 0.5;
enum double TOWER_HIGHEST = 2;
enum double SHELTER_SLACK = 0.5;
enum int TREE_EDGES = 1;
enum uint TREE_RISE = 2;
enum int LANDMARK_RINGS = 3;
enum int SINK_EDGES = 2;
enum uint MOST_ROUTE_TRIES = 300;
enum double ROUTE_CRUST = 4.5;
enum int MAZE_EDGES_AWAY = 5;
enum size_t MOST_VOID_LAYERS = 8;
enum size_t MOST_GROUND_RULES = 16;
enum uint LIBRARY_TAG = tagNamed("library:library");
enum uint STACKS_TAG = tagNamed("library:stacks");
enum uint NO_VOID = tagNamed("");
immutable Spot SPAWN = Spot(-14, 12, 0);
immutable Connection CONNECTION = Connection.rolled();

struct LandmarkSites {
    Turtle[4] arms;
    uint next;

    Turtle take() {
        uint arm = next % arms.length;
        Turtle site = arms[arm];
        if (next / arms.length % 2 == 0) {
            arms[arm] = site.forward(2).right();
        } else {
            arms[arm] = site.forward(2).left();
        }
        next += 1;
        return site;
    }
}

struct Clear {
    Hashes vertices;

    void keepFace(Turtle face) {
        foreach (corner; cornersOf(face)) {
            vertices.add(corner.probeHash(SitePart.vertex));
        }
    }

    void keepAround(Turtle site) {
        keepFace(site);
        foreach (corner; cornersOf(site)) {
            keepFace(corner.right());
            keepFace(corner.right().right());
            keepFace(corner.left());
        }
    }
}

struct Placed {
    Turtle[LANDMARK_RINGS * 4] sites;
    uint count;
}

Placed landmarks(const(Api)* api, Turtle at, ref Clear clear) {
    Turtle ahead = at.forward(2).left();
    Turtle behind = at.left().left().forward(2).right();
    Turtle aside = at.left().forward(2);
    Turtle beyond = at.right().forward(5).right();
    LandmarkSites sites = LandmarkSites([ahead.forward(1), behind.forward(1), aside, beyond]);
    Placed placed;
    uint index = 0;
    bool stands = true;
    while (index < placed.sites.length && stands) {
        Turtle site = sites.take();
        stands = api.landmark(api, index, site.site);
        if (stands) {
            api.flatten(api, site.site);
            clear.keepAround(site);
            placed.sites[placed.count] = site;
            placed.count += 1;
        }
        index += 1;
    }
    return placed;
}

caves.Root mouthsOf(const(Api)* api, Turtle at, ref const Clear clear, ref const Placed placed) {
    caves.Root root;
    root.blocked = clear.vertices;
    caves.Entry entry = caves.entryNear(at.right().forward(SINK_EDGES).right().forward(SINK_EDGES), root.blocked);
    if (entry.found == Found.some) {
        root.spawn = entry.surface.frame.probeHash(SitePart.vertex);
        api.flatten(api, entry.surface.frame.site);
    }
    foreach (site; placed.sites[0 .. placed.count]) {
        caves.Entry beside = caves.entryNear(site.left().forward(SINK_EDGES), root.blocked);
        if (beside.found == Found.some) {
            root.forced.add(beside.surface.frame.probeHash(SitePart.vertex));
            api.flatten(api, beside.surface.frame.site);
        }
    }
    return root;
}

enum Homestead : ubyte {
    none,
    watchtower,
}

Homestead homesteadAt(Turtle post, ref const caves.Root root) {
    ulong hash = post.probeHash(SitePart.vertex);
    if (root.blocked.contains(hash) || caves.isRolledMouth(hash, root) || post.probeRising().exists) {
        return Homestead.none;
    } else {
        double relief = post.probeRelief();
        if (relief > TOWER_RAISED && relief < TOWER_HIGHEST && roll(hash, TOWER_SALT) < tuning.towerOdds) {
            return Homestead.watchtower;
        } else {
            return Homestead.none;
        }
    }
}

void watchtower(Turtle post) {
    box.Palette palette = box.palettes.palettes.items[post.probeHash(SitePart.vertex) % box.palettes.palettes.count];
    int top = post.edgeCells() - 2 * box.STORY;
    box.tower(post, top, palette, 0);
    box.buttresses(post, top, palette, 0);
    box.door(post);
    post.paint(fixtures.watchFire, boxOf(Span(-1, 0), Span(-1, 0), Span(top + 1, top + 1)));
    post.paint(fixtures.watchFire, boxOf(Span(box.LOW - 2, box.LOW - 2), Span(2, 2), Span(1, 1)));
}

void shelterAlong(Turtle start, Lie lie, ref const caves.Root root) {
    double edge = start.edgeCells();
    double near = lie.near;
    double far = lie.far;
    Turtle post = start;
    double rise = far - near;
    if (isLevel(far)) {
        post = start.forward(1).pitchUp().pitchUp();
        rise = near - far;
        near = far;
    }
    if (isLevel(near) && rise > edge - SHELTER_SLACK && homesteadAt(post, root) == Homestead.watchtower) {
        watchtower(post);
    }
}

bool isKeptClear(Turtle end, ref const caves.Root root) {
    ulong vertex = end.probeHash(SitePart.vertex);
    if (root.blocked.contains(vertex) || caves.isRolledMouth(vertex, root) || end.probeRising().exists) {
        return true;
    } else {
        bool port = end.probePort();
        return port || homesteadAt(end.pitchUp(), root) != Homestead.none;
    }
}

Box roadBox(Span across, Span height, Span along, Turn up, int sign) {
    Span z = height;
    if (sign < 0) {
        z = Span(-height.high - 1, -height.low - 1);
    }
    if (up == Turn.pitchUp) {
        return boxOf(across, z, along);
    } else {
        return boxOf(z, across, along);
    }
}

struct Skyward {
    Turn up;
    int sign;
}

Skyward skywardOf(Turtle start) {
    double sideways = start.openPen().turn(90, 0).rise();
    double pitched = start.openPen().turn(0, 90).rise();
    Turn up = Turn.pitchUp;
    double rise = pitched;
    if (fabs(sideways) > fabs(pitched)) {
        up = Turn.right;
        rise = sideways;
    }
    int sign = 1;
    if (rise < 0) {
        sign = -1;
    }
    return Skyward(up, sign);
}

Turn upOf(Turtle start) {
    return skywardOf(start).up;
}

Turtle[GROUND_EDGES] groundWaysOf(Turtle heading) {
    Turtle back = heading.pitchUp().pitchUp();
    if (upOf(heading) == Turn.pitchUp) {
        return [heading, back, heading.right(), heading.left()];
    } else {
        return [heading, back, heading.pitchUp(), heading.pitchDown()];
    }
}

struct Pointer {
    Turtle toward;
    ulong vertex;
    Found found;
}

ulong trailRank(ulong vertex) {
    return mixed(vertex, TRAIL_SALT);
}

Pointer parentOf(Turtle heading, ulong own) {
    Pointer best = Pointer(heading, own, Found.none);
    ulong highest = trailRank(own);
    foreach (way; groundWaysOf(heading)) {
        ulong next = way.forward(1).probeHash(SitePart.vertex);
        if (trailRank(next) > highest) {
            highest = trailRank(next);
            best = Pointer(way, next, Found.some);
        }
    }
    return best;
}

bool isMouthAt(Turtle at, ulong vertex, ref const caves.Root root) {
    if (!caves.isRolledMouth(vertex, root)) {
        return false;
    } else {
        caves.Vertex surface = caves.vertexAt(at, at.openPen());
        caves.Bed bed = caves.Bed.ofSurface(&root);
        return caves.probeSunk(surface, vertex, bed);
    }
}

bool probeMouthBehind(Turtle heading, ulong vertex, ref const caves.Root root, int steps) {
    if (isMouthAt(heading, vertex, root)) {
        return true;
    } else if (steps == 0) {
        return false;
    } else {
        foreach (way; groundWaysOf(heading)) {
            Turtle child = way.forward(1);
            ulong childVertex = child.probeHash(SitePart.vertex);
            Pointer up = parentOf(child, childVertex);
            if (up.found == Found.some && up.vertex == vertex && probeMouthBehind(child, childVertex, root, steps - 1)) {
                return true;
            }
        }
        return false;
    }
}

void trailAlong(Turtle start, Lie lie, ref const caves.Root root) {
    if (isLevel(lie.near) && isLevel(lie.far)) {
        ulong first = start.probeHash(SitePart.vertex);
        Turtle end = start.forward(1);
        ulong second = end.probeHash(SitePart.vertex);
        Pointer up = parentOf(start, first);
        if (up.found == Found.some && up.vertex == second && probeMouthBehind(start, first, root, TRAIL_STEPS)) {
            layTrail(start, root);
        } else {
            Pointer down = parentOf(end.pitchUp().pitchUp(), second);
            if (down.found == Found.some && down.vertex == first && probeMouthBehind(end.pitchUp().pitchUp(), second, root, TRAIL_STEPS)) {
                layTrail(end.pitchUp().pitchUp(), root);
            }
        }
    }
}

bool isTrailGround(double relief) {
    return relief > -TRAIL_SPAN && relief < TRAIL_SPAN;
}

void layTrail(Turtle from, ref const caves.Root root) {
    if (isTrailGround(from.probeRelief()) && isTrailGround(from.forward(1).probeRelief()) && !isBesidePalace(from, root)) {
        paintTrail(from, root);
    }
}

void paintTrail(Turtle from, ref const caves.Root root) {
    int length = from.edgeCells();
    Turtle to = from.forward(1);
    int low = TRAIL_SHORT;
    if (isMouthAt(from, from.probeHash(SitePart.vertex), root)) {
        low = TRAIL_MOUTH;
    }
    int high = length - 1;
    if (isMouthAt(to, to.probeHash(SitePart.vertex), root)) {
        high = length - 1 - TRAIL_MOUTH;
    } else if (isKeptClear(to, root)) {
        high = length - 1 - TRAIL_SHORT;
    }
    double rising = to.probeRelief() - from.probeRelief();
    double base = from.probeRelief();
    Skyward sky = skywardOf(from);
    Turn up = sky.up;
    int sign = sky.sign;
    Span wide = Span(-TRAIL_HALF, TRAIL_HALF - 1);
    foreach (at; low .. high + 1) {
        int ground = cast(int) floor(base + rising * at / length);
        from.replace(fixtures.trail, roadBox(wide, Span(ground - TRAIL_DEEP, ground + TRAIL_OVER), Span(at, at), up, sign));
    }
    Pointer onward = parentOf(to, to.probeHash(SitePart.vertex));
    if (onward.found == Found.none) {
        int top = cast(int) floor(base + rising);
        from.paint(fixtures.cairn, roadBox(Span(-1, 0), Span(top, top + CAIRN_HEIGHT - 1), Span(length - 3, length - 2), up, sign));
    }
}

enum Homesteads : ubyte {
    allowed,
    refused,
}

struct Footing {
    double lowest;
    double highest;
    Homesteads homesteads;
}

bool isFreeCorner(Turtle corner, ref const caves.Root root, Footing footing) {
    ulong vertex = corner.probeHash(SitePart.vertex);
    double relief = corner.probeRelief();
    if (!(relief > footing.lowest && relief < footing.highest)) {
        return false;
    } else if (root.blocked.contains(vertex) || caves.isRolledMouth(vertex, root) || corner.probeRising().exists) {
        return false;
    } else if (corner.probePort()) {
        return false;
    } else {
        final switch (footing.homesteads) {
            case Homesteads.allowed:
                return true;
            case Homesteads.refused:
                return homesteadAt(upright(corner), root) == Homestead.none;
        }
    }
}

bool isFreeFace(Turtle face, ref const caves.Root root, Footing footing, ulong salt, double odds) {
    if (!(roll(face.probeHash(SitePart.face), salt) < odds)) {
        return false;
    } else {
        Turtle[FACE_CORNERS] corners = cornersOf(face);
        uint index = 0;
        while (index < FACE_CORNERS && isFreeCorner(corners[index], root, footing)) {
            index += 1;
        }
        return index == FACE_CORNERS;
    }
}

bool isCrownFace(Turtle face, ref const caves.Root root) {
    return isFreeFace(face, root, Footing(-CROWN_LEVEL, CROWN_LEVEL, Homesteads.allowed), CROWN_SALT, tuning.crownOdds);
}

bool isPalaceFace(Turtle face, ref const caves.Root root) {
    if (!isFreeFace(face, root, Footing(PALACE_DEEPEST, PALACE_HIGHEST, Homesteads.refused), PALACE_SALT, tuning.palaceOdds)) {
        return false;
    } else {
        double highest = PALACE_DEEPEST;
        foreach (corner; cornersOf(face)) {
            highest = higherOf(highest, corner.probeRelief());
        }
        return highest > PALACE_DOOR_LOWEST;
    }
}

Turtle groundAlong(Turtle start) {
    if (upOf(start) == Turn.pitchUp) {
        return start;
    } else {
        return start.rollRight();
    }
}

bool isBesidePalace(Turtle start, ref const caves.Root root) {
    Turtle ground = groundAlong(start);
    return isPalaceFace(ground, root) || isPalaceFace(ground.left(), root);
}

Cell treadCell(int step) {
    int place = step % CROWN_RING;
    int side = place / CROWN_SIDE;
    int off = place % CROWN_SIDE;
    if (side == 0) {
        return Cell(CROWN_INNER.low + off, CROWN_INNER.low);
    } else if (side == 1) {
        return Cell(CROWN_INNER.high, CROWN_INNER.low + off);
    } else if (side == 2) {
        return Cell(CROWN_INNER.high - off, CROWN_INNER.high);
    } else {
        return Cell(CROWN_INNER.low, CROWN_INNER.high - off);
    }
}

void crownFooting(Turtle quarter, box.Palette palette) {
    quarter.fill(palette.wall, boxOf(CROWN_OUTER, CROWN_OUTER, Span(-CROWN_FOOTING, -1)));
}

void crownQuarter(Turtle quarter, box.Palette palette) {
    int far = quarter.column().high;
    Span outer = CROWN_OUTER;
    Span inner = CROWN_INNER;
    quarter.paint(palette.wall, boxOf(outer, outer, Span(0, CROWN_TOP)));
    quarter.paint(Material.none, boxOf(inner, inner, Span(1, CROWN_TOP - 1)));
    quarter.paint(palette.floor, boxOf(inner, inner, Span(0, 0)));
    quarter.paint(palette.floor, boxOf(inner, inner, Span(CROWN_DECK, CROWN_DECK)));
    foreach (step; 0 .. CROWN_DECK) {
        Cell at = treadCell(step);
        quarter.paint(palette.trim, boxOf(Span(at.x, at.x), Span(at.y, at.y), Span(step + 1, step + 1)));
    }
    foreach (step; CROWN_DECK - CROWN_SIDE .. CROWN_DECK) {
        Cell at = treadCell(step);
        quarter.paint(Material.none, boxOf(Span(at.x, at.x), Span(at.y, at.y), Span(CROWN_DECK, CROWN_DECK)));
    }
    quarter.paint(Material.none, boxOf(Span(outer.low, outer.low), CROWN_DOOR, Span(1, CROWN_DOOR_HEIGHT)));
    quarter.paint(Material.none, boxOf(CROWN_APPROACH, CROWN_DOOR, Span(1, CROWN_LEVEL_CELLS)));
    Span doorway = Span(CROWN_DECK + 1, CROWN_DECK + CROWN_DOOR_HEIGHT);
    quarter.paint(Material.none, boxOf(CROWN_DOOR, Span(outer.low, outer.low), doorway));
    quarter.paint(Material.none, boxOf(Span(outer.low, outer.low), CROWN_DOOR, doorway));
    quarter.paint(palette.floor, boxOf(Span(outer.low, far), CROWN_WALK, Span(CROWN_DECK, CROWN_DECK)));
    quarter.paint(palette.floor, boxOf(CROWN_WALK, Span(outer.low, far), Span(CROWN_DECK, CROWN_DECK)));
    quarter.paint(palette.trim, boxOf(outer, outer, Span(CROWN_TOP, CROWN_TOP)));
    foreach (x; outer.low .. outer.high + 1) {
        foreach (y; outer.low .. outer.high + 1) {
            bool rim = x == outer.low || x == outer.high || y == outer.low || y == outer.high;
            if (rim && (x + y) % 2 == 0) {
                quarter.paint(palette.trim, boxOf(Span(x, x), Span(y, y), Span(CROWN_TOP + 1, CROWN_TOP + 1)));
            }
        }
    }
    quarter.paint(box.palettes.lamp, boxOf(Span(inner.high, inner.high), Span(inner.high, inner.high), Span(CROWN_TOP - 1, CROWN_TOP - 1)));
}

enum Window : ubyte {
    above,
    below,
}

struct Upright {
    Turtle post;
    Window window;
    Found found;
}

bool isLevel(double height) {
    return height > -SHELTER_SLACK && height < SHELTER_SLACK;
}

Upright uprightAt(Turtle start, Lie lie) {
    double edge = start.edgeCells();
    double near = lie.near;
    double far = lie.far;
    if (isLevel(near) && far > edge - SHELTER_SLACK) {
        return Upright(start, Window.above, Found.some);
    } else if (isLevel(far) && near > edge - SHELTER_SLACK) {
        return Upright(start.forward(1).pitchUp().pitchUp(), Window.above, Found.some);
    } else if (isLevel(near) && far < SHELTER_SLACK - edge) {
        return Upright(start.pitchUp().pitchUp(), Window.below, Found.some);
    } else if (isLevel(far) && near < SHELTER_SLACK - edge) {
        return Upright(start.forward(1), Window.below, Found.some);
    } else {
        return Upright(start, Window.above, Found.none);
    }
}

bool isAbove(Turtle other, double relief, ulong vertex) {
    double theirs = other.probeRelief();
    return theirs > relief || (theirs == relief && other.probeHash(SitePart.vertex) < vertex);
}

bool isDoorCorner(Turtle corner) {
    double relief = corner.probeRelief();
    ulong vertex = corner.probeHash(SitePart.vertex);
    Turtle[FACE_CORNERS] corners = cornersOf(corner);
    uint index = 1;
    while (index < FACE_CORNERS && !isAbove(corners[index], relief, vertex)) {
        index += 1;
    }
    return index == FACE_CORNERS;
}

void palaceQuarter(Turtle corner, Window window) {
    palace.Door door = palace.Door.none;
    if (isDoorCorner(corner)) {
        door = palace.Door.here;
    }
    final switch (window) {
        case Window.above:
            palace.upperQuarter(corner, door, higherOf(0, cast(int) floor(corner.probeRelief())));
            break;
        case Window.below:
            palace.lowerQuarter(corner, door);
            break;
    }
}

void crownAt(Turtle corner, Window window) {
    box.Palette palette = box.palettes.palettes.items[corner.probeHash(SitePart.face) % box.palettes.palettes.count];
    final switch (window) {
        case Window.above:
            crownQuarter(upright(corner), palette);
            break;
        case Window.below:
            crownFooting(upright(corner), palette);
            break;
    }
}

void standingAt(Turtle start, Lie lie, ref const caves.Root root) {
    Upright at = uprightAt(start, lie);
    if (at.found == Found.some) {
        Turtle corner = at.post.rollLeft().pitchDown();
        Turtle[GROUND_EDGES] around = [corner, corner.right(), corner.right().right(), corner.left()];
        foreach (quarter; around) {
            if (isPalaceFace(quarter, root)) {
                palaceQuarter(quarter, at.window);
            } else if (isCrownFace(quarter, root)) {
                crownAt(quarter, at.window);
            }
        }
    }
}

void sink(const(Api)* api, ref const caves.Root root) {
    api.crust(api, KindTag.init, tuning.rootCrust);
    api.thinCrust(api, KindTag.init, tuning.rootThinCrust);
    api.abyss(api, KindTag.init, tuning.rootAbyss);
    api.tileEdges(api, &underground, &root, caves.Root.sizeof);
    api.edgeCeiling(api, caves.SURFACE_BAND);
    api.ports(api, caves.tuning.portOdds);
    caves.darken(api, KindTag.init, caves.OPEN_UNDER);
    const(GroundRule)[] rules = groundRules.grounds.items[0 .. groundRules.grounds.count];
    foreach (ref rule; rules) {
        caves.darken(api, KindTag.of(rule.tag.tag), darknessDepth(rule.under));
    }
    deepen(api, KindTag.init);
    foreach (ref rule; rules) {
        final switch (rule.crust) {
            case GroundCrust.none:
                break;
            case GroundCrust.risen:
                api.crust(api, KindTag.of(rule.tag.tag), tuning.risenCrust);
                api.abyss(api, KindTag.of(rule.tag.tag), tuning.risenAbyss);
                deepen(api, KindTag.of(rule.tag.tag));
                break;
        }
    }
    api.crust(api, KindTag.of(LIBRARY_TAG), tuning.libraryCrust);
    api.crust(api, KindTag.of(STACKS_TAG), tuning.libraryCrust);
    api.abyss(api, KindTag.of(LIBRARY_TAG), tuning.libraryAbyss);
    lattice.deepen(api, KindTag.of(LIBRARY_TAG));
    lattice.hangMaze(api, KindTag.of(lattice.MAZE_TAG));
}

void deepen(const(Api)* api, KindTag ground) {
    double from = 0;
    foreach (ref layer; voidLayers.layers.items[0 .. voidLayers.layers.count]) {
        if (layer.look.text.length > 0) {
            api.underCrust(api, ground, layer.look.text, from, layer.fog);
        }
        from = layer.until;
    }
}

void forcedRoute(const(Api)* api, Site site, const(void)* data) {
    const(caves.Root)* root = &dataOf!(caves.Root)(data);
    Turtle frame = Turtle(api, site);
    uint tries = 0;
    Found routed = Found.none;
    while (routed == Found.none && tries < MOST_ROUTE_TRIES) {
        if (frame.probeCrust() < ROUTE_CRUST) {
            caves.Entry entry = caves.clearEntryAt(frame, root.blocked);
            if (entry.found == Found.some) {
                routed = caves.routeToDrain(entry, *root);
            }
        }
        frame = frame.forward(1);
        if (tries % 3 == 2) {
            frame = frame.right();
        }
        tries += 1;
    }
}

double abyssUnder(ref const Risen risen) {
    if (risen.tag == KindTag.of(LIBRARY_TAG)) {
        return tuning.libraryAbyss;
    } else if (risen.hasRisen) {
        return tuning.risenAbyss;
    } else {
        return tuning.rootAbyss;
    }
}

void voids(Turtle start, Lie lie, double abyss) {
    double edge = start.edgeCells();
    double low = lowerOf(lie.near, lie.far);
    double below = -low / edge - start.probeCrust();
    double shift = roll(start.probeHash(SitePart.edge), LAYER_SALT) - 0.5;
    const(VoidLayer)[] layers = voidLayers.layers.items[0 .. voidLayers.layers.count];
    uint index = 0;
    while (index + 1 < layers.length && !(below < layers[index].until + shift)) {
        index += 1;
    }
    paintVoid(start, lie, abyss, layers[index].world);
    paintVoid(start, lie, abyss, layers[index].over);
    paintVoid(start, lie, abyss, voidLayers.everywhere);
}

void paintVoid(Turtle start, Lie lie, double abyss, Named world) {
    if (world.tag != NO_VOID && !start.api.paintVoid(start.api, world.tag, start.site, lie.near, lie.far, abyss)) {
        start.fail("a void layer names a void world that no plugin registered");
    }
}

void underground(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    Turtle start = Turtle(api, site);
    Lie lie = lieOf(start);
    if (risen.tag != KindTag.of(LIBRARY_TAG)) {
        voids(start, lie, abyssUnder(*risen));
        caves.tile(api, site, risen, data);
    } else {
        lattice.bookVoid(start, lie, tuning.shelfLayer, abyssUnder(*risen));
    }
    if (!risen.hasRisen) {
        const(caves.Root)* root = &dataOf!(caves.Root)(data);
        shelterAlong(start, lie, *root);
        trailAlong(start, lie, *root);
        standingAt(start, lie, *root);
    }
}

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    Clear clear;
    clear.keepAround(at);
    Placed placed = landmarks(api, at, clear);
    caves.Root mouths = mouthsOf(api, at, clear, placed);
    Kinds kinds = addKinds(api, tuning.riseOdds, tuning.treeOdds, &CONNECTION);
    api.rooted(api, kinds.wild);
    api.risingKinds(api, tuning.riseOdds);
    KindId maze = api.hanging(api, tuning.mazeOdds, WILD_TAG, tuning.mazeEdges, lattice.MAZE_TAG, &lattice.maze, null, 0);
    api.look(api, maze, lattice.LOOK);
    api.worldLook(api, WILD_LOOK);
    Turtle tree = at.right().forward(TREE_EDGES);
    api.openHorosphere(api, tree.site, kinds.tree, TREE_RISE);
    api.openHorosphere(api, mazeSiteOf(at).site, maze, tuning.mazeEdges);
    tree.entrance(SPAWN.x, SPAWN.y, SPAWN.z);
    sink(api, mouths);
    at.left().forward(SINK_EDGES).place(&forcedRoute, &mouths, caves.Root.sizeof);
}

Turtle mazeSiteOf(Turtle at) {
    return at.left().left().forward(MAZE_EDGES_AWAY);
}

immutable Dependency[10] NEEDS = [dependencyOn(BASE), dependencyOn("box"), dependencyOn("buildings"), dependencyOn("connector"), dependencyOn("blocks"), dependencyOn("rooms"), dependencyOn("horospheres"), dependencyOn("caves"), dependencyOn("lattice"), dependencyOn("palace")];
struct Tuning {
    double riseOdds;
    double treeOdds;
    double towerOdds;
    double crownOdds;
    double palaceOdds;
    double mazeOdds;
    int mazeEdges;
    double rootCrust;
    double rootThinCrust;
    double risenCrust;
    double rootAbyss;
    double risenAbyss;
    double libraryCrust;
    double libraryAbyss;
    double shelfLayer;
}

enum Darkness : ubyte {
    open,
    sealed,
}

enum GroundCrust : ubyte {
    none,
    risen,
}

struct GroundRule {
    Named tag;
    Darkness under;
    GroundCrust crust;
}

struct GroundRules {
    List!(GroundRule, MOST_GROUND_RULES) grounds;
}

__gshared GroundRules groundRules;

double darknessDepth(Darkness under) {
    final switch (under) {
        case Darkness.open:
            return caves.OPEN_UNDER;
        case Darkness.sealed:
            return caves.SEALED_UNDER;
    }
}

struct VoidLayer {
    double until;
    Named world;
    Named over;
    Text look;
    double fog;
}

struct Voids {
    List!(VoidLayer, MOST_VOID_LAYERS) layers;
    Named everywhere;
}

__gshared Voids voidLayers;

struct Fixtures {
    Material watchFire;
    Material trail;
    Material cairn;
}

__gshared Fixtures fixtures;

__gshared Tuning tuning;

void resolve(const(Content)* content) {
    resolveHorospheres(content);
    box.resolveBox(content);
    caves.resolveCaves(content);
    lattice.resolveLattice(content);
    palace.resolvePalace(content);
    resolveGrove(content);
    tuning = content.settingsOf!Tuning("planet");
    fixtures = content.bound!Fixtures("planet:fixtures");
    voidLayers = content.bound!Voids("planet:voids");
    groundRules = content.bound!GroundRules("planet:grounds");
}

immutable Manifest MANIFEST = Manifest("planet", FIRST_VERSION, NEEDS[], null, &resolve, null, import("plugins/planet/settings.conf"), import("plugins/planet/planet.decl"), import("plugins/planet/planet.content"));

void groveLandmark(const(Api)* api, Site site, const(void)* data) {
    Turtle at = Turtle(api, site);
    grove(at);
    stairRoute(at);
}

void groveRig(const(Api)* api, Site site, const(void)* data) {
    groveLandmark(api, site, data);
    stairEntrance(Turtle(api, site));
    api.worldLook(api, WILD_LOOK);
}

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.add(registry, "planet", &world);
    registry.addDebug(registry, "grove", &groveRig);
    registry.addLandmark(registry, "grove", &groveLandmark);
}
