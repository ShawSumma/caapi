local climb = require("lib.climb")
local walk = require("lib.walk")

local MIN_CLIMB = 0.7

return function(world)
  world:worldgen("structure", "library")
  walk.spawn(world)
  climb.route(world, MIN_CLIMB)
end
