local climb = require("lib.climb")
local walk = require("lib.walk")

local ROAD_MATERIALS = {
  basalt = true,
  white_brick = true,
}

return function(world)
  world:worldgen("structure", "road")
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  local reached = climb.follow(world, math.huge)
  world:wait(walk.SETTLE_SECONDS)
  assert(world:is_on_ground(), string.format("standing on the road after %d waypoints", reached))
  assert(not world:route_waypoint(reached + 1), string.format("stopped after %d waypoints", reached))
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  local below = world:target_material()
  assert(ROAD_MATERIALS[below], string.format("standing on %s instead of the road", tostring(below)))
end
