module plugins.lattice.plugin;

import core.stdc.math : fabs;
import plugins.api.api : Api, ENTRY, HorosphereForm, Look, Material, NO_KIND, Registry, Rhythm, Risen, Site, SitePart, Tint, Turn;
import plugins.turtle.turtle : Tread, Turtle, boxOf, lowerOf, roll, treadAround, upright;

immutable Look LOOK = Look("lattice", [0.05f, 0.06f, 0.1f], Tint.fog);

enum int BEAM = 1;
enum int PLATFORM = 6;
enum int ROOT_PLATFORM = 10;
enum int POLE_RING = 3;
enum int POLE_TREADS = 4 * 2;
enum double FOG = 3.5;
enum double PLATFORM_ODDS = 0.12;
enum double STAIR_ODDS = 0.2;
enum double LANTERN_ODDS = 0.4;
enum double TREE_ODDS = 0.7;
enum double HUT_ODDS = 0.9;
enum ulong PLATFORM_SALT = 0x2F4A7C15;
enum ulong STAIR_SALT = 0x6B43A9B5;
enum ulong DECOR_SALT = 0x5BE0CD19;
enum ulong FLOOR_SALT = 0x1F83D9AB;
enum Material POLE = Material.steel;
enum Material GIRDER = Material.concrete;
enum Material JOINT = Material.basalt;
enum Material STEP = Material.woodPlanks;
immutable Material[3] FLOORS = [Material.woodPlanks, Material.marble, Material.greyBrick];
immutable float[3] SPAWN = [21, 2, -3];

enum Axis : ubyte {
    x,
    y,
    z,
}

immutable Axis[2] CROSS = [Axis.x, Axis.y];

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
            return frame.pen().turn(90, 0).rise();
        case Axis.y:
            return frame.pen().turn(0, 90).rise();
        case Axis.z:
            return frame.pen().rise();
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

bool isStair(ulong edge) {
    return roll(edge, STAIR_SALT) < STAIR_ODDS;
}

bool isPlatform(ref const End end, ref const Root root) {
    return end.vertex == root.vertex || isStair(along(end.frame, end.vertical, 1).hash(SitePart.edge)) || isStair(along(end.frame, end.vertical, -1).hash(SitePart.edge)) || roll(end.vertex, PLATFORM_SALT) < PLATFORM_ODDS;
}

bool isUpward(ref const End end) {
    return riseOf(end.frame, Axis.z) * end.sign > 0;
}

int[2] near(int sign, int from, int to) {
    if (sign > 0) {
        return [from, to];
    } else {
        return [-to - 1, -from - 1];
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
    return lowerOf(along(frame, axis, 1).hash(SitePart.edge), along(frame, axis, -1).hash(SitePart.edge));
}

bool isDesignated(ref const End end) {
    return lineHash(end.frame, Axis.z) < lineHash(end.frame, acrossOf(end.vertical));
}

void platform(ref const End end, ref const Root root) {
    int reach = PLATFORM;
    if (end.vertex == root.vertex) {
        reach = ROOT_PLATFORM;
    }
    Material floor = FLOORS[cast(size_t)(roll(end.vertex, FLOOR_SALT) * FLOORS.length)];
    int[2] wide = [-reach, reach - 1];
    int[2] thin = [-BEAM, BEAM - 1];
    int[2] z = near(end.sign, BEAM, reach - 1);
    if (end.vertical == Axis.y) {
        end.frame.paint(floor, boxOf(wide, thin, z));
    } else {
        end.frame.paint(floor, boxOf(thin, wide, z));
    }
}

void decorate(ref const End end) {
    double choice = roll(end.vertex, DECOR_SALT);
    Turtle frame = end.frame;
    int sign = end.sign;
    if (choice < LANTERN_ODDS) {
        frame.paint(Material.lightPanel, boxOf([-2, 1], [-2, 1], near(sign, 3, 4)));
    } else if (choice < TREE_ODDS) {
        frame.fill(Material.oakLeaves, boxOf([-4, 3], [-4, 3], near(sign, 3, 6)));
        frame.fill(Material.oakLeaves, boxOf([-2, 1], [-2, 1], near(sign, 7, 8)));
    } else if (choice < HUT_ODDS) {
        int[2] walls = near(sign, 1, 5);
        frame.paint(Material.woodPlanks, boxOf([-5, 4], [-5, -5], walls));
        frame.paint(Material.woodPlanks, boxOf([-5, 4], [4, 4], walls));
        frame.paint(Material.woodPlanks, boxOf([-5, -5], [-4, 3], walls));
        frame.paint(Material.woodPlanks, boxOf([4, 4], [-4, 3], walls));
        frame.paint(Material.none, boxOf([4, 4], [-1, 0], near(sign, 1, 3)));
        frame.paint(Material.redSandstone, boxOf([-6, 5], [-6, 5], near(sign, 6, 6)));
    }
}

void spiral(Turtle frame, int length) {
    foreach (index; 0 .. POLE_TREADS) {
        Tread tread = treadAround(BEAM, POLE_RING, 1, index);
        frame.paint(STEP, boxOf(tread.x, tread.y, [1, length - 2]), Rhythm(POLE_TREADS, index, 1));
    }
}

End endAt(Turtle frame, int sign) {
    return End(frame, verticalOf(frame), frame.hash(SitePart.vertex), sign);
}

void edge(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    Turtle start = Turtle(api, site);
    Root root = *cast(const(Root)*) data;
    int length = start.edgeCells();
    int[2] cross = [-BEAM, BEAM - 1];
    End[2] ends = [endAt(start, 1), endAt(start.forward(1), -1)];
    foreach (end; ends) {
        if (isPlatform(end, root) && end.vertical == Axis.z && isUpward(end)) {
            decorate(end);
        }
    }
    Material beam = GIRDER;
    if (ends[0].vertical == Axis.z) {
        beam = POLE;
    }
    start.paint(beam, boxOf(cross, cross, [1, length - 2]));
    start.paint(JOINT, boxOf(cross, cross, [0, 0]));
    start.paint(JOINT, boxOf(cross, cross, [length - 1, length - 1]));
    if (ends[0].vertical == Axis.z && isStair(start.hash(SitePart.edge))) {
        spiral(start, length);
    }
    foreach (end; ends) {
        if (isPlatform(end, root) && end.vertical != Axis.z && isDesignated(end)) {
            platform(end, root);
        }
    }
}

void world(const(Api)* api, Site at, const(void)* data) {
    Turtle root = Turtle(api, at);
    Root lattice = Root(root.hash(SitePart.vertex));
    uint kind = api.horosphere(api, 0, HorosphereForm.bare, 0, null, null, 0);
    api.rooted(api, kind);
    api.invertGravity(api);
    api.fog(api, FOG);
    api.look(api, NO_KIND, &LOOK);
    api.tileEdges(api, &edge, &lattice, Root.sizeof);
    upright(root).entrance(SPAWN[0], SPAWN[1], SPAWN[2]);
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "lattice", &world);
}
