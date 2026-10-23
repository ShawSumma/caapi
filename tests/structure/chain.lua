local climb = require("lib.climb")
local walk = require("lib.walk")

local LANDING = "concrete"
local LOWER_ALTITUDE = 1.5
local LEAST_MOVED = 0.5

return function(world)
  world:worldgen("structure", "chain")
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  assert(world:is_on_ground(), "standing on the first city outside the connector's lower door")
  local start = world:altitude()
  assert(start > LOWER_ALTITUDE, string.format("starting only %.3f above the ground, not on the first city", start))
  local reached = climb.follow(world, math.huge)
  world:wait(walk.SETTLE_SECONDS)
  assert(world:route_waypoint(reached + 1) == nil, string.format("stopped after %d waypoints", reached))
  assert(world:is_on_ground(), "standing in the city risen from the first")
  assert(math.abs(world:altitude() - start) > LEAST_MOVED, string.format("ended %.3f above the ground from %.3f, still by the first city", world:altitude(), start))
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  local below = world:target_material()
  assert(below == LANDING, string.format("standing on %s instead of the connector's landing", tostring(below)))
end
