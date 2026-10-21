local walk = require("lib.walk")

local AHEAD = 4
local RISE = 0.15
local LOOK_UP_DEGREES = -10

return function(world)
  world:worldgen("structure", "city")
  world:mode("noclip")
  world:press(AHEAD / walk.NOCLIP_SPEED, "fwd")
  world:press(RISE / walk.NOCLIP_SPEED, "up")
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
