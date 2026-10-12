local climb = require("lib.climb")

local STAIRS = "tests/lib/backroomsstairs.lua"
local MIN_CLIMB = 0.25

-- The stairs from the second level climb up and round their landing to the top floor.
return function(world)
  world:worldgen("structure", STAIRS)
  climb.route(world, MIN_CLIMB)
end
