module plugins.rooms.layout;

import plugins.api.api : Api, MaybeIndex, Risen, Site, SitePart;
import plugins.api.binding : Weighted, bound, settingsOf;
import plugins.api.content : Content;
import blocks = plugins.blocks.blocks;
import plugins.buildings.building : SIDES, Side;
import plugins.connector.connector : Routing;
import plugins.rooms.levels : Biome, Bounds, FIELD_COUNT, Field, HallLayout, Level, MOST_BIOMES, MOST_LEVELS, Opening, PlanRow, Rare, Rarity, Rooms, Tuning, rooms, tuning;
import plugins.rooms.rooms : Axis, CHAPEL_RISE, COURT_TRUNK, Doors, Floor, Frame, Halls, Laid, MAZE_CELLS, MaybeLayer, Owns, Plan, Quarter, QuarterKind, ROOF, SEPARATION, Stair, WallForm, WellDoor, frameOf, origin, paintFloor, stairs;
import plugins.turtle.turtle : FACE_CORNERS, Turtle, cornersOf, higherOf, lowerOf, mixed, ownerAround, roll, upright;

enum int DOOR_LOW = 3;
enum int DOOR_HIGH = 8;
enum ulong SLOT_SALT = 0x2F4A7C15;
enum ulong SECOND_SALT = 0x4F1BBCDD;
enum ulong OFFSET_SALT = 0x6B43A9B5;
enum ulong MISSING_SALT = 0x1F83D9AB;
enum ulong DOOR_SALT = 0x5BE0CD19;
enum ulong STAIR_SALT = 0x6A09E667;
enum ulong STAIR_ODDS_SALT = 0x510E527F;
enum ulong PICK_SALT = 0x3C6EF372;
enum ulong RARE_SALT = 0x4A7C15F3;
enum ulong RARE_STRIDE = 16;
immutable Side[2] OUTER_SIDES = [Side.xLow, Side.yLow];
enum uint RING_FACES = FACE_CORNERS + 1;
enum uint BALL_FACES = RING_FACES * RING_FACES;
enum uint FIELD_STEPS = 1000;
immutable ulong[FIELD_COUNT] FIELD_SALTS = [0x9E3779B9, 0x85EBCA6B, 0xC2B2AE35, 0x27D4EB2F];
immutable Reach[FIELD_COUNT] FIELD_REACH = [Reach.ring, Reach.ball, Reach.ball, Reach.ring];

enum Reach : ubyte {
    ring,
    ball,
}
enum ulong HALL_SALT = 0x7F4A7C15;
enum ulong SOLID_SALT = 0x1B873593;
enum ulong PLAN_SALT = 0x5BD1E995;
enum ulong FORM_SALT = 0x243F6A88;

enum Shaft : ubyte {
    none,
    open,
}

enum Passage : ubyte {
    open,
    closed,
}

struct ForcedStair {
    ulong vertex;
    ulong face;
    MaybeLayer upper;
}

struct Root {
    ulong vertex;
    Shaft shaft;
    Routing routing;
    ForcedStair forced;
}

struct Line {
    ulong hash;
    ulong beyond;
}

__gshared Floor[MOST_LEVELS] floors;

void resolveRooms(const(Content)* content) {
    blocks.resolveStreets(content);
    rooms = content.bound!Rooms("rooms:materials");
    tuning = content.settingsOf!Tuning("rooms");
    int base = rooms.ground.level - 1;
    foreach (index; 0 .. rooms.levels.count) {
        if (index > 0) {
            base = base - rooms.levels.items[index].room - SEPARATION - 2;
        }
        floors[index] = Floor(index, base);
    }
}

uint floorCount() {
    return rooms.levels.count;
}

double reachAbove() {
    int top = floors[0].base;
    return higherOf(top + floors[0].level().room + 1 + CHAPEL_RISE + ROOF, top + COURT_TRUNK + 1) + 1;
}

double reachBelow() {
    return SEPARATION - floors[floorCount() - 1].base;
}

