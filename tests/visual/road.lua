local walk = require("lib.walk")

local RISE = 0.3
local AHEAD_WAYPOINT = 5
local LOOK_DOWN_DEGREES = 25

return function(world)
  world:worldgen("terrain")
  world:mode("noclip")
  world:enter_route()
  world:press(RISE / walk.NOCLIP_SPEED, "up")
  local yaw = world:route_waypoint(AHEAD_WAYPOINT)
  world:look(yaw, LOOK_DOWN_DEGREES)
  world:step()
end
