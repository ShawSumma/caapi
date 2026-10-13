local NOCLIP_SPEED = 0.6
local EDGE = 1.0613
local VERTEX = 6
local ASIDE = 0.6
local DROP = 0.8
local AHEAD_WAYPOINT = 5
local TOWARD_ROAD_DEGREES = 90
local LOOK_DOWN_DEGREES = 0

return function(world)
  world:worldgen("terrain")
  world:mode("noclip")
  world:enter_route()
  local yaw = world:route_waypoint(AHEAD_WAYPOINT)
  world:look(yaw, 0)
  world:press(VERTEX * EDGE / NOCLIP_SPEED, "fwd")
  world:press(ASIDE / NOCLIP_SPEED, "left")
  world:press(DROP / NOCLIP_SPEED, "down")
  world:look(TOWARD_ROAD_DEGREES, LOOK_DOWN_DEGREES)
  world:step()
end
