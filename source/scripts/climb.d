module scripts.climb;

import client.game : Key, RouteWaypoint;
import client.script : Script, StepHook, degrees;
import scripts.walk : BLOCKED_SPEED, Motion, SETTLE_SECONDS, checkSpeedLimit, trackMotion;

enum float REACHED_DISTANCE = 0.02f;
enum float REACHED_RISE = 0.02f;
enum uint MAX_STEPS_PER_WAYPOINT = 400;
enum size_t EVERY_WAYPOINT = size_t.max;

size_t follow(ref Script world, size_t last) {
    size_t index = 1;
    uint steps = 0;
    world.hold(Key.fwd);
    while (!world.isFailed && index <= last && world.routeWaypoint(index).isFound) {
        RouteWaypoint waypoint = world.routeWaypoint(index);
        float rise = waypoint.rise.value;
        if (world.isOnGround() && waypoint.horizontal.value < REACHED_DISTANCE && rise < REACHED_RISE && -rise < REACHED_RISE) {
            index += 1;
            steps = 0;
        } else {
            world.check(steps < MAX_STEPS_PER_WAYPOINT, "stuck before waypoint %zu, %.4f away and %.4f up", index, waypoint.horizontal.value, rise);
            world.look(waypoint.yaw, degrees(0));
            world.step();
            world.release(Key.up);
            if (world.isOnGround() && world.horizontalSpeed().value < BLOCKED_SPEED && rise > REACHED_RISE) {
                world.hold(Key.up);
            }
            steps += 1;
        }
    }
    world.release(Key.fwd, Key.up);
    return index - 1;
}

void route(ref Script world, float minClimb) {
    world.enterRoute();
    world.wait(SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing at the start of the route");
    float start = world.altitude().value;
    Motion motion;
    trackMotion(world, &motion);
    size_t reached = follow(world, EVERY_WAYPOINT);
    world.wait(SETTLE_SECONDS);
    world.onStep(StepHook.init);
    world.check(world.isOnGround(), "standing after %zu waypoints", reached);
    world.check(world.altitude().value - start >= minClimb, "climbed only %.3f over %zu waypoints", world.altitude().value - start, reached);
    checkSpeedLimit(world, motion);
}
