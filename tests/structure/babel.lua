local climb = require("lib.climb")
local walk = require("lib.walk")

local MIN_CLIMB = 1.2

return function(world)
  world:worldgen("structure", "babel")
  walk.spawn(world)
  climb.route(world, MIN_CLIMB)
end
