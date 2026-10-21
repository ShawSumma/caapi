local walk = require("lib.walk")

local RISE = 2.0

return function(world)
  world:worldgen("structure", "city")
  world:mode("noclip")
  world:look(0, -walk.STRAIGHT_DOWN_DEGREES)
  world:press(RISE / walk.NOCLIP_SPEED, "fwd")
  world:look(0, 2 * walk.STRAIGHT_DOWN_DEGREES)
  world:step()
end
