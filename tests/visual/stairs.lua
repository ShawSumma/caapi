local SETTLE_SECONDS = 0.5
local AHEAD_WAYPOINT = 3
local LOOK_UP_DEGREES = -20

return function(world)
  world:worldgen("structure", "tower")
  world:enter_route()
  world:wait(SETTLE_SECONDS)
  local yaw = world:route_waypoint(AHEAD_WAYPOINT)
  world:look(yaw, LOOK_UP_DEGREES)
  world:step()
end
