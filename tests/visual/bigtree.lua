local walk = require("lib.walk")

local BACK = 1.0
local RISE = 0.5
local LOOK_UP_DEGREES = -5

return function(world)
  world:worldgen("terrain")
  world:mode("noclip")
  world:press(BACK / walk.NOCLIP_SPEED, "back")
  world:press(RISE / walk.NOCLIP_SPEED, "up")
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
