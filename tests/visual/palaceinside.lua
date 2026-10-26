local walk = require("lib.walk")

local INTO_HALL = 1.3
local LOOK_DOWN_DEGREES = 25

return function(world)
  world:worldgen("structure", "palace")
  world:mode("noclip")
  world:press(INTO_HALL / walk.NOCLIP_SPEED, "fwd")
  world:look(0, LOOK_DOWN_DEGREES)
  world:step()
end
