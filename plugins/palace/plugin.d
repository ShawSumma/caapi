module plugins.palace.plugin;

import plugins.api.api : Api, Box, ENTRY, Material, Registry, Risen, Site, SitePart, Turn;
import plugins.turtle.turtle : Turtle, boxOf, cornersOf, roll, upright;

enum size_t MOST_FACES = 16;
enum int FLOOR = -11;
enum int CEILING = 10;
enum int ROOF = 11;
enum int GROUND = 0;
enum int DOOR_TOP = 3;
enum int LANDING = 4;
enum int TREADS = 10;
enum int TREAD_DEPTH = 2;
enum int[2] STAIR_Y = [1, 6];
enum int[2] DOOR_X = [2, 3];
enum int[2] WINDOW_Z = [2, 7];
enum int WINDOW_EVERY = 4;
enum int[2] LAMP_Z = [6, 8];
enum int LAMP = 6;
enum int BASIN = 8;
enum int JET_TOP = -6;
enum double STAIR_ODDS = 0.3;
enum ulong STAIR_SALT = 0x2545F491;
enum Material STONE = Material.limestone;
enum Material FLOOR_STONE = Material.marble;
enum Material TREAD = Material.whiteBrick;

struct Footprint {
    ulong[MOST_FACES] hashes;
    Turtle[MOST_FACES] faces;
    uint count;

    bool contains(ulong hash) const {
        uint index = 0;
        while (index < count && hashes[index] != hash) {
            index += 1;
        }
        return index < count;
    }

    void add(Turtle face) {
        ulong hash = face.hash(SitePart.face);
        if (!contains(hash)) {
            hashes[count] = hash;
            faces[count] = face;
            count += 1;
        }
    }
}

struct Lawn {
    ulong[MOST_FACES] hashes;
    uint count;
}

Footprint footprintOf(Turtle root) {
    Footprint footprint;
    footprint.add(root);
    foreach (corner; cornersOf(root)) {
        footprint.add(corner.right());
        footprint.add(corner.right().right());
        footprint.add(corner.left());
    }
    return footprint;
}

bool isExterior(ref const Footprint footprint, Turtle across) {
    return !footprint.contains(across.hash(SitePart.face));
}

void outerWall(Turtle tower, bool isAlongX) {
    int far = tower.column().high;
    tower.paint(STONE, line(isAlongX, [0, far], [FLOOR - 1, ROOF]));
    for (int along = 2; along < far; along += WINDOW_EVERY) {
        tower.paint(Material.glass, line(isAlongX, [along, along + 1], WINDOW_Z));
    }
}

Box line(bool isAlongX, int[2] span, int[2] z) {
    if (isAlongX) {
        return boxOf(span, [0, 0], z);
    } else {
        return boxOf([0, 0], span, z);
    }
}

void hall(Turtle corner, ref const Footprint footprint, bool isCentre) {
    Turtle tower = upright(corner);
    int far = tower.column().high;
    int[2] whole = [0, far];
    tower.paint(Material.none, boxOf(whole, whole, [FLOOR + 1, CEILING - 1]));
    tower.paint(FLOOR_STONE, boxOf(whole, whole, [FLOOR - 1, FLOOR]));
    tower.paint(Material.plaster, boxOf(whole, whole, [CEILING, CEILING]));
    tower.paint(STONE, boxOf(whole, whole, [ROOF, ROOF]));
    tower.paint(FLOOR_STONE, boxOf([0, 1], [0, 1], [FLOOR, CEILING]));
    tower.paint(Material.steel, boxOf([LAMP, LAMP], [LAMP, LAMP], [LAMP_Z[1] + 1, CEILING - 1]));
    tower.paint(Material.lightPanel, boxOf([LAMP, LAMP], [LAMP, LAMP], LAMP_Z));
    if (isExterior(footprint, corner.left())) {
        outerWall(tower, true);
    }
    if (isExterior(footprint, corner.right())) {
        outerWall(tower, false);
    }
    if (isCentre) {
        tower.paint(Material.redCarpet, boxOf([2, BASIN - 1], [2, BASIN - 1], [FLOOR, FLOOR]));
        tower.paint(FLOOR_STONE, boxOf([BASIN, far], [BASIN, far], [FLOOR + 1, FLOOR + 1]));
        tower.paint(Material.water, boxOf([BASIN + 1, far], [BASIN + 1, far], [FLOOR + 1, FLOOR + 1]));
        tower.paint(Material.water, boxOf([far, far], [far, far], [FLOOR + 2, JET_TOP]));
    }
}

