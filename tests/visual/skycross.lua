local climb = require("lib.climb")
local walk = require("lib.walk")

local LAST_PLANET_TREAD = 24
local LOOK_UP_DEGREES = -70

return function(world)
  world:worldgen("structure", "skycity")
  world:enter_route()
  world:wait(walk.SETTLE_SECONDS)
  climb.follow(world, LAST_PLANET_TREAD)
  world:wait(walk.SETTLE_SECONDS)
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
