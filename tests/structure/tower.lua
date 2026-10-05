local walk = require("lib.walk")

local WALK_SECONDS = 20
local MAX_WALKED_FRACTION = 0.8
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
  world:worldgen("structure", "tower")
  walk.spawn(world)
  local start = world:traveled()
  world:press(WALK_SECONDS, "fwd")
  local walked = world:traveled() - start
  local free = walk.SPEED * WALK_SECONDS
  local target = world:target_material()
  assert(walked < MAX_WALKED_FRACTION * free, string.format("walked %.1f m of %.1f m without reaching the tower", walked, free))
  assert(TOWER_MATERIALS[target], string.format("facing %s instead of the tower after walking into it", tostring(target)))
end
