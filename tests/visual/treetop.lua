local walk = require("lib.walk")

local TOWARD_TREE = 1.2
local LOOK_UP_DEGREES = -75

return function(world)
  world:worldgen("terrain")
  world:mode("noclip")
  world:press(TOWARD_TREE / walk.NOCLIP_SPEED, "fwd")
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
