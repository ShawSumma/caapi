local climb = require("lib.climb")
local walk = require("lib.walk")

local BACKROOMS = "tests/lib/backrooms.lua"
local SKY_ALTITUDE = 1.5
local FLOORS = {
  carpet = true,
  damp_carpet = true,
  red_carpet = true,
  concrete = true,
}
local CEILINGS = {
  ceiling_tile = true,
  light_panel = true,
  concrete = true,
}

-- The connector climbs from the planet into the backrooms, where the floor is carpet and the ceiling is low.
return function(world)
  world:worldgen("structure", BACKROOMS)
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  assert(world:altitude() < SKY_ALTITUDE, string.format("starting on the planet, %.3f up", world:altitude()))
  local reached = climb.follow(world, math.huge)
  world:wait(walk.SETTLE_SECONDS)
  assert(not world:route_waypoint(reached + 1), string.format("stopped after %d waypoints", reached))
  assert(world:is_on_ground(), "standing in the backrooms")
  assert(world:altitude() > SKY_ALTITUDE, string.format("ended only %.3f above the planet", world:altitude()))
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  local below = world:target_material()
  world:look(0, -2 * walk.STRAIGHT_DOWN_DEGREES)
  local above = world:target_material()
  assert(FLOORS[below], string.format("standing on %s instead of the backrooms' floor", tostring(below)))
  assert(CEILINGS[above], string.format("under %s instead of the backrooms' ceiling", tostring(above)))
end
