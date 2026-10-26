local walk = require("lib.walk")

local TOWARD_TOWER = 1.0
local RISE = 1.5
local LOOK_DOWN_DEGREES = 50

return function(world)
  world:worldgen("structure", "babel")
  world:mode("noclip")
  world:press(TOWARD_TOWER / walk.NOCLIP_SPEED, "fwd")
  world:press(RISE / walk.NOCLIP_SPEED, "up")
  world:look(0, LOOK_DOWN_DEGREES)
  world:step()
end
