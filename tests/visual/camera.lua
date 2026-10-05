local walk = require("lib.walk")

local TILT_DEGREES = 25
local WALK_SECONDS = 3

return function(world)
  walk.on_slope(world, TILT_DEGREES, 0)
  world:up("camera")
  world:press(WALK_SECONDS, "fwd")
  world:step()
end
