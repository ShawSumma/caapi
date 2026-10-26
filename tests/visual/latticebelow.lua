local walk = require("lib.walk")

local AWAY = 0.6
local LOOK_DOWN_DEGREES = 50

return function(world)
  world:worldgen("structure", "lattice")
  world:mode("noclip")
  world:press(AWAY / walk.NOCLIP_SPEED, "up")
  world:look(0, LOOK_DOWN_DEGREES)
  world:step()
end
