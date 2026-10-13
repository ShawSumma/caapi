local climb = require("lib.climb")

local BASEMENT = "basement"
local MIN_CLIMB = 0.2

return function(world)
  world:worldgen("structure", BASEMENT)
  climb.route(world, MIN_CLIMB)
end
