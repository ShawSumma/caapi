module plugins.palace.palace;

import plugins.api.api : Box, Material, SitePart, Span;
import plugins.api.binding : bound;
import plugins.api.content : Content;
import plugins.turtle.turtle : Along, Rows, Turtle, boxOf, cornersOf, line, lowerOf, middle, roll, upright;

enum size_t MOST_FACES = 16;
enum int FLOOR = -11;
enum int CEILING = 10;
enum int ROOF = 11;
enum int GROUND = 0;
enum int DOOR_TOP = 3;
enum int LANDING = 4;
enum int TREADS = 10;
enum int TREAD_DEPTH = 2;
enum int SUNK_LANDING = 2;
enum Span STAIR_Y = Span(1, 6);
enum Span DOOR_X = Span(2, 3);
enum Span APRON_X = Span(1, 4);
enum int APRON_DEPTH = 6;
enum int APRON_CLEAR = 8;
enum int MERLON_EVERY = 2;
enum int MERLON = 2;
enum int DOME_RADIUS = 9;
enum Span WINDOW_Z = Span(2, 7);
enum int WINDOW_EVERY = 4;
enum Span LAMP_Z = Span(6, 8);
enum int LAMP = 6;
enum int BASIN = 8;
enum int JET_TOP = -6;
enum double STAIR_ODDS = 0.3;
enum ulong STAIR_SALT = 0x2545F491;

struct Materials {
    Material stone;
    Material floor;
    Material tread;
    Material window;
    Material ceiling;
    Material rod;
    Material lamp;
    Material carpet;
    Material water;
    Material lawn;
}

__gshared Materials materials;

void resolvePalace(const(Content)* content) {
    materials = content.bound!Materials("palace:materials");
}

struct FaceHashes {
    ulong[MOST_FACES] items;
    uint count;

    bool contains(ulong hash) const {
        uint index = 0;
        while (index < count && items[index] != hash) {
            index += 1;
        }
        return index < count;
    }
}

struct Footprint {
    FaceHashes hashes;
    Turtle[MOST_FACES] faces;

    void add(Turtle face) {
        ulong hash = face.probeHash(SitePart.face);
        if (!hashes.contains(hash)) {
            hashes.items[hashes.count] = hash;
            faces[hashes.count] = face;
            hashes.count += 1;
        }
    }

