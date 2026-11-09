module plugins.lattice.plugin;

import core.stdc.math : fabs;
import plugins.api.api : Api, HorosphereForm, KindId, Material, Registry, Rhythm, Risen, Site, SitePart, Span, Spot, Turn, entryOf, tagNamed;
import plugins.api.binding : List, bound, settingsOf;
import plugins.api.content : Content, FIRST_VERSION, Manifest, ON_BASE;
import plugins.turtle.turtle : Tread, Turtle, boxOf, lowerOf, roll, treadAround, upright;

enum string LOOK = "lattice:look";

enum int BEAM = 1;
enum int PLATFORM = 6;
enum int ROOT_PLATFORM = 10;
enum int POLE_RING = 3;
enum int POLE_TREADS = 4 * 2;
enum ulong PLATFORM_SALT = 0x2F4A7C15;
enum ulong STAIR_SALT = 0x6B43A9B5;
enum ulong DECOR_SALT = 0x5BE0CD19;
enum ulong FLOOR_SALT = 0x1F83D9AB;
enum size_t MOST_FLOORS = 16;
enum uint LATTICE_TAG = tagNamed("lattice:lattice");
immutable Spot SPAWN = Spot(21, 2, -3);

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
}

__gshared Materials materials;

struct Tuning {
    double fog;
    double platformOdds;
    double stairOdds;
    double lanternOdds;
    double treeOdds;
    double hutOdds;
}

__gshared Tuning tuning;

void resolve(const(Content)* content) {
    materials = content.bound!Materials("lattice:materials");
    tuning = content.settingsOf!Tuning("lattice");
}

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

bool isStair(ulong edge) {
    return roll(edge, STAIR_SALT) < tuning.stairOdds;
}

bool probePlatform(ref const End end, ref const Root root) {
    bool raised = end.vertex == root.vertex;
    if (!raised) {
        raised = isStair(along(end.frame, end.vertical, 1).probeHash(SitePart.edge));
    }
    if (!raised) {
        raised = isStair(along(end.frame, end.vertical, -1).probeHash(SitePart.edge));
    }
    return raised || roll(end.vertex, PLATFORM_SALT) < tuning.platformOdds;
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
        end.frame.paint(floor, boxOf(wide, thin, z));
    } else {
        end.frame.paint(floor, boxOf(thin, wide, z));
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

void spiral(Turtle frame, int length) {
    foreach (index; 0 .. POLE_TREADS) {
        Tread tread = treadAround(BEAM, POLE_RING, 1, index);
        frame.paint(materials.step, boxOf(tread.x, tread.y, Span(1, length - 2)), Rhythm(POLE_TREADS, index, 1));
    }
}

End endAt(Turtle frame, int sign) {
    return End(frame, verticalOf(frame), frame.probeHash(SitePart.vertex), sign);
}

void edge(const(Api)* api, Site site, const(Risen)* risen, const(void)* data) {
    Turtle start = Turtle(api, site);
    Root root = *cast(const(Root)*) data;
    int length = start.edgeCells();
    Span cross = Span(-BEAM, BEAM - 1);
    End[2] ends = [endAt(start, 1), endAt(start.forward(1), -1)];
    foreach (end; ends) {
        bool raised = probePlatform(end, root);
        if (raised && end.vertical == Axis.z) {
            bool upward = probeUpward(end);
            if (upward) {
                decorate(end);
            }
        }
    }
    Material beam = materials.girder;
    if (ends[0].vertical == Axis.z) {
        beam = materials.pole;
    }
    start.paint(beam, boxOf(cross, cross, Span(1, length - 2)));
    start.paint(materials.joint, boxOf(cross, cross, Span(0, 0)));
    start.paint(materials.joint, boxOf(cross, cross, Span(length - 1, length - 1)));
    ulong startEdge = start.probeHash(SitePart.edge);
    if (ends[0].vertical == Axis.z && isStair(startEdge)) {
        spiral(start, length);
    }
    foreach (end; ends) {
        bool raised = probePlatform(end, root);
        if (raised && end.vertical != Axis.z) {
            bool designated = probeDesignated(end);
            if (designated) {
                platform(end, root);
            }
        }
    }
}

void world(const(Api)* api, Site at, const(void)* data) {
    Turtle root = Turtle(api, at);
    Root lattice = Root(root.probeHash(SitePart.vertex));
    KindId kind = api.horosphere(api, 0, HorosphereForm.bare, LATTICE_TAG, null, null, 0);
    api.rooted(api, kind);
    api.invertGravity(api);
    api.fog(api, tuning.fog);
    api.worldLook(api, LOOK);
    api.tileEdges(api, &edge, &lattice, Root.sizeof);
    upright(root).entrance(SPAWN.x, SPAWN.y, SPAWN.z);
}

immutable Manifest MANIFEST = Manifest("lattice", FIRST_VERSION, ON_BASE[], null, &resolve, null, import("plugins/lattice/settings.conf"), import("plugins/lattice/lattice.decl"), import("plugins/lattice/lattice.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    registry.add(registry, "lattice", &world);
}
