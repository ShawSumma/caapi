local walk = require("lib.walk")

local STAIRS = "tests/lib/backroomsstairs.lua"
local LOOK_DEGREES = -60
local LOOK_UP_DEGREES = -20

-- At the foot of the stairs up from the house to the top level, looking up the first flight.
return function(world)
  world:worldgen("structure", STAIRS)
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  world:look(LOOK_DEGREES, LOOK_UP_DEGREES)
  world:step()
end
