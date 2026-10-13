local walk = require("lib.walk")

local BASEMENT = "basement"
local LOOK_DEGREES = 150

return function(world)
  world:worldgen("structure", BASEMENT)
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  world:look(LOOK_DEGREES, 0)
  world:step()
end
