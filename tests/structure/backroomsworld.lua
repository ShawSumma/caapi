local walk = require("lib.walk")

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

return function(world)
  world:worldgen("structure", "backrooms")
  walk.spawn(world)
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  local below = world:target_material()
  world:look(0, -2 * walk.STRAIGHT_DOWN_DEGREES)
  local above = world:target_material()
  assert(FLOORS[below], string.format("standing on %s instead of the backrooms' floor", tostring(below)))
  assert(CEILINGS[above], string.format("under %s instead of the backrooms' ceiling", tostring(above)))
end
