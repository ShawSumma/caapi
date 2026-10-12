local walk = require("lib.walk")

local STAIRS = "tests/lib/backroomsstairs.lua"
local LOOK_DEGREES = 150

-- At the foot of the stairs up from the house's upper story, looking back into its rooms.
return function(world)
  world:worldgen("structure", STAIRS)
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  world:look(LOOK_DEGREES, 0)
  world:step()
end
