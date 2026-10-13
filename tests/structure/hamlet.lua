local walk = require("lib.walk")

local HAMLET = "hamlet"
local HUTS = 5
local STOPS_PER_HUT = 14
local WALK_SECONDS = 6

return function(world)
  world:worldgen("structure", HAMLET)
  assert(world:route_waypoint(HUTS * STOPS_PER_HUT), "every hut added its stair route")
  assert(not world:route_waypoint(HUTS * STOPS_PER_HUT + 1), "and nothing else did")
  walk.spawn(world)
  local ground = world:altitude()
  world:press(WALK_SECONDS, "fwd")
  world:wait(walk.SETTLE_SECONDS)
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  assert(world:target_material() == "wood_planks", string.format("standing on %s instead of the first hut's floor", tostring(world:target_material())))
  assert(world:altitude() - ground > walk.MIN_BLOCK_EDGE / 2, "stepped over the hut's threshold")
end
