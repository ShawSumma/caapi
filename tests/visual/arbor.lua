local walk = require("lib.walk")

local BACK_OUT = 0.6
local LOOK_UP_DEGREES = -35

return function(world)
  world:worldgen("structure", "arbor")
  world:mode("noclip")
  world:press(BACK_OUT / walk.NOCLIP_SPEED, "back")
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
