local walk = require("lib.walk")

local WALL_BLOCKS = 2
local SIDE_STEP_SECONDS = 0.5
local SIDE_YAW_DEGREES = -35

return function(world)
  world:worldgen("plane")
  walk.build_wall(world, WALL_BLOCKS)
  world:press(SIDE_STEP_SECONDS, "right")
  world:look(SIDE_YAW_DEGREES, 0)
  world:step()
end
