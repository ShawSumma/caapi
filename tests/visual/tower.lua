local walk = require("lib.walk")

local VIEW_HEIGHT = 2
local BACK_OUT = 0.75
local LOOK_DOWN_DEGREES = 20
local TURN_AROUND_DEGREES = 180

return function(world)
  world:worldgen("structure", "tower")
  world:mode("noclip")
  world:enter_structure(VIEW_HEIGHT)
  world:press(BACK_OUT / walk.NOCLIP_SPEED, "fwd")
  world:look(TURN_AROUND_DEGREES, LOOK_DOWN_DEGREES)
  world:step()
end
