local walk = require("lib.walk")

local STAIRS = "backroomsstairs"
local LOOK_DEGREES = -60
local LOOK_UP_DEGREES = -20

return function(world)
  world:worldgen("structure", STAIRS)
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  world:look(LOOK_DEGREES, LOOK_UP_DEGREES)
  world:step()
end
