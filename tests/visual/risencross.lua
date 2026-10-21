local climb = require("lib.climb")
local walk = require("lib.walk")

local LAST_LOWER_TREAD = 24
local LOOK_UP_DEGREES = -70

return function(world)
  world:worldgen("structure", "risencity")
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  climb.follow(world, LAST_LOWER_TREAD)
  world:wait(walk.SETTLE_SECONDS)
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