bool probeHall(Turtle turtle, ref const Root root, ref const Level level, size_t index) {
    if (level.halls == HallLayout.none) {
        return false;
    } else if (level.halls == HallLayout.streets) {
        blocks.Root streets = blocks.Root(root.vertex);
        return blocks.probeStreet(turtle, streets);
    } else {
        ulong start = turtle.probeHash(SitePart.vertex);
        bool rooted = start == root.vertex;
        if (!rooted) {
            ulong end = turtle.forward(1).probeHash(SitePart.vertex);
            rooted = end == root.vertex;
        }
        if (!rooted) {
            double rolled = roll(turtle.probeHash(SitePart.edge), HALL_SALT + index);
            rooted = rolled >= tuning.gridDropped;
        }
        return rooted;
    }
}

bool isSolid(ulong face, ref const Level level, size_t index) {
    return roll(face, SOLID_SALT + index) < level.solid;
}

Doors lineDoors(ulong hash, size_t index, ref const Level level, Passage passage) {
    if (level.isMaze()) {
        int first = cast(int)(mixed(hash, SLOT_SALT + index) % MAZE_CELLS);
        Doors slots = Doors.one(first);
        if (roll(hash, SECOND_SALT + index) < tuning.secondPassageOdds) {
            slots.at[1] = cast(int)((first + 1 + mixed(hash, OFFSET_SALT + index) % (MAZE_CELLS - 1)) % MAZE_CELLS);
            slots.count = 2;
        }
        return slots;
    } else if (passage == Passage.closed) {
        return Doors.init;
    } else if (roll(hash, MISSING_SALT + index) < level.missing) {
        return Doors([0, 0], 0, WallForm.missing);
    } else {
        return Doors.one(DOOR_LOW + cast(int)(mixed(hash, DOOR_SALT + index) % (DOOR_HIGH - DOOR_LOW + 1)));
    }
}

Line[4] linesOf(Turtle corner) {
    ulong vertex = corner.probeHash(SitePart.vertex);
    ulong face = corner.probeHash(SitePart.face);
    ulong edgeY = corner.probeHash(SitePart.edge);
    ulong edgeX = corner.right().probeHash(SitePart.edge);
    Line[4] lines;
    lines[Side.yLow] = Line(edgeY ^ vertex, corner.left().probeHash(SitePart.face));
    lines[Side.xLow] = Line(edgeX ^ vertex, corner.right().probeHash(SitePart.face));
    lines[Side.xHigh] = Line(edgeY ^ face, face);
    lines[Side.yHigh] = Line(edgeX ^ face, face);
    return lines;
}

bool probeForcedStair(Turtle corner, ref const Root root) {
    if (root.forced.upper.exists) {
        ulong vertex = corner.probeHash(SitePart.vertex);
        ulong face = corner.probeHash(SitePart.face);
        return vertex == root.forced.vertex && face == root.forced.face;
    } else {
        return false;
    }
}

Stair stairOf(Turtle corner, ref const Root root, ref const Halls[MOST_LEVELS] halls, ref const Quarter q) {
    ulong hash = corner.probeHash(SitePart.vertex) ^ corner.probeHash(SitePart.face);
    uint upper = cast(uint)(mixed(hash, STAIR_SALT) % (floorCount() - 1));
    bool forced = probeForcedStair(corner, root);
    if (forced) {
        upper = root.forced.upper.value;
    }
    if (q.isLobby() || (!forced && roll(hash, STAIR_ODDS_SALT) >= floors[upper].level.stairs)) {
        return Stair.init;
    } else {
        uint lower = upper + 1;
        int x = origin(halls[upper], Axis.x, floors[upper].level);
        int otherX = origin(halls[lower], Axis.x, floors[lower].level);
        int y = origin(halls[upper], Axis.y, floors[upper].level);
        int otherY = origin(halls[lower], Axis.y, floors[lower].level);
        return Stair(MaybeLayer.of(upper), lower, higherOf(x, otherX), higherOf(y, otherY));
    }
}

