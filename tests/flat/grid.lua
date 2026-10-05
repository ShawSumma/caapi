local walk = require("lib.walk")

local WALK_SECONDS = 2
local SETTLE_SECONDS = 1

return function(world)
  world:worldgen("plane")
  walk.spawn(world)
  world:press(WALK_SECONDS, "fwd")
  local traveled = world:traveled()
  world:grid("uniform")
  assert(world:grid() == "uniform", "switched to the uniform grid")
  walk.check_standing(world, "right after switching the grid")
  world:wait(SETTLE_SECONDS)
  walk.check_standing(world, "settled on the uniform grid")
  world:grid("volume")
  walk.check_standing(world, "right after switching back")
  world:press(WALK_SECONDS, "fwd")
  assert(world:traveled() > traveled, "kept walking after switching the grid twice")
end
