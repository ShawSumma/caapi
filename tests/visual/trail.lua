local walk = require("lib.walk")

local RISE = 0.7
local LOOK_DOWN_DEGREES = 75

return function(world)
  world:worldgen("structure", "trail")
  world:enter_route()
  world:mode("noclip")
  world:press(RISE / walk.NOCLIP_SPEED, "up")
  world:look(0, LOOK_DOWN_DEGREES)
  world:step()
end
