local climb = require("lib.climb")
local walk = require("lib.walk")

local BACKROOMS = "tests/lib/backrooms.lua"
local TURN_DEGREES = 180
local AHEAD_SECONDS = 1.5

return function(world)
  world:worldgen("structure", BACKROOMS)
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  climb.follow(world, math.huge)
  world:wait(walk.SETTLE_SECONDS)
  world:press(AHEAD_SECONDS, "fwd")
  world:look(TURN_DEGREES, 0)
  world:step()
end
