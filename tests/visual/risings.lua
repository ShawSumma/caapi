local walk = require("lib.walk")

local YAW_DEGREES = 90
local DISTANCE = 3.0
local LOOK_UP_DEGREES = -30

-- Out over the terrain world, looking up at the horospheres rising from it.
return function(world)
  world:mode("noclip")
  world:look(YAW_DEGREES, 0)
  world:press(DISTANCE / walk.NOCLIP_SPEED, "fwd")
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
