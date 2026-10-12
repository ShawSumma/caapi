local walk = require("lib.walk")

local NOCLIP_SPEED = 0.6
local DROP = 0.55
local FLOORS = {
  concrete = true,
  basalt = true,
  carpet = true,
  damp_carpet = true,
}
local CEILINGS = {
  concrete = true,
  steel = true,
  slate = true,
  ceiling_tile = true,
  light_panel = true,
}

-- The layer below the lobby is its own closed-in rooms, with one of its own floors below and ceilings above.
return function(world)
  world:worldgen("structure", "backrooms")
  world:mode("noclip")
  world:press(DROP / NOCLIP_SPEED, "down")
  world:look(0, -walk.STRAIGHT_DOWN_DEGREES)
  local above = world:target_material()
  world:look(0, 2 * walk.STRAIGHT_DOWN_DEGREES)
  local below = world:target_material()
  assert(CEILINGS[above], string.format("under %s instead of the second layer's ceiling", tostring(above)))
  assert(FLOORS[below], string.format("over %s instead of the second layer's floor", tostring(below)))
end