struct Run {
    Turtle near;
    Turtle far;
}

Turtle frameAt(ref const Run run, int cell) {
    if (cell <= run.near.column().high) {
        return run.near;
    } else {
        return run.far;
    }
}

int alongIn(ref const Run run, int cell) {
    int span = run.near.column().high + 1;
    if (cell < span) {
        return cell;
    } else {
        return cell - 2 * span;
    }
}

void grandStair(ref const Run run, bool isRouted) {
    run.near.paint(Material.none, boxOf(DOOR_X, [0, 0], [GROUND, GROUND + DOOR_TOP]));
    run.near.paint(TREAD, boxOf([0, LANDING - 1], STAIR_Y, [FLOOR, GROUND - 1]));
    foreach (step; 1 .. TREADS) {
        foreach (offset; 0 .. TREAD_DEPTH) {
            int cell = LANDING + (step - 1) * TREAD_DEPTH + offset;
            int along = alongIn(run, cell);
            frameAt(run, cell).paint(TREAD, boxOf([along, along], STAIR_Y, [FLOOR, GROUND - step - 1]));
        }
    }
    if (isRouted) {
        float lane = (STAIR_Y[0] + STAIR_Y[1] + 1) / 2.0f;
        int floorCell = LANDING + (TREADS - 1) * TREAD_DEPTH;
        run.far.stop(alongIn(run, floorCell) + 0.5f, STAIR_Y[1] + 3.5f, FLOOR + 1);
        run.far.stop(alongIn(run, floorCell) + 0.5f, lane, FLOOR + 1);
        foreach_reverse (step; 1 .. TREADS) {
            int cell = LANDING + (step - 1) * TREAD_DEPTH + 1;
            frameAt(run, cell).stop(alongIn(run, cell), lane, GROUND - step);
        }
        float door = (DOOR_X[0] + DOOR_X[1] + 1) / 2.0f;
        run.near.stop(door, lane, GROUND);
        run.near.stop(door, 0.5f, GROUND);
        run.near.stop(door, -2.5f, GROUND);
    }
}

void lawn(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    Turtle face = Turtle(api, site);
    const(Lawn)* lawn = cast(const(Lawn)*) data;
    ulong hash = face.hash(SitePart.face);
    uint index = 0;
    while (index < lawn.count && lawn.hashes[index] != hash) {
        index += 1;
    }
    if (index == lawn.count) {
        foreach (corner; cornersOf(face)) {
            int far = corner.column().high;
            upright(corner).paint(Material.grass, boxOf([0, far], [0, far], [-1, -1]));
        }
    }
}

void world(const(Api)* api, Site site, const(void)* data) {
    Turtle root = Turtle(api, site);
    Footprint footprint = footprintOf(root);
    Lawn lawnData = Lawn(footprint.hashes, footprint.count);
    bool hasEntrance = false;
    foreach (face; footprint.faces[0 .. footprint.count]) {
        bool isCentre = face.hash(SitePart.face) == footprint.hashes[0];
        foreach (corner; cornersOf(face)) {
            hall(corner, footprint, isCentre);
        }
    }
    foreach (face; footprint.faces[0 .. footprint.count]) {
        foreach (corner; cornersOf(face)) {
            bool isFirst = !hasEntrance;
            if (isExterior(footprint, corner.left()) && (isFirst || roll(corner.hash(SitePart.edge), STAIR_SALT) < STAIR_ODDS)) {
                Run run = Run(upright(corner), upright(corner.forward(1)));
                grandStair(run, isFirst);
                if (isFirst) {
                    run.near.turned(Turn.rollLeft).entrance(0, -(DOOR_X[0] + DOOR_X[1] + 1) / 2.0f, GROUND);
                    hasEntrance = true;
                }
            }
        }
    }
    api.tile(api, &lawn, &lawnData, Lawn.sizeof);
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "palace", &world);
}
