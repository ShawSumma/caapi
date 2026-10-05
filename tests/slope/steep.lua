local walk = require("lib.walk")

local TILT_DEGREES = 40
local WALK_SECONDS = 8

return function(world)
  walk.on_slope(world, TILT_DEGREES, 0)
  local motion = walk.track_motion(world)
  local start = world:altitude()
  world:press(WALK_SECONDS, "fwd")
  world:wait(walk.SETTLE_SECONDS)
  walk.check_speed_limit(motion)
  assert(motion.airborne == 0, string.format("left the ground for %d steps walking up a %d degree slope", motion.airborne, TILT_DEGREES))
  assert(world:altitude() > start, "climbed some of the slope")
  assert(world:is_on_ground(), "on ground at the end")
end
