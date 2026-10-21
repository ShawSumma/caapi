local walk = require("lib.walk")

local BACK = 1.2
local LOOK_UP_DEGREES = -40

return function(world)
  world:worldgen("structure", "skywild")
  world:enter_route()
  world:mode("noclip")
  world:press(BACK / walk.NOCLIP_SPEED, "back")
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
