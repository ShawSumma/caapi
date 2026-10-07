local walk = require("lib.walk")

local WALK_SECONDS = 6
local MIN_WALKED_FRACTION = 0.9
local TOWER_MATERIALS = {
  concrete = true,
  white_brick = true,
  grey_brick = true,
  sandstone = true,
  wood_planks = true,
  steel = true,
  marble = true,
}

return function(world)
  world:worldgen("structure", "crown")
  walk.spawn(world)
  local ground = world:altitude()
  local start = world:traveled()
  world:press(WALK_SECONDS, "fwd")
  world:wait(walk.SETTLE_SECONDS)
  local walked = world:traveled() - start
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  local below = world:target_material()
  assert(world:is_on_ground(), "standing in the hall")
  assert(walked >= MIN_WALKED_FRACTION * walk.SPEED * WALK_SECONDS, string.format("walked only %.3f toward the hall door", walked))
  assert(world:altitude() - ground > walk.MIN_BLOCK_EDGE / 2, string.format("rose %.3f, not over the door's threshold", world:altitude() - ground))
  assert(TOWER_MATERIALS[below], string.format("standing on %s instead of the hall floor", tostring(below)))
end
