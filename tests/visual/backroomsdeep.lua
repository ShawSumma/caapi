local climb = require("lib.climb")
local walk = require("lib.walk")

local AHEAD_SECONDS = 5
local TURN_DEGREES = 40
local BACK_SECONDS = 1
local SIDE_DEGREES = -60

return function(world)
  world:worldgen("structure", "risenbackrooms")
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  climb.follow(world, math.huge)
  world:wait(walk.SETTLE_SECONDS)
  world:look(TURN_DEGREES, 0)
  world:press(AHEAD_SECONDS, "fwd")
  world:press(BACK_SECONDS, "back")
  world:look(SIDE_DEGREES, 0)
  world:step()
end
