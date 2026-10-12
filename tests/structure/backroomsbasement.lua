local climb = require("lib.climb")

local BASEMENT = "tests/lib/backroomsbasement.lua"
local MIN_CLIMB = 0.2

-- The stairs out of the basement climb up and round their landing to the house above.
return function(world)
  world:worldgen("structure", BASEMENT)
  climb.route(world, MIN_CLIMB)
end
