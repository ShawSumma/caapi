local climb = require("lib.climb")

local MIN_CLIMB = 2.5

return function(world)
  world:worldgen("structure", "tower")
  pcall(climb.route, world, MIN_CLIMB)
end
