module scripts.walk;

import core.stdc.math : ceil;
import base.maybe : Maybe;
import base.names : ENUM_NAMES;
import base.numbers : higherOf, lowerOf;
import base.units : Time;
import client.game : Key;
import client.script : Script, StepHook, degrees;
import common.character.controller : Footing, MovementMode;
import plugins.api.api : Material;

enum float SPEED = 0.225f;
enum float SPEED_TOLERANCE = 0.0025f;
enum float BLOCKED_SPEED = SPEED / 2;
enum float HALF_HEIGHT = 0.045f;
enum float CONTACT_SKIN = 0.0005f;
enum float STANDING_ALTITUDE = HALF_HEIGHT + CONTACT_SKIN;
enum float ALTITUDE_TOLERANCE = 0.0001f;
enum float FLY_SPEED = 0.4f;
enum float NOCLIP_SPEED = 0.6f;
enum double STRAIGHT_DOWN_DEGREES = 89;
enum float WALL_HOVER_PER_BLOCK = 0.1f;
enum float WALL_DISTANCE = 0.15f;
enum float WALL_HALF_WIDTH = 0.075f;
enum float ROW_STEP = 0.0125f;
enum float STEP_DEPTH = 0.075f;
enum Material GROUND = Material.dirt;
immutable uint[3] LAYER_SLOTS = [1, 4, 5];
immutable Material[3] LAYER_MATERIALS = [Material.woodPlanks, Material.greyBrick, Material.whiteBrick];
enum double TURN_SECONDS = 0.96;
enum double SETTLE_SECONDS = 0.48;
enum double LANDING_SECONDS = 2;
enum float MIN_BLOCK_EDGE = 0.035f;
enum float MAX_BLOCK_EDGE = 0.077f;
immutable Material[2] STREET_MATERIALS = [Material.basalt, Material.whiteBrick];
immutable Material[7] TOWER_MATERIALS = [Material.concrete, Material.whiteBrick, Material.greyBrick, Material.sandstone, Material.woodPlanks, Material.steel, Material.marble];
immutable Material[4] BACKROOMS_FLOORS = [Material.carpet, Material.dampCarpet, Material.redCarpet, Material.concrete];
immutable Material[3] BACKROOMS_CEILINGS = [Material.ceilingTile, Material.lightPanel, Material.concrete];

enum ClimbGoal : ubyte {
    timed,
    ontoStep,
}

struct Motion {
    float excess = 0;
    float excessAt = 0;
    float cap = SPEED;
    float rise = 0;
    float lowest = 0;
    float highest = 0;
    uint offGround;
    Footing lastFooting;
}

struct Across {
    float walked = 0;
    float climbed = 0;
}

string nameOf(Maybe!Material target) {
    if (target.exists) {
        return ENUM_NAMES!Material[target.value];
    } else {
        return "nothing";
    }
}

bool isMaterial(Maybe!Material target, Material material) {
    return target.exists && target.value == material;
}

bool isOneOf(Maybe!Material target, const(Material)[] materials) {
    foreach (material; materials) {
        if (isMaterial(target, material)) {
            return true;
        }
    }
    return false;
}

Maybe!Material lookBelow(ref Script world) {
    world.look(degrees(0), degrees(STRAIGHT_DOWN_DEGREES));
    Maybe!Material below = world.targetMaterial();
    world.look(degrees(0), degrees(-STRAIGHT_DOWN_DEGREES));
    return below;
}

void spawn(ref Script world) {
    world.check(world.mode() == MovementMode.walk, "spawned walking");
    world.check(world.isOnGround(), "spawned standing on the ground");
}

void onSlope(ref Script world, double tilt, double heading) {
    world.plane(degrees(tilt));
    spawn(world);
    if (heading != 0) {
        world.turn(degrees(heading), degrees(0), TURN_SECONDS);
    }
    world.wait(SETTLE_SECONDS);
}

