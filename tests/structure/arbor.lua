local climb = require("lib.climb")
local walk = require("lib.walk")

local MIN_CLIMB = 0.8

return function(world)
  world:worldgen("structure", "arbor")
  walk.spawn(world)
  climb.route(world, MIN_CLIMB)
end
