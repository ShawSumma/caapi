local walk = require("lib.walk")

local AHEAD_WAYPOINT = 6
local LOOK_UP_DEGREES = -10

return function(world)
  world:worldgen("structure", "tower")
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  local yaw = world:route_waypoint(AHEAD_WAYPOINT)
  world:look(yaw, LOOK_UP_DEGREES)
  world:step()
end
