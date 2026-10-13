local climb = require("lib.climb")
local walk = require("lib.walk")

local BACKROOMS = "skybackrooms"
local NOCLIP_SPEED = 0.6
local RISE = 0.55
local TURN_DEGREES = 120

return function(world)
  world:worldgen("structure", BACKROOMS)
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  climb.follow(world, math.huge)
  world:wait(walk.SETTLE_SECONDS)
  world:mode("noclip")
  world:press(RISE / NOCLIP_SPEED, "up")
  world:look(TURN_DEGREES, 0)
  world:step()
end
