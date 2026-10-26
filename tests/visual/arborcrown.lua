local walk = require("lib.walk")

local TOWARD_TRUNK = 0.9
local RISE = 1.6
local LOOK_DOWN_DEGREES = 30

return function(world)
  world:worldgen("structure", "arbor")
  world:mode("noclip")
  world:press(TOWARD_TRUNK / walk.NOCLIP_SPEED, "fwd")
  world:press(RISE / walk.NOCLIP_SPEED, "up")
  world:look(0, LOOK_DOWN_DEGREES)
  world:step()
end
