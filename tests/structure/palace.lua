local climb = require("lib.climb")
local walk = require("lib.walk")

local MIN_CLIMB = 0.35

return function(world)
  world:worldgen("structure", "palace")
  walk.spawn(world)
  climb.route(world, MIN_CLIMB)
end
