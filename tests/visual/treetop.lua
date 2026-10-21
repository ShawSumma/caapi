local walk = require("lib.walk")

local TOWARD_TREE = 1.2
local LOOK_UP_DEGREES = -75

-- Up the trunk of the tree by the terrain world's spawn from close by, where its endless column fills the view: from
-- further off all of it shows within a few degrees above its foot.
return function(world)
  world:worldgen("terrain")
  world:mode("noclip")
  world:press(TOWARD_TREE / walk.NOCLIP_SPEED, "fwd")
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
