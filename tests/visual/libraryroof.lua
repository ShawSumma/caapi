local walk = require("lib.walk")

local RISE = 1.9
local LOOK_DOWN_DEGREES = 60

return function(world)
  world:worldgen("structure", "library")
  world:mode("noclip")
  world:press(RISE / walk.NOCLIP_SPEED, "up")
  world:look(0, LOOK_DOWN_DEGREES)
  world:step()
end
