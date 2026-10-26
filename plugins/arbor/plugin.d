module plugins.arbor.plugin;

import core.stdc.math : pow;
import plugins.api.api : Api, ENTRY, Material, Registry, Rhythm, Risen, Site, SitePart, Turn;
import plugins.turtle.turtle : Tread, Turtle, boxOf, cornersOf, floorMod, higherOf, middle, roll, treadAround, upright;

enum int TRUNK = 4;
enum int RING = 4;
enum int SIDE_TREADS = 4;
enum int TREADS = 4 * (SIDE_TREADS + 1);
enum int LIMB_START = TRUNK + RING;
enum int THICKEST = 4;
enum int FLARE = 2;
enum double STRAIGHT_ODDS = 0.8;
enum double UPWARD_ODDS = 0.7;
enum double SIDEWAYS_ODDS = 0.5;
enum double TAPER = 0.85;
enum double STEEP = 45;
enum double DOWNWARD = -20;
enum double SECOND_LIMB_ODDS = 0.5;
enum double LEAF_ODDS = 0.7;
enum int LEAFY_GENERATION = 2;
enum uint MOST_SIDE_BRANCHES = 2;
enum ulong STRAIGHT_SALT = 0x4F1BBCDD;
enum ulong SIDE_SALT = 0x6A09E667;
enum ulong LEAF_SALT = 0x510E527F;
enum ulong LIMB_SALT = 0x3C6EF372;
enum Material BARK = Material.oakWood;
enum Material STEP = Material.woodPlanks;
immutable Material[4] LEAVES = [Material.oakLeaves, Material.oakLeaves, Material.mapleLeaves, Material.cherryLeaves];
immutable Turn[4] SIDES = [Turn.pitchUp, Turn.left, Turn.pitchDown, Turn.right];
enum int ROUTE_TREADS = TREADS;
immutable float[3] SPAWN = [-12, 0, 0];

struct Branch {
    int generation;
    int start;
}

struct Trunk {
    int age;
}

int widthOf(int generation) {
    return higherOf(1, THICKEST - generation);
}

void leaves(Turtle site, int tip, ulong hash) {
    Material leaf = LEAVES[cast(size_t)(roll(hash, LEAF_SALT) * LEAVES.length)];
    site.fill(leaf, boxOf([-5, 4], [-3, 2], [tip - 4, tip + 3]));
    site.fill(leaf, boxOf([-3, 2], [-5, 4], [tip - 4, tip + 3]));
    site.fill(leaf, boxOf([-3, 2], [-3, 2], [tip - 6, tip + 5]));
}

bool grow(Turtle child, Branch data) {
    Turtle tip = child.forward(1);
    if (tip.isClaimed(SitePart.vertex)) {
        return false;
    } else {
        bool isPlaced = child.place(&branch, &data, Branch.sizeof);
        if (isPlaced) {
            tip.claim(SitePart.vertex);
        }
        return isPlaced;
    }
}

void branch(const(Api)* api, Site at, const(void)* data) {
    Turtle site = Turtle(api, at);
    Branch own = *cast(const(Branch)*) data;
    int width = widthOf(own.generation);
    int length = site.edgeCells();
    site.paint(BARK, boxOf([-width, width - 1], [-width, width - 1], [own.start, length - 1]));
    Turtle tip = site.forward(1);
    double odds = pow(TAPER, own.generation);
    Branch next = Branch(own.generation + 1, 0);
    uint grown = 0;
    if (tip.pen().rise() > DOWNWARD && roll(tip.hash(SitePart.edge), STRAIGHT_SALT) < STRAIGHT_ODDS && grow(tip, next)) {
        grown += 1;
    }
    uint sides = 0;
    foreach (turn; SIDES) {
        Turtle side = tip.turned(turn);
        double rise = side.pen().rise();
        double chance = SIDEWAYS_ODDS * odds;
        if (rise > STEEP) {
            chance = UPWARD_ODDS * odds;
        }
        if (sides < MOST_SIDE_BRANCHES && rise > DOWNWARD && roll(side.hash(SitePart.edge), SIDE_SALT) < chance && grow(side, next)) {
            sides += 1;
        }
    }
    ulong vertex = tip.hash(SitePart.vertex);
    if (grown + sides == 0 || (own.generation >= LEAFY_GENERATION && roll(vertex, LEAF_SALT) < LEAF_ODDS)) {
        leaves(site, length, vertex);
    }
}

