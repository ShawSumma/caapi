local walk = require("lib.walk")

local BACK = 0.3
local RISE = 0.3
local TURN_DEGREES = 90
local LOOK_DOWN_DEGREES = 20

return function(world)
  world:worldgen("structure", "city")
  world:mode("noclip")
  world:look(TURN_DEGREES, 0)
  world:press(BACK / walk.NOCLIP_SPEED, "back")
  world:press(RISE / walk.NOCLIP_SPEED, "up")
  world:look(0, LOOK_DOWN_DEGREES)
  world:step()
end