Laid laidOf(PlanRow row, ref const Floor floor) {
    final switch (row.plan) {
        case Opening.rooms:
            return Laid.of(Plan.rooms);
        case Opening.pillars:
            return Laid(Plan.pillars, row.pillarEvery);
        case Opening.pool:
            return Laid.of(Plan.pool);
        case Opening.court:
            if (floor.isTop()) {
                return Laid.of(Plan.court);
            } else {
                return Laid.of(Plan.rooms);
            }
    }
}

Laid openPlan(double chance, ref const Floor floor, ref const Biome biome) {
    const(Weighted!PlanRow)[] rows = biome.plans.slice();
    double total = 0;
    foreach (ref row; rows) {
        total += row.weight;
    }
    double left = chance * total;
    size_t index = 0;
    while (index < rows.length && !(left < rows[index].weight)) {
        left -= rows[index].weight;
        index += 1;
    }
    if (index == rows.length) {
        return Laid.of(Plan.rooms);
    } else {
        return laidOf(rows[index].target, floor);
    }
}

bool isRareHere(ulong face, ref const Rare rare, ref const Floor floor, size_t index, uint row, Halls halls) {
    if (mixed(face, RARE_SALT + index * RARE_STRIDE + row) % rare.oneIn != 0) {
        return false;
    } else {
        final switch (rare.plan) {
            case Rarity.chapel:
                return !halls.has(Axis.x) && !halls.has(Axis.y);
            case Rarity.court:
                return floor.isTop();
            case Rarity.rings:
            case Rarity.pillars:
            case Rarity.pool:
                return true;
        }
    }
}

MaybeIndex!Rare rareOn(ulong face, ref const Floor floor, size_t index, Halls halls) {
    const(Level)* level = &floor.level();
    uint row = 0;
    while (row < level.rare.count && !isRareHere(face, level.rare.items[row], floor, index, row, halls)) {
        row += 1;
    }
    if (row < level.rare.count) {
        return MaybeIndex!Rare.of(row);
    } else {
        return MaybeIndex!Rare.init;
    }
}

Plan planOfRare(Rarity rarity) {
    final switch (rarity) {
        case Rarity.rings:
            return Plan.rings;
        case Rarity.chapel:
            return Plan.chapel;
        case Rarity.pillars:
            return Plan.pillars;
        case Rarity.pool:
            return Plan.pool;
        case Rarity.court:
            return Plan.court;
    }
}

Laid planOf(Turtle corner, ref const Quarter q, ref const Stair stair, ref const Floor floor, size_t index, Halls halls, ref const Biome biome) {
    const(Level)* level = &floor.level();
    ulong hash = corner.probeHash(SitePart.vertex) ^ corner.probeHash(SitePart.face);
    double chance = roll(hash, PLAN_SALT + index);
    ulong face = corner.probeHash(SitePart.face);
    MaybeIndex!Rare rare = rareOn(face, floor, index, halls);
    if (level.isMaze()) {
        return Laid.of(Plan.maze);
    } else if (q.isLobby() && (floor.isTop() || q.hasShaft() || q.hasWell())) {
        return Laid.of(Plan.lobby);
    } else if (stair.isOn(floor.layer)) {
        return Laid.of(Plan.rooms);
    } else if (rare.exists) {
        return Laid.of(planOfRare(level.rare.items[rare.value].plan));
    } else if (isSolid(face, *level, index)) {
        return Laid.of(Plan.solid);
    } else if (chance < level.rings) {
        return Laid.of(Plan.rings);
    } else if (!halls.has(Axis.x) && !halls.has(Axis.y) && chance < level.rings + level.chapel) {
        return Laid.of(Plan.chapel);
    } else {
        return openPlan(roll(hash, FORM_SALT + index), floor, biome);
    }
}

