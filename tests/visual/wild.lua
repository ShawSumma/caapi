local climb = require("lib.climb")
local walk = require("lib.walk")

local WILD = "tests/lib/wild.lua"
local NOCLIP_SPEED = 0.6
local AWAY = 0.6
local RISE = 0.3
local TURN_DEGREES = -120
local LOOK_UP_DEGREES = -30

return function(world)
  world:worldgen("structure", WILD)
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  climb.follow(world, math.huge)
  world:wait(walk.SETTLE_SECONDS)
  world:mode("noclip")
  world:press(AWAY / NOCLIP_SPEED, "fwd")
  world:press(RISE / NOCLIP_SPEED, "up")
  world:look(TURN_DEGREES, LOOK_UP_DEGREES)
  world:step()
end
