local walk = require("lib.walk")

local SPRINT_SECONDS = 3
local MIN_SPRINTED_FRACTION = 0.95

return function(world)
  world:worldgen("plane")
  walk.spawn(world)

  local motion = walk.track_motion(world)
  local start = world:traveled()
  world:press(SPRINT_SECONDS, "fwd", "down")
  local sprinted = world:traveled() - start
  world:wait(walk.SETTLE_SECONDS)

  local free = walk.SPRINT_SPEED * SPRINT_SECONDS
  assert(sprinted >= MIN_SPRINTED_FRACTION * free, string.format("sprinted %.2f m of %.1f m", sprinted, free))
  walk.check_speed_limit(motion, walk.SPRINT_SPEED)
  walk.check_standing(world, "after sprinting")
end
