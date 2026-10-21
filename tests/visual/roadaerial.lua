local walk = require("lib.walk")

local EDGE = 1.0613
local VERTEX = 6
local ASIDE = 0.6
local DROP = 0.8
local AHEAD_WAYPOINT = 5
local TOWARD_ROAD_DEGREES = 90

return function(world)
  world:worldgen("terrain")
  world:mode("noclip")
  world:enter_route()
  local yaw = world:route_waypoint(AHEAD_WAYPOINT)
  world:look(yaw, 0)
  world:press(VERTEX * EDGE / walk.NOCLIP_SPEED, "fwd")
  world:press(ASIDE / walk.NOCLIP_SPEED, "left")
  world:press(DROP / walk.NOCLIP_SPEED, "down")
  world:look(TOWARD_ROAD_DEGREES, 0)
  world:step()
end
