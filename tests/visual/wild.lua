local climb = require("lib.climb")
local walk = require("lib.walk")

local LOOK_UP_DEGREES = -10

return function(world)
  world:worldgen("structure", "risenwild")
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  climb.follow(world, math.huge)
  world:wait(walk.SETTLE_SECONDS)
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
