local climb = require("lib.climb")
local walk = require("lib.walk")

local SKIES = "tests/lib/skies.lua"
local LOOK_UP_DEGREES = -75

return function(world)
  world:worldgen("structure", SKIES)
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  climb.follow(world, math.huge)
  world:wait(walk.SETTLE_SECONDS)
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
