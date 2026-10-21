local climb = require("lib.climb")
local walk = require("lib.walk")

local LANDING = "concrete"
local COPY_ALTITUDE = 2.0

return function(world)
  world:worldgen("structure", "risenwild")
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  assert(world:is_on_ground(), "standing outside the connector's lower door")
  assert(world:altitude() < COPY_ALTITUDE, string.format("starting on the ground, %.3f up", world:altitude()))
  local reached = climb.follow(world, math.huge)
  world:wait(walk.SETTLE_SECONDS)
  assert(world:route_waypoint(reached + 1) == nil, string.format("stopped after %d waypoints", reached))
  assert(world:is_on_ground(), "standing in the risen terrain")
  assert(world:altitude() > COPY_ALTITUDE, string.format("ended only %.3f above the ground", world:altitude()))
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  local below = world:target_material()
  assert(below == LANDING, string.format("standing on %s instead of the connector's landing", tostring(below)))
end
