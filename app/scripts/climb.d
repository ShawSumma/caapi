module app.scripts.climb;

import base.maybe : Maybe;
import common.graph : Graph;
import common.position : Position;
import common.worldgen.structure : nodeToNode;
import geometry.lorentz : Point;
import app.script : Script, StepHook, degrees;
import app.scripts.claims : Measure, Topic, claim;
import plugins.game.game : Key, RouteWaypoint;
import app.scripts.walk : BLOCKED_SPEED, Motion, SETTLE_SECONDS, checkSpeedLimit, lookBelow, nameOf, trackMotion;

enum float REACHED_DISTANCE = 0.02f;
enum float REACHED_RISE = 0.02f;
enum uint MOST_STEPS_PER_WAYPOINT = 400;

enum Approach : ubyte {
    reached,
    going,
}

Approach approach(ref Script world, RouteWaypoint waypoint, size_t index, ref uint steps) {
    float rise = waypoint.rise.value;
    if (world.isOnGround() && waypoint.horizontal.value < REACHED_DISTANCE && rise < REACHED_RISE && -rise < REACHED_RISE) {
        steps = 0;
        return Approach.reached;
    } else {
        if (steps >= MOST_STEPS_PER_WAYPOINT) {
            const(char)[] below = nameOf(lookBelow(world));
            const(char)[] ahead = nameOf(world.targetMaterial());
            world.fail("stuck before waypoint %zu, %.4f away and %.4f up, altitude %.3f, on %.*s facing %.*s", index, waypoint.horizontal.value, rise, world.altitude().value, cast(int) below.length, below.ptr, cast(int) ahead.length, ahead.ptr);
        }
        world.look(waypoint.yaw, degrees(0));
        world.step();
        world.release(Key.up);
        if (world.isOnGround() && world.horizontalSpeed().value < BLOCKED_SPEED && rise > REACHED_RISE) {
            world.hold(Key.up);
        }
        steps += 1;
        return Approach.going;
    }
}

size_t follow(ref Script world, Maybe!size_t last) {
    size_t index = 1;
    uint steps = 0;
    world.hold(Key.forward);
    Maybe!RouteWaypoint next = world.routeWaypoint(index);
    while (!world.isFailed && (!last.exists || index <= last.value) && next.exists) {
        if (approach(world, next.value, index, steps) == Approach.reached) {
            index += 1;
        }
        next = world.routeWaypoint(index);
    }
    world.release(Key.forward, Key.up);
    return index - 1;
}

RouteWaypoint waypointTo(ref Script world, Position stop) {
    const(Graph)* graph = &world.game.world.graph;
    Point!float there = graph.ownView.nodeToNode(graph.slotOf(stop.node).value, graph.slotOf(world.game.characterState.position.node).value) * stop.local * Point!float.origin();
    RouteWaypoint waypoint = world.game.waypointAt(there);
    waypoint.yaw = -waypoint.yaw;
    return waypoint;
}

size_t followStops(ref Script world, const(Position)[] stops) {
    size_t index = 0;
    uint steps = 0;
    world.hold(Key.forward);
    while (!world.isFailed && index < stops.length) {
        if (approach(world, waypointTo(world, stops[index]), index + 1, steps) == Approach.reached) {
            index += 1;
        }
    }
    world.release(Key.forward, Key.up);
    return index;
}

void route(ref Script world, float minClimb) {
    world.enterRoute();
    world.wait(SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing at the start of the route");
    float start = world.altitude().value;
    Motion motion;
    trackMotion(world, &motion);
    size_t reached = follow(world, Maybe!size_t.init);
    world.wait(SETTLE_SECONDS);
    world.onStep(StepHook.init);
    world.check(world.isOnGround(), "standing after %zu waypoints", reached);
    world.claim(Topic.structures, "The stair route through the structure can be walked on foot from its first stop to its last.", world.altitude().value - start >= minClimb, Measure.of("stops reached", reached), Measure.of("climbed", world.altitude().value - start));
    checkSpeedLimit(world, motion);
}