Turn limbSide(int height) {
    return SIDES[floorMod(height - 1, TREADS) / (SIDE_TREADS + 1)];
}

void stairSegment(Turtle tower, int age) {
    int length = tower.edgeCells();
    foreach (index; 0 .. TREADS) {
        Tread tread = treadAround(TRUNK, RING, SIDE_TREADS, index);
        tower.paint(STEP, boxOf(tread.x, tread.y, [0, length - 1]), Rhythm(TREADS, floorMod(index - 1 - age * length, TREADS), 2));
    }
}

void trunk(const(Api)* api, Site at, const(void)* data) {
    Turtle tower = Turtle(api, at);
    int age = (*cast(const(Trunk)*) data).age;
    int length = tower.edgeCells();
    tower.paint(BARK, boxOf([-TRUNK, TRUNK - 1], [-TRUNK, TRUNK - 1], [0, length - 1]));
    if (age == 0) {
        tower.paint(BARK, boxOf([-TRUNK - FLARE, TRUNK + FLARE - 1], [-TRUNK - FLARE, TRUNK + FLARE - 1], [-FLARE, 0]));
    }
    stairSegment(tower, age);
    Turtle top = tower.forward(1);
    top.claim(SitePart.vertex);
    Trunk higher = Trunk(age + 1);
    if (!top.place(&trunk, &higher, Trunk.sizeof)) {
        tower.fail("the trunk's next segment is behind the tree");
    }
    Branch limb = Branch(1, LIMB_START);
    int vertexHeight = (age + 1) * length;
    Turn reachable = limbSide(vertexHeight + widthOf(limb.generation));
    grow(top.turned(reachable), limb);
    if (roll(top.hash(SitePart.vertex), LIMB_SALT) < SECOND_LIMB_ODDS) {
        foreach (turn; SIDES) {
            if (turn != reachable && roll(top.turned(turn).hash(SitePart.edge), LIMB_SALT) < SECOND_LIMB_ODDS / 2) {
                grow(top.turned(turn), limb);
            }
        }
    }
}

void route(Turtle tower) {
    tower.stop(TRUNK + RING + 1.5f, middle(treadAround(TRUNK, RING, SIDE_TREADS, 0).y), 0);
    foreach (index; 0 .. ROUTE_TREADS) {
        Tread tread = treadAround(TRUNK, RING, SIDE_TREADS, index);
        tower.stop(middle(tread.x), middle(tread.y), index + 1);
    }
}

void lawn(const(Api)* api, Site face, const(Risen)* risen, const(void)* data) {
    foreach (corner; cornersOf(Turtle(api, face))) {
        upright(corner).paint(Material.grass, boxOf([0, corner.column().high], [0, corner.column().high], [-1, -1]));
    }
}

void world(const(Api)* api, Site at, const(void)* data) {
    Turtle tower = upright(Turtle(api, at));
    Trunk first = Trunk(0);
    tower.claim(SitePart.vertex);
    if (!tower.place(&trunk, &first, Trunk.sizeof)) {
        tower.fail("the trunk cannot be placed at the root");
    }
    route(tower);
    api.tile(api, &lawn, null, 0);
    tower.entrance(SPAWN[0], SPAWN[1], SPAWN[2]);
}

pragma(mangle, ENTRY) void plugin(const(Registry)* registry) {
    registry.add(registry, "arbor", &world);
}
