local walk = require("lib.walk")

local YAW_DEGREES = 90
local DISTANCE = 4.0
local LOOK_UP_DEGREES = -30

return function(world)
  world:mode("noclip")
  world:look(YAW_DEGREES, 0)
  world:press(DISTANCE / walk.NOCLIP_SPEED, "fwd")
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
