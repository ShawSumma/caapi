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
  local ground = world:altitude()
  local highest = ground
  world:on_step(function()
    highest = math.max(highest, world:altitude())
  end)
  world:press(WALK_SECONDS, "fwd")
  world:wait(walk.SETTLE_SECONDS)
  local walked = world:traveled() - start
  local free = walk.SPEED * WALK_SECONDS
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  local below = world:target_material()
  assert(world:is_on_ground(), "standing inside the tower")
  assert(world:altitude() - ground > walk.MIN_BLOCK_EDGE / 2, string.format("rose %.3f, not onto the ground floor through the door", world:altitude() - ground))
  assert(highest - ground < walk.MAX_BLOCK_EDGE, string.format("climbed %.3f, more than the door's threshold", highest - ground))
  assert(walked < MAX_WALKED_FRACTION * free, string.format("walked %.3f of %.3f without reaching the far wall", walked, free))
  assert(TOWER_MATERIALS[below], string.format("standing on %s instead of the ground floor", tostring(below)))
end
