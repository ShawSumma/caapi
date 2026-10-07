local SETTLE_SECONDS = 0.5
local AHEAD_WAYPOINT = 6
local LOOK_UP_DEGREES = -10

return function(world)
  world:worldgen("structure", "tower")
  world:enter_stairs()
  world:wait(SETTLE_SECONDS)
  local yaw = world:stair_waypoint(AHEAD_WAYPOINT)
  world:look(yaw, LOOK_UP_DEGREES)
  world:step()
end
