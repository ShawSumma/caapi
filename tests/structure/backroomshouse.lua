local climb = require("lib.climb")

local HOUSE = "tests/lib/backroomshouse.lua"
local MIN_CLIMB = 0.12

-- The straight flight between the house's stories climbs from downstairs to upstairs.
return function(world)
  world:worldgen("structure", HOUSE)
  climb.route(world, MIN_CLIMB)
end