float forward(ref Script world, double seconds, float minFraction) {
    float start = world.traveled().value;
    world.press(seconds, Key.fwd);
    float walked = world.traveled().value - start;
    float free = SPEED * seconds;
    string facing = nameOf(world.targetMaterial());
    world.check(walked >= minFraction * free, "walked %.4f of an unobstructed %.4f, facing %.*s", walked, free, cast(int) facing.length, facing.ptr);
    return walked;
}

bool isOnStep(ref Script world, float standing) {
    Maybe!Material below = lookBelow(world);
    return world.isOnGround() && world.altitude().value - standing > MIN_BLOCK_EDGE / 2 && isMaterial(below, LAYER_MATERIALS[0]);
}

void climbForward(ref Script world, double seconds, Time dt, ClimbGoal goal, float standing) {
    double deadline = world.time().value + seconds;
    world.hold(Key.fwd);
    world.step(dt);
    while (!world.isFailed && world.time().value < deadline && !(goal == ClimbGoal.ontoStep && isOnStep(world, standing))) {
        jumpIfBlocked(world);
        world.step(dt);
    }
    world.release(Key.fwd, Key.up);
}

void jumpIfBlocked(ref Script world) {
    world.release(Key.up);
    if (world.isOnGround() && world.horizontalSpeed().value < BLOCKED_SPEED) {
        world.hold(Key.up);
    }
}

Motion motionFrom(ref Script world) {
    float altitude = world.altitude().value;
    return Motion(0, 0, SPEED, 0, altitude, altitude, 0, world.footing());
}

void trackMotion(ref Script world, Motion* motion) {
    *motion = motionFrom(world);
    world.onStep(StepHook(&observeHook, motion));
}

void observeHook(ref Script world, void* context) {
    observe(world, *cast(Motion*) context);
}

void observe(ref Script world, ref Motion motion) {
    float speed = world.horizontalSpeed().value;
    float altitude = world.altitude().value;
    if (world.isOnGround()) {
        if (motion.lastFooting == Footing.airborne) {
            motion.cap = higherOf(SPEED, speed);
        }
        if (speed - motion.cap > motion.excess) {
            motion.excess = speed - motion.cap;
            motion.excessAt = world.time().value;
        }
        motion.cap = higherOf(SPEED, lowerOf(motion.cap, speed));
    } else {
        motion.offGround += 1;
    }
    motion.lastFooting = world.footing();
    motion.rise = higherOf(motion.rise, world.verticalSpeed().value);
    motion.lowest = lowerOf(motion.lowest, altitude);
    motion.highest = higherOf(motion.highest, altitude);
}

void checkSpeedLimit(ref Script world, ref const Motion motion) {
    world.check(motion.excess <= SPEED_TOLERANCE, "walking sped up %.4f past the walk speed or the landing speed at t=%.2f", motion.excess, motion.excessAt);
}

void checkOnStep(ref Script world, float standing, const(char)* what) {
    world.check(world.isOnGround(), "%s: on ground", what);
    float rise = world.altitude().value - standing;
    world.check(rise > MIN_BLOCK_EDGE / 2, "%s: rose %.4f", what, rise);
    Maybe!Material below = lookBelow(world);
    string name = nameOf(below);
    world.check(isMaterial(below, LAYER_MATERIALS[0]), "%s: standing on %.*s", what, cast(int) name.length, name.ptr);
}

void checkStanding(ref Script world, const(char)* what) {
    float altitude = world.altitude().value;
    world.check(world.isOnGround(), "%s: on ground", what);
    world.check(altitude - STANDING_ALTITUDE <= ALTITUDE_TOLERANCE && STANDING_ALTITUDE - altitude <= ALTITUDE_TOLERANCE, "%s: standing at altitude %.5f (expected %.5f)", what, altitude, STANDING_ALTITUDE);
}

void fly(ref Script world, float distance, Key key) {
    world.press(distance / FLY_SPEED, key);
}

void strafe(ref Script world, float distance) {
    if (distance > 0) {
        fly(world, distance, Key.right);
    } else if (distance < 0) {
        fly(world, -distance, Key.left);
    }
}

Key opposite(Key key) {
    if (key == Key.fwd) {
        return Key.back;
    } else if (key == Key.back) {
        return Key.fwd;
    } else if (key == Key.left) {
        return Key.right;
    } else {
        return Key.left;
    }
}