void quarter(Turtle corner, ref const Root root, ref const(Biome)*[MOST_LEVELS] biomes, ref const Besides besides) {
    ulong vertex = corner.probeHash(SitePart.vertex);
    ulong face = corner.probeHash(SitePart.face);
    QuarterKind kind = QuarterKind.plain;
    if (vertex == root.vertex && root.shaft == Shaft.open) {
        kind = QuarterKind.lobbyWithShaft;
    } else {
        bool lobby = vertex == root.vertex;
        if (!lobby) {
            lobby = corner.probeRising().exists;
        }
        if (lobby) {
            kind = QuarterKind.lobby;
        } else {
            bool port = corner.probePort();
            if (port) {
                kind = QuarterKind.lobbyWithWell;
            }
        }
    }
    WellDoor door = WellDoor.elsewhere;
    if (kind == QuarterKind.lobbyWithWell && face == ownerAround(corner).probeHash(SitePart.face)) {
        door = WellDoor.here;
    }
    Quarter q = Quarter(upright(corner), kind, door);
    Owns owns;
    owns.put(Side.xHigh, vertex > corner.forward(1).probeHash(SitePart.vertex));
    owns.put(Side.yHigh, vertex > corner.right().forward(1).probeHash(SitePart.vertex));
    Halls[MOST_LEVELS] halls;
    foreach (index; 0 .. floorCount()) {
        bool hallX = probeHall(corner.right(), root, floors[index].level, index + 1);
        bool hallY = probeHall(corner, root, floors[index].level, index + 1);
        halls[index].put(Axis.x, hallX);
        halls[index].put(Axis.y, hallY);
    }
    Line[4] lines = linesOf(corner);
    Stair stair = stairOf(corner, root, halls, q);
    bool forced = probeForcedStair(corner, root);
    if (stair.isPresent() && !forced && (isSolid(face, floors[stair.upper.value].level, stair.upper.value + 1) || isSolid(face, floors[stair.lower].level, stair.lower + 1))) {
        stair = Stair.init;
    }
    Frame[MOST_LEVELS] frames;
    foreach_reverse (index; 0 .. floorCount()) {
        Floor floor = floors[index];
        const(Level)* level = &floor.level();
        Doors[4] doors;
        foreach (side; SIDES) {
            Passage passage = Passage.open;
            if (isSolid(face, *level, index + 1) || isSolid(lines[side].beyond, *level, index + 1)) {
                passage = Passage.closed;
            }
            doors[side] = lineDoors(lines[side].hash, index + 1, *level, passage);
        }
        Laid plan = planOf(corner, q, stair, floor, index + 1, halls[index], *biomes[index]);
        frames[index] = frameOf(q, halls[index], floor, biomes[index], stair, plan, owns);
        Owns borders;
        foreach (side; OUTER_SIDES) {
            borders.put(side, isBorder(besides, lines[side].beyond, index, biomes[index]));
        }
        paintFloor(frames[index], doors, plan.plan, borders);
    }
    if (stair.isPresent()) {
        Routing routing = Routing.unrouted;
        if (root.routing == Routing.routed && forced) {
            routing = Routing.routed;
        }
        stairs(frames[stair.lower], frames[stair.upper.value], stair, routing);
    }
}

void tile(const(Api)* api, Site site, ref const Risen risen, ref const Root root) {
    tileAt(Turtle(api, site), root);
}

struct Neighborhood {
    ulong[BALL_FACES] faces;
}

struct Mood {
    double[FIELD_COUNT] at = 0;
    ulong key;
}

void ringInto(Turtle face, ulong[] into) {
    into[0] = face.probeHash(SitePart.face);
    uint index = 1;
    foreach (corner; cornersOf(face)) {
        into[index] = corner.left().probeHash(SitePart.face);
        index += 1;
    }
}

Neighborhood neighborhoodOf(Turtle face) {
    Neighborhood near;
    ringInto(face, near.faces[0 .. RING_FACES]);
    uint ring = 1;
    foreach (corner; cornersOf(face)) {
        ringInto(corner.left(), near.faces[ring * RING_FACES .. (ring + 1) * RING_FACES]);
        ring += 1;
    }
    return near;
}

