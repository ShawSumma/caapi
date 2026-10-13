module plugins.bigtree.plugin;

import core.stdc.math : ceil, exp;
import plugins.api.api : Api, ENTRY, Material, Registry, Site;
import plugins.turtle.turtle : Drawing, Turtle;

enum Material BARK = Material.oakWood;
enum Material LEAVES = Material.oakLeaves;
enum double GOLDEN = 137.5;
enum double STEP = 3;
enum double THINNEST = 0.7;

enum double TRUNK_HEIGHT = 48;
enum double TRUNK_SINK = 12;
enum double TRUNK_RADIUS = 5;
enum double TRUNK_TOP = 2.5;
enum double TRUNK_FLARE = 3;
enum double TRUNK_FLARE_HEIGHT = 4;
enum double TRUNK_WANDER = 2;
enum double TRUNK_STEER = 2;
enum double UPRIGHT = 90;

enum uint ROOT_COUNT = 7;
enum double ROOT_HEIGHT = 3;
enum double ROOT_LENGTH = 22;
enum double ROOT_RADIUS = 3;
enum double ROOT_TIP = 1;
enum double ROOT_DIP = 20;
enum double ROOT_DROOP = 5;
enum double ROOT_WANDER = 10;

enum uint LIMB_COUNT = 12;
enum double LIMB_LOW = 0.3;
enum double LIMB_HIGH = 0.97;
enum double LOWEST_LIMB_ANGLE = 80;
enum double HIGHEST_LIMB_ANGLE = 25;
enum double LIMB_SPREAD = 8;
enum double LIMB_LENGTH = 36;
enum double LIMB_SHORTENING = 0.45;
enum double LIMB_WIDTH = 0.65;

enum double SPREAD = 10;
enum double LATER_SHORTER = 0.5;
enum double LEAF_START = 0.4;
immutable double[2] TWIG_LEAVES = [3, 4];
immutable double[2] TIP_LEAVES = [3.5, 5];
immutable float[3] SPAWN = [-14, 12, 0];
enum uint MOST_CHILDREN = 8;

struct Order {
    uint children;
    double first;
    double angle;
    double length;
    double width;
    double wander;
    double elevation;
    double steer;
    double tip;
}

immutable Order[4] ORDERS = [
    Order(6, 0.3, 45, 0.55, 0.6, 5, 8, 3, 0.35),
    Order(5, 0.2, 50, 0.6, 0.6, 8, 15, 4, 0.4),
    Order(4, 0.2, 55, 0.65, 0.6, 12, 20, 5, 0.5),
    Order(0, 0, 0, 0, 0, 15, 25, 5, 0.6),
];

double clampedTo(double value, double rate) {
    if (value > rate) {
        return rate;
    } else if (value < -rate) {
        return -rate;
    } else {
        return value;
    }
}

double higher(double a, double b) {
    return a > b ? a : b;
}

Drawing wandered(Drawing pen, double degrees) {
    return pen.turn(pen.between(-degrees, degrees), pen.between(-degrees, degrees));
}

Drawing steered(Drawing pen, double elevation, double rate) {
    return pen.lift(clampedTo(elevation - pen.rise(), rate));
}

void branch(Drawing start, double length, double radius, size_t order) {
    immutable Order shape = ORDERS[order];
    Drawing pen = start;
    uint steps = cast(uint) higher(1, ceil(length / STEP));
    double step = length / steps;
    double tip = higher(THINNEST, radius * shape.tip);
    double roll = pen.between(0, 360);
    double[MOST_CHILDREN] places;
    uint count = 0;
    if (order + 1 < ORDERS.length) {
        foreach (child; 0 .. shape.children) {
            double slot = (child + 1 - pen.between(0.2, 0.8)) / shape.children;
            places[child] = shape.first + (1 - shape.first) * slot;
        }
        count = shape.children;
    }
    uint child = 0;
    foreach (index; 0 .. steps) {
        double done = (index + 1.0) / steps;
        double from = radius + (tip - radius) * index / steps;
        double to = radius + (tip - radius) * done;
        pen = pen.limb(BARK, step, from, to);
        while (child < count && places[child] <= done) {
            Drawing fork = pen.roll(roll + (child + 1) * GOLDEN).turn(0, pen.between(shape.angle - SPREAD, shape.angle + SPREAD));
            double reach = length * shape.length * (1 - LATER_SHORTER * places[child]);
            branch(fork, reach, higher(THINNEST, to * shape.width), order + 1);
            child += 1;
        }
        if (order + 1 == ORDERS.length && done >= LEAF_START) {
            pen.leaves(LEAVES, pen.between(TWIG_LEAVES[0], TWIG_LEAVES[1]));
        }
        pen = steered(wandered(pen, shape.wander), shape.elevation, shape.steer);
    }
    if (order + 2 >= ORDERS.length) {
        pen.leaves(LEAVES, pen.between(TIP_LEAVES[0], TIP_LEAVES[1]));
    }
}

