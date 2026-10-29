local walk = require("lib.walk")

local YAW_DEGREES = 90
local DISTANCE = 3.0

return function(world)
  world:mode("noclip")
  world:look(YAW_DEGREES, 0)
  world:press(DISTANCE / walk.NOCLIP_SPEED, "fwd")
  world:look(0, -walk.STRAIGHT_DOWN_DEGREES)
  world:step()
end
