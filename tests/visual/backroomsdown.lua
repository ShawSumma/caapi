local walk = require("lib.walk")

local LOOK_DEGREES = 150

return function(world)
  world:worldgen("structure", "backroomsstairs")
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  world:look(LOOK_DEGREES, 0)
  world:step()
end
