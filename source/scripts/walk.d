module scripts.walk;

import core.stdc.math : ceil;
import base.maybe : Maybe;
import base.numbers : higherOf, lowerOf;
import base.units : Time;
import client.game : Key;
import client.script : Script, StepHook, degrees;
import client.structures : probePort;
import common.character.controller : Footing, MovementMode;
import common.graph : Graph;
import common.items : materialNames;
import common.position : Position;
import common.worldgen.horospheres : ROOT, edgeOf, ensurePlaneHeight, ensureUndersideAt;
import common.worldgen.structure : ColumnSpot, SiteFrame, columnPoint, edgeCells, forwarded, moveToLevel, rootSite, siteOf, sitePlacement, turnSite;
import geometry.lorentz : Point, Shift = Motion;
import plugins.api.api : Material, Turn;
import scripts.claims : Measure, Topic, claim;

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
enum string GROUND = "base:dirt";
immutable BuildLayer[3] BUILD_LAYERS = [BuildLayer(1, "base:wood-planks"), BuildLayer(4, "base:grey-brick"), BuildLayer(5, "base:white-brick")];
enum double TURN_SECONDS = 0.96;
enum double SETTLE_SECONDS = 0.48;
enum double LANDING_SECONDS = 2;
enum float LEAST_BLOCK_EDGE = 0.035f;
enum float MOST_BLOCK_EDGE = 0.077f;
enum size_t MOST_PORT_SITES = 512;
enum int BENEATH_EDGES = 3;
enum float BENEATH_MARGIN_EDGES = 0.5f;
immutable string[2] STREET_MATERIALS =["base:basalt", "base:white-brick"];
immutable string[7] TOWER_MATERIALS = ["base:concrete", "base:white-brick", "base:grey-brick", "base:sandstone", "base:wood-planks", "base:steel", "base:marble"];
immutable string[5] BACKROOMS_FLOORS = ["base:carpet", "base:damp-carpet", "base:red-carpet", "base:concrete", "base:marble"];
immutable string[6] BACKROOMS_CEILINGS = ["base:ceiling-tile", "base:light-panel", "base:concrete", "base:plaster", "base:white-brick", "base:sunlight"];

struct BuildLayer {
    uint slot;
    string material;
}

enum Beneath : ubyte {
    open,
    rock,
}

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

const(char)[] nameOf(Maybe!Material target) {
    if (target.exists) {
        return materialNames.ptr[target.value.id];
    } else {
        return "nothing";
    }
}

bool isMaterial(Maybe!Material target, const(char)[] name) {
    return target.exists && materialNames.ptr[target.value.id] == name;
}

