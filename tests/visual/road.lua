local NOCLIP_SPEED = 0.6
local RISE = 0.3
local AHEAD_WAYPOINT = 5
local LOOK_DOWN_DEGREES = 25

return function(world)
  world:worldgen("structure", "road")
  world:mode("noclip")
  world:enter_route()
  world:press(RISE / NOCLIP_SPEED, "up")
  local yaw = world:route_waypoint(AHEAD_WAYPOINT)
  world:look(yaw, LOOK_DOWN_DEGREES)
  world:step()
end