double trunkRadius(double height) {
    double above = higher(0, height);
    double taper = TRUNK_TOP + (TRUNK_RADIUS - TRUNK_TOP) * (1 - above / TRUNK_HEIGHT);
    return taper + TRUNK_FLARE * exp(-above / TRUNK_FLARE_HEIGHT);
}

void roots(Drawing base) {
    double turn = base.between(0, 360);
    uint steps = cast(uint) ceil(ROOT_LENGTH / STEP);
    foreach (root; 0 .. ROOT_COUNT) {
        double around = turn + (root + 1) * 360.0 / ROOT_COUNT + base.between(-ROOT_WANDER, ROOT_WANDER);
        Drawing pen = base.roll(around).turn(0, 90 + ROOT_DIP + base.between(-ROOT_WANDER, ROOT_WANDER));
        foreach (index; 0 .. steps) {
            double from = ROOT_RADIUS + (ROOT_TIP - ROOT_RADIUS) * index / steps;
            double to = ROOT_RADIUS + (ROOT_TIP - ROOT_RADIUS) * (index + 1.0) / steps;
            pen = wandered(pen.limb(BARK, STEP, from, to), ROOT_WANDER).lift(-ROOT_DROOP);
        }
    }
}

struct Limbs {
    uint next;
    double roll;

    void grow(Drawing trunk, double height, double radius) {
        bool isDue = true;
        while (next < LIMB_COUNT && isDue) {
            double share = cast(double) next / (LIMB_COUNT - 1);
            double along = LIMB_LOW + (LIMB_HIGH - LIMB_LOW) * share;
            isDue = along * TRUNK_HEIGHT <= height;
            if (isDue) {
                double angle = LOWEST_LIMB_ANGLE + (HIGHEST_LIMB_ANGLE - LOWEST_LIMB_ANGLE) * share;
                Drawing pen = trunk.roll(roll + (next + 1) * GOLDEN).turn(0, trunk.between(angle - LIMB_SPREAD, angle + LIMB_SPREAD));
                branch(pen, LIMB_LENGTH * (1 - LIMB_SHORTENING * along), radius * LIMB_WIDTH, 0);
                next += 1;
            }
        }
    }
}

void grow(Turtle site) {
    Drawing pen = site.pitchUp().pen().forward(-TRUNK_SINK);
    Limbs limbs = Limbs(0, pen.between(0, 360));
    uint steps = cast(uint) ceil((TRUNK_HEIGHT + TRUNK_SINK) / STEP);
    foreach (index; 0 .. steps) {
        double height = index * STEP - TRUNK_SINK;
        if (height == ROOT_HEIGHT) {
            roots(pen);
        }
        pen = pen.limb(BARK, STEP, trunkRadius(height), trunkRadius(height + STEP));
        limbs.grow(pen, height + STEP, trunkRadius(height + STEP));
        pen = steered(wandered(pen, TRUNK_WANDER), UPRIGHT, TRUNK_STEER);
    }
    pen.leaves(LEAVES, TIP_LEAVES[1]);
    site.entrance(SPAWN[0], SPAWN[1], SPAWN[2]);
}

void world(const(Api)* api, Site site, const(void)* data) {
    grow(Turtle(api, site));
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "bigtree", &world);
}
