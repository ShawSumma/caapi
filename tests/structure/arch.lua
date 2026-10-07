local climb = require("lib.climb")

local MIN_CLIMB = 1.8

return function(world)
  world:worldgen("structure", "crown")
  climb.route(world, MIN_CLIMB)
end
