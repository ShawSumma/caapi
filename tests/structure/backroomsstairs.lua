local climb = require("lib.climb")

local MIN_CLIMB = 0.25

return function(world)
  world:worldgen("structure", "backroomsstairs")
  climb.route(world, MIN_CLIMB)
end
