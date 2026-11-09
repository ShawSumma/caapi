module plugins.horospheres.tree;

import core.stdc.math : ceil, exp;
import plugins.api.api : Material;
import plugins.api.binding : bound;
import plugins.api.content : Content;
import plugins.turtle.turtle : Drawing, Turtle, clamped, higherOf;

struct Materials {
    Material bark;
    Material leaves;
}

__gshared Materials materials;

void resolveTree(const(Content)* content) {
    materials = content.bound!Materials("horospheres:tree");
}

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
enum double BARE_HEIGHT = 10;
enum double LOWEST_LIMB_ANGLE = 85;
enum double HIGHEST_LIMB_ANGLE = 45;
enum double LIMB_SHARE = 0.5;
enum double LIMB_WIDTH = 0.6;

enum double SPREAD = 10;
enum double LATER_SHORTER = 0.5;
enum double LEAF_START = 0.4;
immutable LeafSize TWIG_LEAVES = LeafSize(3, 4);
immutable LeafSize TIP_LEAVES = LeafSize(3.5, 5);
enum uint MOST_CHILDREN = 8;

enum double FULL_TURN = 360;
enum double QUARTER_TURN = 90;
enum double LIMB_DRIFT = 15;

enum Trunk : ubyte {
    bare,
    climbed,
}

struct LeafSize {
    double smallest;
    double largest;
}

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
    return pen.turn(pen.pickBetween(-degrees, degrees), pen.pickBetween(-degrees, degrees));
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
    double roll = pen.pickBetween(0, FULL_TURN);
    double[MOST_CHILDREN] places;
    uint count = 0;
    if (order + 1 < ORDERS.length) {
        foreach (child; 0 .. shape.children) {
            double slot = (child + 1 - pen.pickBetween(0.2, 0.8)) / shape.children;
            places[child] = shape.first + (1 - shape.first) * slot;
        }
        count = shape.children;
    }
    uint child = 0;
    foreach (index; 0 .. steps) {
        double done = (index + 1.0) / steps;
        double from = radius + (tip - radius) * index / steps;
        double to = radius + (tip - radius) * done;
        pen = pen.limb(materials.bark, step, from, to);
        while (child < count && places[child] <= done) {
            Drawing fork = pen.roll(roll + (child + 1) * GOLDEN_ANGLE).turn(0, pen.pickBetween(shape.angle - SPREAD, shape.angle + SPREAD));
            double reach = length * shape.length * (1 - LATER_SHORTER * places[child]);
            branch(fork, reach, higherOf(THINNEST, to * shape.width), order + 1);
            child += 1;
        }
        if (order + 1 == ORDERS.length && done >= LEAF_START) {
            pen.leaves(materials.leaves, pen.pickBetween(TWIG_LEAVES.smallest, TWIG_LEAVES.largest));
        }
        pen = steered(wandered(pen, shape.wander), shape.elevation, shape.steer);
    }
    if (order + 2 >= ORDERS.length) {
        pen.leaves(materials.leaves, pen.pickBetween(TIP_LEAVES.smallest, TIP_LEAVES.largest));
    }
}

double trunkRadius(double aboveGround) {
    return TRUNK_RADIUS + TRUNK_FLARE * exp(-higherOf(0.0, aboveGround) / TRUNK_FLARE_HEIGHT);
}

void roots(Drawing base) {
    double turn = base.pickBetween(0, FULL_TURN);
    uint steps = cast(uint) ceil(ROOT_LENGTH / STEP);
    foreach (root; 0 .. ROOT_COUNT) {
        double around = turn + (root + 1) * FULL_TURN / ROOT_COUNT + base.pickBetween(-ROOT_WANDER, ROOT_WANDER);
        Drawing pen = base.roll(around).turn(0, QUARTER_TURN + ROOT_DIP + base.pickBetween(-ROOT_WANDER, ROOT_WANDER));
        foreach (index; 0 .. steps) {
            double from = ROOT_RADIUS + (ROOT_TIP - ROOT_RADIUS) * index / steps;
            double to = ROOT_RADIUS + (ROOT_TIP - ROOT_RADIUS) * (index + 1.0) / steps;
            pen = wandered(pen.limb(materials.bark, STEP, from, to), ROOT_WANDER).lift(-ROOT_DROOP);
        }
    }
}

double limbRoll(Trunk trunk, Drawing pen, double firstRoll, uint limb, double along) {
    final switch (trunk) {
        case Trunk.bare:
            return firstRoll + (limb + 1) * GOLDEN_ANGLE;
        case Trunk.climbed:
            return along * FULL_TURN + FULL_TURN / 2 - QUARTER_TURN + pen.pickBetween(-LIMB_DRIFT, LIMB_DRIFT);
    }
}

void segment(Turtle base, int index, int ground, Trunk trunk) {
    double edge = base.edgeCells();
    double bottom = index * edge;
    double start = higherOf(0.0, ground - TRUNK_SINK - bottom);
    if (start < edge) {
        Drawing pen = base.openPen().forward(start);
        uint steps = cast(uint) ceil((edge - start) / STEP);
        double step = (edge - start) / steps;
        double roll = pen.pickBetween(0, FULL_TURN);
        uint limb = 0;
        foreach (stepIndex; 0 .. steps) {
            double height = start + stepIndex * step;
            double above = bottom + height - ground;
            if (above <= ROOT_HEIGHT && above + step > ROOT_HEIGHT) {
                roots(pen);
            }
            pen = pen.limb(materials.bark, step, trunkRadius(above), trunkRadius(above + step));
            while (limb < SEGMENT_LIMBS && (limb + 1.0) / (SEGMENT_LIMBS + 1) * edge <= height + step) {
                double along = (limb + 1.0) / (SEGMENT_LIMBS + 1);
                if (bottom + along * edge - ground >= BARE_HEIGHT) {
                    double angle = LOWEST_LIMB_ANGLE + (HIGHEST_LIMB_ANGLE - LOWEST_LIMB_ANGLE) * pen.rollUnit();
                    Drawing fork = pen.roll(limbRoll(trunk, pen, roll, limb, along)).turn(0, pen.pickBetween(angle - SPREAD, angle + SPREAD));
                    branch(fork, LIMB_SHARE * edge * (1 - LATER_SHORTER * pen.rollUnit()), trunkRadius(above + step) * LIMB_WIDTH, 0);
                }
                limb += 1;
            }
        }
    }
}
