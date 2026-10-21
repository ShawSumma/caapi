local climb = require("lib.climb")
local walk = require("lib.walk")

local SKY_ALTITUDE = 1.5

return function(world)
  world:worldgen("structure", "skybackrooms")
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  assert(world:altitude() < SKY_ALTITUDE, string.format("starting on the planet, %.3f up", world:altitude()))
  local reached = climb.follow(world, math.huge)
  world:wait(walk.SETTLE_SECONDS)
  assert(world:route_waypoint(reached + 1) == nil, string.format("stopped after %d waypoints", reached))
  assert(world:is_on_ground(), "standing in the backrooms")
  assert(world:altitude() > SKY_ALTITUDE, string.format("ended only %.3f above the planet", world:altitude()))
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  local below = world:target_material()
  world:look(0, -2 * walk.STRAIGHT_DOWN_DEGREES)
  local above = world:target_material()
  assert(walk.BACKROOMS_FLOORS[below] ~= nil, string.format("standing on %s instead of the backrooms' floor", tostring(below)))
  assert(walk.BACKROOMS_CEILINGS[above] ~= nil, string.format("under %s instead of the backrooms' ceiling", tostring(above)))
end
