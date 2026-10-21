local walk = require("lib.walk")

local RISE = 0.7
local AHEAD = 2.0
local LOOK_DOWN_DEGREES = 25

return function(world)
  world:mode("noclip")
  world:press(AHEAD / walk.NOCLIP_SPEED, "fwd")
  world:look(0, -walk.STRAIGHT_DOWN_DEGREES)
  world:press(RISE / walk.NOCLIP_SPEED, "fwd")
  world:look(0, walk.STRAIGHT_DOWN_DEGREES + LOOK_DOWN_DEGREES)
  world:step()
end
