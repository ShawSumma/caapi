local climb = require("lib.climb")

local MIN_CLIMB = 0.2

return function(world)
  world:worldgen("structure", "basement")
  climb.route(world, MIN_CLIMB)
end
