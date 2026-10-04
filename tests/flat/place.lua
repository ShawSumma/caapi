local walk = require("lib.walk")

local STRAIGHT_DOWN_DEGREES = 89
local AHEAD_DEGREES = 30

return function(world)
  world:worldgen("flat")
  walk.spawn(world)

  world:look(0, STRAIGHT_DOWN_DEGREES)
  assert(not world:place_block(), "placing a block where the player stands is refused")
  world:wait(0.5)
  walk.check_standing(world, "after the refused placement")
  world:look(0, AHEAD_DEGREES - STRAIGHT_DOWN_DEGREES)
  assert(world:place_block(), "placing a block ahead succeeds")
  world:wait(0.5)
  walk.check_standing(world, "after placing ahead")
end
