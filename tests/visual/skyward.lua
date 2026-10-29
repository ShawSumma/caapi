local walk = require("lib.walk")

local RISE = 2.5
local YAW_DEGREES = 90
local LOOK_DOWN_DEGREES = 70

return function(world)
  world:mode("noclip")
  world:look(YAW_DEGREES, -walk.STRAIGHT_DOWN_DEGREES)
  world:press(RISE / walk.NOCLIP_SPEED, "fwd")
  world:look(0, walk.STRAIGHT_DOWN_DEGREES + LOOK_DOWN_DEGREES)
  world:step()
end
