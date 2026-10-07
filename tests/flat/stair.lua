local walk = require("lib.walk")

local WALK_SECONDS = 3

local function is_on_step(world, standing)
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  local below = world:target_material()
  world:look(0, -walk.STRAIGHT_DOWN_DEGREES)
  return world:is_on_ground() and world:altitude() - standing > walk.MIN_BLOCK_EDGE / 2 and below == walk.LAYER_MATERIALS[1]
end

return function(world)
  world:worldgen("plane")
  walk.spawn(world)
  walk.check_standing(world, "before building")
  walk.build_step(world)

  local standing = world:altitude()
  local motion = walk.track_motion(world)
  local deadline = world:time() + WALK_SECONDS
  world:hold("fwd")
  while world:time() < deadline and not is_on_step(world, standing) do
    world:step()
  end
  world:release("fwd")
  world:wait(walk.SETTLE_SECONDS)
  assert(motion.off_ground == 0, string.format("left the ground on %d steps walking up a one-block step", motion.off_ground))
  walk.check_on_step(world, standing, "after walking onto the step")
end
