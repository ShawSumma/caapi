local walk = require("lib.walk")

local climb = {}

local REACHED_DISTANCE = 0.02
local REACHED_RISE = 0.02
local MAX_STEPS_PER_WAYPOINT = 400

function climb.follow(world, last)
  local index = 1
  local steps = 0
  world:hold("fwd")
  while index <= last and world:route_waypoint(index) ~= nil do
    local yaw, horizontal, rise = world:route_waypoint(index)
    if world:is_on_ground() and horizontal < REACHED_DISTANCE and math.abs(rise) < REACHED_RISE then
      index = index + 1
      steps = 0
    else
      assert(steps < MAX_STEPS_PER_WAYPOINT, string.format("stuck before waypoint %d, %.4f away and %.4f up", index, horizontal, rise))
      world:look(yaw, 0)
      world:step()
      world:release("up")
      if world:is_on_ground() and world:horizontal_speed() < walk.BLOCKED_SPEED and rise > REACHED_RISE then
        world:hold("up")
      end
      steps = steps + 1
    end
  end
  world:release("fwd", "up")
  return index - 1
end

function climb.route(world, min_climb)
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  assert(world:is_on_ground(), "standing at the start of the route")
  local start = world:altitude()
  local motion = walk.track_motion(world)
  local reached = climb.follow(world, math.huge)
  world:wait(walk.SETTLE_SECONDS)
  assert(world:is_on_ground(), string.format("standing after %d waypoints", reached))
  assert(world:altitude() - start >= min_climb, string.format("climbed only %.3f over %d waypoints", world:altitude() - start, reached))
  walk.check_speed_limit(motion)
end

return climb