void buildLayer(ref Script world, Material below, Key key, uint steps) {
    uint step = 0;
    while (step <= steps && !world.isFailed) {
        world.look(degrees(0), degrees(STRAIGHT_DOWN_DEGREES));
        if (isMaterial(world.targetMaterial(), below)) {
            string name = ENUM_NAMES!Material[below];
            world.check(world.placeBlock(), "placed a block on %.*s %u steps along the row", cast(int) name.length, name.ptr, step);
        }
        world.look(degrees(0), degrees(-STRAIGHT_DOWN_DEGREES));
        if (step < steps) {
            fly(world, ROW_STEP, key);
        }
        step += 1;
    }
}

void buildRow(ref Script world, uint blocks, Key key, float length) {
    uint steps = cast(uint) ceil(length / ROW_STEP);
    Material below = GROUND;
    foreach (layer; 0 .. blocks) {
        world.material(LAYER_SLOTS[layer]);
        buildLayer(world, below, key, steps);
        below = LAYER_MATERIALS[layer];
        if (layer + 1 < blocks) {
            fly(world, steps * ROW_STEP, opposite(key));
        }
    }
    world.material(LAYER_SLOTS[0]);
}

void hover(ref Script world, uint blocks) {
    world.mode(MovementMode.fly);
    fly(world, WALL_HOVER_PER_BLOCK * blocks, Key.up);
}

void land(ref Script world) {
    world.step();
    world.mode(MovementMode.walk);
    world.wait(LANDING_SECONDS);
}

void buildWall(ref Script world, uint blocks) {
    hover(world, blocks);
    fly(world, WALL_DISTANCE, Key.fwd);
    strafe(world, -WALL_HALF_WIDTH);
    buildRow(world, blocks, Key.right, 2 * WALL_HALF_WIDTH);
    strafe(world, -WALL_HALF_WIDTH);
    fly(world, WALL_DISTANCE, Key.back);
    land(world);
}

void buildStep(ref Script world) {
    hover(world, 1);
    fly(world, WALL_DISTANCE, Key.fwd);
    strafe(world, -WALL_HALF_WIDTH);
    Key key = Key.right;
    uint rows = cast(uint) ceil(STEP_DEPTH / ROW_STEP);
    foreach (row; 0 .. rows + 1) {
        buildRow(world, 1, key, 2 * WALL_HALF_WIDTH);
        key = opposite(key);
        if (row < rows) {
            fly(world, ROW_STEP, Key.fwd);
        }
    }
    if (key == Key.right) {
        strafe(world, WALL_HALF_WIDTH);
    } else {
        strafe(world, -WALL_HALF_WIDTH);
    }
    fly(world, WALL_DISTANCE + rows * ROW_STEP, Key.back);
    land(world);
}

void buildCorner(ref Script world, uint blocks) {
    hover(world, blocks);
    fly(world, WALL_DISTANCE, Key.fwd);
    strafe(world, -WALL_HALF_WIDTH);
    buildRow(world, blocks, Key.right, 2 * WALL_HALF_WIDTH);
    buildRow(world, blocks, Key.back, WALL_DISTANCE);
    strafe(world, -WALL_HALF_WIDTH);
    land(world);
}

Across acrossSlope(ref Script world, double tilt, double heading, double seconds, float minFraction) {
    onSlope(world, tilt, heading);
    Motion motion;
    trackMotion(world, &motion);
    float start = world.altitude().value;
    float before = world.traveled().value;
    climbForward(world, seconds, world.timestep, ClimbGoal.timed, 0);
    float walked = world.traveled().value - before;
    float free = SPEED * seconds;
    string facing = nameOf(world.targetMaterial());
    world.check(walked >= minFraction * free, "walked %.4f of an unobstructed %.4f, facing %.*s", walked, free, cast(int) facing.length, facing.ptr);
    world.wait(LANDING_SECONDS);
    world.onStep(StepHook.init);
    checkSpeedLimit(world, motion);
    world.check(world.isOnGround(), "on ground at the end");
    return Across(walked, world.altitude().value - start);
}