    const(Turtle)[] slice() const return {
        return faces[0 .. hashes.count];
    }
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

bool probeExterior(ref const Footprint footprint, Turtle across) {
    ulong face = across.probeHash(SitePart.face);
    return !footprint.hashes.contains(face);
}

void outerWall(Turtle tower, Along direction, int bottom) {
    int far = tower.column().high;
    tower.paint(materials.stone, line(direction, Span(0, far), Span(bottom, ROOF)));
    for (int along = 2; along < far; along += WINDOW_EVERY) {
        tower.paint(materials.window, line(direction, Span(along, along + 1), WINDOW_Z));
    }
    for (int along = 0; along <= far; along += MERLON_EVERY) {
        tower.paint(materials.stone, line(direction, Span(along, along), Span(ROOF + 1, ROOF + MERLON)));
    }
}

enum Door : ubyte {
    none,
    here,
}

immutable Along[2] WALLS = [Along.x, Along.y];

Box beside(Along wall, Span along, Span away, Span z) {
    final switch (wall) {
        case Along.x:
            return boxOf(along, away, z);
        case Along.y:
            return boxOf(away, along, z);
    }
}

void upperQuarter(Turtle corner, Door door, int land) {
    Turtle tower = upright(corner);
    int far = tower.column().high;
    Span whole = Span(0, far);
    tower.paint(Material.none, boxOf(whole, whole, Span(GROUND, CEILING - 1)));
    tower.paint(materials.ceiling, boxOf(whole, whole, Span(CEILING, CEILING)));
    tower.paint(materials.stone, boxOf(whole, whole, Span(ROOF, ROOF)));
    tower.paint(materials.floor, boxOf(Span(0, 1), Span(0, 1), Span(GROUND, CEILING)));
    tower.paint(materials.rod, boxOf(Span(LAMP, LAMP), Span(LAMP, LAMP), Span(LAMP_Z.high + 1, CEILING - 1)));
    tower.paint(materials.lamp, boxOf(Span(LAMP, LAMP), Span(LAMP, LAMP), LAMP_Z));
    foreach (wall; WALLS) {
        outerWall(tower, wall, GROUND);
    }
    dome(corner);
    final switch (door) {
        case Door.none:
            break;
        case Door.here:
            foreach (wall; WALLS) {
                tower.paint(Material.none, beside(wall, DOOR_X, Span(0, 0), Span(GROUND, GROUND + DOOR_TOP)));
                foreach (away; 1 .. APRON_DEPTH + 1) {
                    int level = GROUND + lowerOf(away - 1, land);
                    Span step = Span(-away, -away);
                    tower.paint(Material.none, beside(wall, APRON_X, step, Span(level, level + APRON_CLEAR)));
                }
            }
            break;
    }
}

void lowerQuarter(Turtle corner, Door door) {
    Turtle tower = upright(corner);
    int far = tower.column().high;
    Span whole = Span(0, far);
    tower.paint(Material.none, boxOf(whole, whole, Span(FLOOR + 1, GROUND - 1)));
    tower.paint(materials.floor, boxOf(whole, whole, Span(FLOOR - 1, FLOOR)));
    tower.paint(materials.floor, boxOf(Span(0, 1), Span(0, 1), Span(FLOOR, GROUND - 1)));
    foreach (wall; WALLS) {
        tower.paint(materials.stone, line(wall, whole, Span(FLOOR - 1, GROUND - 1)));
    }
    centrePiece(corner);
    final switch (door) {
        case Door.none:
            break;
        case Door.here:
            foreach (wall; WALLS) {
                tower.paint(materials.tread, beside(wall, Span(0, SUNK_LANDING - 1), STAIR_Y, Span(FLOOR, GROUND - 1)));
                foreach (step; 1 .. TREADS) {
                    Span cells = Span(SUNK_LANDING + step - 1, SUNK_LANDING + step - 1);
                    tower.paint(materials.tread, beside(wall, cells, STAIR_Y, Span(FLOOR, GROUND - step - 1)));
                }
                foreach (away; 1 .. APRON_DEPTH + 1) {
                    tower.paint(materials.tread, beside(wall, APRON_X, Span(-away, -away), Span(GROUND - 1, GROUND - 1)));
                }
            }
            break;
    }
}

void dome(Turtle corner) {
    Turtle tower = upright(corner);
    int far = tower.column().high;
    double centre = far + 1;
    foreach (rise; 1 .. DOME_RADIUS + 1) {
        double height = rise - 0.5;
        double reach = DOME_RADIUS * DOME_RADIUS - height * height;
        Rows rows;
        foreach (y; 0 .. far + 1) {
            foreach (x; 0 .. far + 1) {
                double across = centre - (x + 0.5);
                double along = centre - (y + 0.5);
                if (across * across + along * along < reach) {
                    rows.add(x, y);
                }
            }
        }
        tower.paintRows(materials.stone, rows, Span(ROOF + rise, ROOF + rise));
    }
    tower.paint(materials.lamp, boxOf(Span(far, far), Span(far, far), Span(ROOF + DOME_RADIUS + 1, ROOF + DOME_RADIUS + 1)));
}

void hall(Turtle corner, ref const Footprint footprint) {
    Turtle tower = upright(corner);
    int far = tower.column().high;
    Span whole = Span(0, far);
    tower.paint(Material.none, boxOf(whole, whole, Span(FLOOR + 1, CEILING - 1)));
    tower.paint(materials.floor, boxOf(whole, whole, Span(FLOOR - 1, FLOOR)));
    tower.paint(materials.ceiling, boxOf(whole, whole, Span(CEILING, CEILING)));
    tower.paint(materials.stone, boxOf(whole, whole, Span(ROOF, ROOF)));
    tower.paint(materials.floor, boxOf(Span(0, 1), Span(0, 1), Span(FLOOR, CEILING)));
    tower.paint(materials.rod, boxOf(Span(LAMP, LAMP), Span(LAMP, LAMP), Span(LAMP_Z.high + 1, CEILING - 1)));
    tower.paint(materials.lamp, boxOf(Span(LAMP, LAMP), Span(LAMP, LAMP), LAMP_Z));
    bool outerX = probeExterior(footprint, corner.left());
    if (outerX) {
        outerWall(tower, Along.x, FLOOR - 1);
    }
    bool outerY = probeExterior(footprint, corner.right());
    if (outerY) {
        outerWall(tower, Along.y, FLOOR - 1);
    }
}

void centrePiece(Turtle corner) {
    Turtle tower = upright(corner);
    int far = tower.column().high;
    tower.paint(materials.carpet, boxOf(Span(2, BASIN - 1), Span(2, BASIN - 1), Span(FLOOR, FLOOR)));
    tower.paint(materials.floor, boxOf(Span(BASIN, far), Span(BASIN, far), Span(FLOOR + 1, FLOOR + 1)));
    tower.paint(materials.water, boxOf(Span(BASIN + 1, far), Span(BASIN + 1, far), Span(FLOOR + 1, FLOOR + 1)));
    tower.paint(materials.water, boxOf(Span(far, far), Span(far, far), Span(FLOOR + 2, JET_TOP)));
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

void grandStair(ref const Run run) {
    run.near.paint(Material.none, boxOf(DOOR_X, Span(0, 0), Span(GROUND, GROUND + DOOR_TOP)));
    run.near.paint(materials.tread, boxOf(Span(0, LANDING - 1), STAIR_Y, Span(FLOOR, GROUND - 1)));
    foreach (step; 1 .. TREADS) {
        foreach (offset; 0 .. TREAD_DEPTH) {
            int cell = LANDING + (step - 1) * TREAD_DEPTH + offset;
            int along = alongIn(run, cell);
            frameAt(run, cell).paint(materials.tread, boxOf(Span(along, along), STAIR_Y, Span(FLOOR, GROUND - step - 1)));
        }
    }
}

void stairRoute(ref const Run run) {
    float lane = middle(STAIR_Y);
    int floorCell = LANDING + (TREADS - 1) * TREAD_DEPTH;
    run.far.stop(alongIn(run, floorCell) + 0.5f, STAIR_Y.high + 3.5f, FLOOR + 1);
    run.far.stop(alongIn(run, floorCell) + 0.5f, lane, FLOOR + 1);
    foreach_reverse (step; 1 .. TREADS) {
        int cell = LANDING + (step - 1) * TREAD_DEPTH + 1;
        frameAt(run, cell).stop(alongIn(run, cell), lane, GROUND - step);
    }
    float door = middle(DOOR_X);
    run.near.stop(door, lane, GROUND);
    run.near.stop(door, 0.5f, GROUND);
    run.near.stop(door, -2.5f, GROUND);
}

struct Halls {
    Run entranceRun;
    Footprint footprint;
}

Halls halls(Turtle root) {
    Footprint footprint = footprintOf(root);
    Run entranceRun;
    uint stairs = 0;
    foreach (face; footprint.slice()) {
        foreach (corner; cornersOf(face)) {
            hall(corner, footprint);
            ulong hash = face.probeHash(SitePart.face);
            if (hash == footprint.hashes.items[0]) {
                centrePiece(corner);
                dome(corner);
            }
        }
    }
    foreach (face; footprint.slice()) {
        foreach (corner; cornersOf(face)) {
            bool exterior = probeExterior(footprint, corner.left());
            if (exterior) {
                double rolled = roll(corner.probeHash(SitePart.edge), STAIR_SALT);
                if (stairs == 0 || rolled < STAIR_ODDS) {
                    Run run = Run(upright(corner), upright(corner.forward(1)));
                    grandStair(run);
                    if (stairs == 0) {
                        stairRoute(run);
                        entranceRun = run;
                    }
                    stairs += 1;
                }
            }
        }
    }
    return Halls(entranceRun, footprint);
}
