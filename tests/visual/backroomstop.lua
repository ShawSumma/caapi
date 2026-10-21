local climb = require("lib.climb")
local walk = require("lib.walk")

local RISE = 0.55
local TURN_DEGREES = 120

return function(world)
  world:worldgen("structure", "risenbackrooms")
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  climb.follow(world, math.huge)
  world:wait(walk.SETTLE_SECONDS)
  world:mode("noclip")
  world:press(RISE / walk.NOCLIP_SPEED, "up")
  world:look(TURN_DEGREES, 0)
  world:step()
end
