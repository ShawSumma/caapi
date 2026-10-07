local climb = require("lib.climb")

local FIRST_ARCH_WAYPOINT = 45
local APEX_WAYPOINT = 50
local LOOK_UP_DEGREES = -15

return function(world)
  world:worldgen("structure", "crown")
  world:enter_route()
  climb.follow(world, FIRST_ARCH_WAYPOINT)
  local yaw = world:route_waypoint(APEX_WAYPOINT)
  world:look(yaw, LOOK_UP_DEGREES)
  world:step()
end
