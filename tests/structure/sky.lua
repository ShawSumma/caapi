local climb = require("lib.climb")
local walk = require("lib.walk")

local SKIES = "tests/lib/skies.lua"
local PLAZA = "granite"

return function(world)
  world:worldgen("structure", SKIES)
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  assert(world:is_on_ground(), "standing at the planet's door of the connector")
  local reached = climb.follow(world, math.huge)
  world:wait(walk.SETTLE_SECONDS)
  assert(not world:route_waypoint(reached + 1), string.format("stopped after %d waypoints", reached))
  assert(world:is_on_ground(), "standing in the sky city")
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  local below = world:target_material()
  assert(below == PLAZA, string.format("standing on %s instead of the sky city's plaza", tostring(below)))
end
