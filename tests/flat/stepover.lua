local walk = require("lib.walk")

local WALK_SECONDS = 3
local CLIMB_SPEED_TOLERANCE = 1.5

return function(world)
  world:worldgen("plane")
  walk.spawn(world)
  walk.build_step(world)

  local standing = world:altitude()
  local motion = walk.track_motion(world)
  local fastest = 0
  local traveled = world:traveled()
  world:on_step(function()
    fastest = math.max(fastest, (world:traveled() - traveled) / world:timestep())
    traveled = world:traveled()
    walk.observe(world, motion)
  end)
  local deadline = world:time() + WALK_SECONDS
  world:hold("fwd")
  while world:time() < deadline and not walk.is_on_step(world, standing) do
    world:step()
  end
  world:release("fwd")
  world:on_step(nil)

  assert(walk.is_on_step(world, standing), "walked onto the step")
  assert(motion.off_ground == 0, string.format("left the ground on %d steps walking up a one-block step", motion.off_ground))
  assert(fastest <= walk.SPEED * CLIMB_SPEED_TOLERANCE, string.format("moved at %.4f stepping up, walking is %.4f", fastest, walk.SPEED))
end
