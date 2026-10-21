local walk = require("lib.walk")

local CLIMB_SECONDS = 3
local DISTANCE = 10.0
local AWAY_FROM_TREE_DEGREES = 180
local LOOK_DOWN_DEGREES = 60

return function(world)
  world:look(AWAY_FROM_TREE_DEGREES, 0)
  world:mode("fly")
  world:press(CLIMB_SECONDS, "up")
  world:press(DISTANCE / walk.FLY_SPEED, "fwd")
  world:look(0, LOOK_DOWN_DEGREES)
  world:step()
end
