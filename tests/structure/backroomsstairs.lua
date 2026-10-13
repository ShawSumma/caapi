local climb = require("lib.climb")

local STAIRS = "backroomsstairs"
local MIN_CLIMB = 0.25

return function(world)
  world:worldgen("structure", STAIRS)
  climb.route(world, MIN_CLIMB)
end