Mood moodOf(ref const Neighborhood near) {
    Mood mood;
    foreach (field; 0 .. FIELD_COUNT) {
        uint count = BALL_FACES;
        if (FIELD_REACH[field] == Reach.ring) {
            count = RING_FACES;
        }
        ulong best = 0;
        ulong winner = near.faces[0];
        foreach (hash; near.faces[0 .. count]) {
            ulong salted = mixed(hash, FIELD_SALTS[field]);
            if (salted > best) {
                best = salted;
                winner = hash;
            }
        }
        mood.at[field] = (mixed(winner, FIELD_SALTS[field] + 1) % FIELD_STEPS) / cast(double) FIELD_STEPS;
        mood.key ^= mixed(winner, FIELD_SALTS[field] + 2);
    }
    return mood;
}

double distanceTo(ref const Biome biome, ref const Mood mood) {
    double far = 0;
    foreach (field; 0 .. FIELD_COUNT) {
        Bounds bounds = biome.boundsOf(cast(Field) field);
        double value = mood.at[field];
        if (value < bounds.above) {
            far += (bounds.above - value) * (bounds.above - value);
        } else if (!(value < bounds.below)) {
            double over = value - bounds.below + 1.0 / FIELD_STEPS;
            far += over * over;
        }
    }
    return far;
}

const(Biome)* biomeIn(ref const Mood mood, size_t index) {
    const(Biome)[] biomes = floors[index].level().biomes.slice();
    double[MOST_BIOMES] far;
    double least = double.infinity;
    foreach (at, ref biome; biomes) {
        far[at] = distanceTo(biome, mood);
        least = lowerOf(least, far[at]);
    }
    double weights = 0;
    foreach (at, ref biome; biomes) {
        if (far[at] == least) {
            weights += biome.weight;
        }
    }
    double roll = (mixed(mood.key, PICK_SALT + index) % FIELD_STEPS) / cast(double) FIELD_STEPS * weights;
    size_t picked = 0;
    foreach (at, ref biome; biomes) {
        if (far[at] == least) {
            if (!(roll < 0)) {
                picked = at;
            }
            roll -= biome.weight;
        }
    }
    return &biomes[picked];
}

double mostWellShare() {
    const(Level)* level = &floors[floorCount() - 1].level();
    double most = 0;
    foreach (ref biome; level.biomes.items[0 .. level.biomes.count]) {
        most = higherOf(most, biome.well);
    }
    return most;
}

bool portAt(const(Api)* api, Site vertex, double rolled, const(void)* data) {
    Neighborhood near = neighborhoodOf(ownerAround(Turtle(api, vertex)));
    Mood mood = moodOf(near);
    return rolled < biomeIn(mood, floorCount() - 1).well;
}

struct Beside {
    ulong face;
    const(Biome)*[MOST_LEVELS] biomes;
}

alias Besides = Beside[FACE_CORNERS];

Beside besideOf(Turtle other) {
    Neighborhood near = neighborhoodOf(other);
    Mood mood = moodOf(near);
    Beside beside;
    beside.face = near.faces[0];
    foreach (index; 0 .. floorCount()) {
        beside.biomes[index] = biomeIn(mood, index);
    }
    return beside;
}

bool isBorder(ref const Besides besides, ulong face, size_t index, const(Biome)* own) {
    uint at = 0;
    while (at < FACE_CORNERS && besides[at].face != face) {
        at += 1;
    }
    return at < FACE_CORNERS && besides[at].biomes[index] !is own;
}

void tileAt(Turtle face, ref const Root root) {
    Turtle[FACE_CORNERS] corners = cornersOf(face);
    Neighborhood near = neighborhoodOf(face);
    Mood mood = moodOf(near);
    const(Biome)*[MOST_LEVELS] biomes;
    foreach (index; 0 .. floorCount()) {
        biomes[index] = biomeIn(mood, index);
    }
    Besides besides;
    foreach (index, corner; corners) {
        besides[index] = besideOf(corner.left());
    }
    foreach (corner; corners) {
        quarter(corner, root, biomes, besides);
    }
}
