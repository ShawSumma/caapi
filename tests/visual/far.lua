-- The terrain far from the root, where anything carried from the root by long chains of steps shows its errors.
local walk = require("lib.walk")

local CLIMB_SECONDS = 3
local DISTANCE = 10.0
local LOOK_DOWN_DEGREES = 15

return function(world)
  world:mode("fly")
  world:press(CLIMB_SECONDS, "up")
  world:press(DISTANCE / walk.FLY_SPEED, "fwd")
  world:look(0, -LOOK_DOWN_DEGREES)
  world:step()
end
