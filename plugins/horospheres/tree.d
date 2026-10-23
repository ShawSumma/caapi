module plugins.horospheres.tree;

import core.stdc.math : ceil, exp;
import plugins.api.api : Material;
import plugins.turtle.turtle : Drawing, Turtle, clamped, higherOf;

enum Material BARK = Material.oakWood;
enum Material LEAVES = Material.oakLeaves;
enum double GOLDEN_ANGLE = 137.5;
enum double STEP = 3;
enum double THINNEST = 0.7;

enum double TRUNK_SINK = 12;
enum double TRUNK_RADIUS = 4;
enum double TRUNK_FLARE = 4;
enum double TRUNK_FLARE_HEIGHT = 4;

enum uint ROOT_COUNT = 7;
enum double ROOT_HEIGHT = 3;
enum double ROOT_LENGTH = 22;
enum double ROOT_RADIUS = 3;
enum double ROOT_TIP = 1;
enum double ROOT_DIP = 20;
enum double ROOT_DROOP = 5;
enum double ROOT_WANDER = 10;

enum uint SEGMENT_LIMBS = 4;
enum double BARE_SHARE = 0.4;
enum double LOWEST_LIMB_ANGLE = 85;
enum double HIGHEST_LIMB_ANGLE = 45;
enum double LIMB_SHARE = 0.5;
enum double LIMB_WIDTH = 0.6;

enum double SPREAD = 10;
enum double LATER_SHORTER = 0.5;
enum double LEAF_START = 0.4;
immutable double[2] TWIG_LEAVES = [3, 4];
immutable double[2] TIP_LEAVES = [3.5, 5];
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

Drawing wandered(Drawing pen, double degrees) {
    return pen.turn(pen.between(-degrees, degrees), pen.between(-degrees, degrees));
}

Drawing steered(Drawing pen, double elevation, double rate) {
    return pen.lift(clamped(elevation - pen.rise(), -rate, rate));
}

void branch(Drawing start, double length, double radius, size_t order) {
    Order shape = ORDERS[order];
    Drawing pen = start;
    uint steps = cast(uint) higherOf(1.0, ceil(length / STEP));
    double step = length / steps;
    double tip = higherOf(THINNEST, radius * shape.tip);
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
            Drawing fork = pen.roll(roll + (child + 1) * GOLDEN_ANGLE).turn(0, pen.between(shape.angle - SPREAD, shape.angle + SPREAD));
            double reach = length * shape.length * (1 - LATER_SHORTER * places[child]);
            branch(fork, reach, higherOf(THINNEST, to * shape.width), order + 1);
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
    return TRUNK_RADIUS + TRUNK_FLARE * exp(-higherOf(0.0, height) / TRUNK_FLARE_HEIGHT);
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

void segment(Turtle base, int index) {
    double edge = base.edgeCells();
    double start = 0;
    if (index == 0) {
        start = -TRUNK_SINK;
    }
    Drawing pen = base.pen().forward(start);
    uint steps = cast(uint) ceil((edge - start) / STEP);
    double step = (edge - start) / steps;
    double roll = pen.between(0, 360);
    uint limb = 0;
    foreach (stepIndex; 0 .. steps) {
        double height = start + stepIndex * step;
        if (index == 0 && height <= ROOT_HEIGHT && height + step > ROOT_HEIGHT) {
            roots(pen);
        }
        double low = index * edge + height;
        pen = pen.limb(BARK, step, trunkRadius(low), trunkRadius(low + step));
        while (limb < SEGMENT_LIMBS && (limb + 1.0) / (SEGMENT_LIMBS + 1) * edge <= height + step) {
            double along = (limb + 1.0) / (SEGMENT_LIMBS + 1);
            if (index > 0 || along >= BARE_SHARE) {
                double angle = LOWEST_LIMB_ANGLE + (HIGHEST_LIMB_ANGLE - LOWEST_LIMB_ANGLE) * pen.random();
                Drawing fork = pen.roll(roll + (limb + 1) * GOLDEN_ANGLE).turn(0, pen.between(angle - SPREAD, angle + SPREAD));
                branch(fork, LIMB_SHARE * edge * (1 - LATER_SHORTER * pen.random()), trunkRadius(low + step) * LIMB_WIDTH, 0);
            }
            limb += 1;
        }
    }
}
