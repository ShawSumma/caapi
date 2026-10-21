local walk = require("lib.walk")

local RISE = 0.5
local LOOK_DOWN_DEGREES = 20

return function(world)
  world:worldgen("structure", "hamlet")
  world:mode("noclip")
  world:press(RISE / walk.NOCLIP_SPEED, "up")
  world:look(0, LOOK_DOWN_DEGREES)
  world:step()
end