bool isOneOf(Maybe!Material target, const(string)[] names) {
    size_t index = 0;
    while (index < names.length && !isMaterial(target, names[index])) {
        index += 1;
    }
    return index < names.length;
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

Position ensureVertex(ref Graph graph, SiteFrame site) {
    Point!float vertex = sitePlacement(site, graph.layout) * Point!float.origin();
    return graph.ensureNormalized(Position(graph.idAt(site.node), Shift!float.shiftTo(vertex)));
}

Maybe!Position ensureLastFlat(ref Script world) {
    Graph* graph = &world.game.world.graph;
    const(SiteFrame)[] flats = graph.structures.blueprint.flats.slice();
    if (flats.length == 0) {
        return Maybe!Position.init;
    } else {
        return Maybe!Position.of((*graph).ensureVertex(flats[$ - 1]));
    }
}

Position ensureBelowVertex(ref Graph graph, SiteFrame site, int edges) {
    SiteFrame up = graph.view.turnSite(site, Turn.pitchUp);
    float center = graph.layout.dimension;
    Point!float spot = sitePlacement(up, graph.layout) * columnPoint(graph.layout, ColumnSpot(center, center, -edges * edgeCells(graph.layout.dimension) - center));
    return graph.ensureNormalized(Position(graph.idAt(up.node), Shift!float.shiftTo(spot)));
}

bool isBeneath(Beneath wanted, float depth, float underside, float margin) {
    final switch (wanted) {
        case Beneath.open:
            return depth > underside + margin;
        case Beneath.rock:
            return depth < underside - margin;
    }
}

Maybe!Position ensureUnderGround(ref Script world, Beneath wanted) {
    Graph* graph = &world.game.world.graph;
    float margin = BENEATH_MARGIN_EDGES * graph.view.edgeOf();
    SiteFrame[MOST_PORT_SITES] sites;
    sites[0] = rootSite(graph.anchorSlot);
    size_t count = 1;
    size_t next = 0;
    Maybe!Position found;
    while (!found.exists && next < count) {
        SiteFrame site = graph.view.moveToLevel(sites[next], 0);
        next += 1;
        Position below = (*graph).ensureBelowVertex(site, BENEATH_EDGES);
        float depth = -graph.view.ensurePlaneHeight(ROOT, below);
        float underside = graph.view.ensureUndersideAt(ROOT, below);
        if (isBeneath(wanted, depth, underside, margin)) {
            found = Maybe!Position.of(below);
        } else if (count + 3 <= MOST_PORT_SITES) {
            SiteFrame ahead = forwarded(site, 1);
            sites[count] = ahead;
            sites[count + 1] = graph.view.turnSite(ahead, Turn.left);
            sites[count + 2] = graph.view.turnSite(ahead, Turn.right);
            count += 3;
        }
    }
    return found;
}

Maybe!Position ensurePort(ref Script world) {
    Graph* graph = &world.game.world.graph;
    SiteFrame[MOST_PORT_SITES] sites;
    sites[0] = rootSite(graph.anchorSlot);
    size_t count = 1;
    size_t next = 0;
    Maybe!Position found;
    while (!found.exists && next < count) {
        SiteFrame site = graph.view.moveToLevel(sites[next], 0);
        next += 1;
        bool port = graph.view.probePort(siteOf(site), ROOT);
        if (port) {
            found = Maybe!Position.of((*graph).ensureVertex(site));
        } else if (count + 3 <= MOST_PORT_SITES) {
            SiteFrame ahead = forwarded(site, 1);
            sites[count] = ahead;
            sites[count + 1] = graph.view.turnSite(ahead, Turn.left);
            sites[count + 2] = graph.view.turnSite(ahead, Turn.right);
            count += 3;
        }
    }
    return found;
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
    world.press(seconds, Key.forward);
    float walked = world.traveled().value - start;
    float free = SPEED * seconds;
    const(char)[] facing = nameOf(world.targetMaterial());
    world.check(walked >= minFraction * free, "walked %.4f of an unobstructed %.4f, facing %.*s", walked, free, cast(int) facing.length, facing.ptr);
    return walked;
}

bool probeOnStep(ref Script world, float standing) {
    Maybe!Material below = lookBelow(world);
    return world.isOnGround() && world.altitude().value - standing > LEAST_BLOCK_EDGE / 2 && isMaterial(below, BUILD_LAYERS[0].material);
}

bool probeReached(ref Script world, ClimbGoal goal, float standing) {
    if (goal == ClimbGoal.ontoStep) {
        return probeOnStep(world, standing);
    } else {
        return false;
    }
}

void climbForward(ref Script world, double seconds, Time dt, ClimbGoal goal, float standing) {
    double deadline = world.time().value + seconds;
    world.hold(Key.forward);
    world.step(dt);
    bool reached = probeReached(world, goal, standing);
    while (!world.isFailed && world.time().value < deadline && !reached) {
        jumpIfBlocked(world);
        world.step(dt);
        reached = probeReached(world, goal, standing);
    }
    world.release(Key.forward, Key.up);
}

void jumpIfBlocked(ref Script world) {
    world.release(Key.up);
    if (world.isOnGround() && world.horizontalSpeed().value < BLOCKED_SPEED) {
        world.hold(Key.up);
    }
}

Motion motionFrom(ref Script world) {
    Motion motion;
    motion.lowest = world.altitude().value;
    motion.highest = motion.lowest;
    motion.lastFooting = world.footing();
    return motion;
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
    world.claim(Topic.movement, "On the ground the body never moves faster than its walk speed, or than the speed it landed with.", motion.excess <= SPEED_TOLERANCE, Measure.of("largest excess", motion.excess), Measure.of("at second", motion.excessAt));
}

void checkOnStep(ref Script world, float standing, const(char)* what) {
    world.check(world.isOnGround(), "%s: on ground", what);
    float rise = world.altitude().value - standing;
    world.check(rise > LEAST_BLOCK_EDGE / 2, "%s: rose %.4f", what, rise);
    Maybe!Material below = lookBelow(world);
    const(char)[] name = nameOf(below);
    world.check(isMaterial(below, BUILD_LAYERS[0].material), "%s: standing on %.*s", what, cast(int) name.length, name.ptr);
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
    if (key == Key.forward) {
        return Key.back;
    } else if (key == Key.back) {
        return Key.forward;
    } else if (key == Key.left) {
        return Key.right;
    } else {
        return Key.left;
    }
}

void buildLayer(ref Script world, string below, Key key, uint steps) {
    uint step = 0;
    while (step <= steps && !world.isFailed) {
        world.look(degrees(0), degrees(STRAIGHT_DOWN_DEGREES));
        if (isMaterial(world.targetMaterial(), below)) {
            bool placed = world.placeBlock();
            world.check(placed, "placed a block on %.*s %u steps along the row", cast(int) below.length, below.ptr, step);
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
    string below = GROUND;
    foreach (layer; 0 .. blocks) {
        world.material(BUILD_LAYERS[layer].slot);
        buildLayer(world, below, key, steps);
        below = BUILD_LAYERS[layer].material;
        if (layer + 1 < blocks) {
            fly(world, steps * ROW_STEP, opposite(key));
        }
    }
    world.material(BUILD_LAYERS[0].slot);
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
    fly(world, WALL_DISTANCE, Key.forward);
    strafe(world, -WALL_HALF_WIDTH);
    buildRow(world, blocks, Key.right, 2 * WALL_HALF_WIDTH);
    strafe(world, -WALL_HALF_WIDTH);
    fly(world, WALL_DISTANCE, Key.back);
    land(world);
}

void buildStep(ref Script world) {
    hover(world, 1);
    fly(world, WALL_DISTANCE, Key.forward);
    strafe(world, -WALL_HALF_WIDTH);
    Key key = Key.right;
    uint rows = cast(uint) ceil(STEP_DEPTH / ROW_STEP);
    foreach (row; 0 .. rows + 1) {
        buildRow(world, 1, key, 2 * WALL_HALF_WIDTH);
        key = opposite(key);
        if (row < rows) {
            fly(world, ROW_STEP, Key.forward);
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
    fly(world, WALL_DISTANCE, Key.forward);
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
    const(char)[] facing = nameOf(world.targetMaterial());
    world.check(walked >= minFraction * free, "walked %.4f of an unobstructed %.4f, facing %.*s", walked, free, cast(int) facing.length, facing.ptr);
    world.wait(LANDING_SECONDS);
    world.onStep(StepHook.init);
    checkSpeedLimit(world, motion);
    world.check(world.isOnGround(), "on ground at the end");
    return Across(walked, world.altitude().value - start);
}
