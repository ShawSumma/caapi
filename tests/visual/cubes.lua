local walk = require("lib.walk")

local WALL_BLOCKS = 3
local BACK_SECONDS = 0.3

return function(world)
  world:worldgen("plane")
  walk.build_wall(world, WALL_BLOCKS)
  world:press(BACK_SECONDS, "back")
  world:wait(walk.SETTLE_SECONDS)
end
