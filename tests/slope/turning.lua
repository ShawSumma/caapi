local walk = require("lib.walk")

local TILT_DEGREES = 25
local TURN_DEGREES_PER_SECOND = 25
local WALK_SECONDS = 14.4

return function(world)
  walk.on_slope(world, TILT_DEGREES, 0)
  local motion = walk.track_motion(world)
  world:turn_rate(TURN_DEGREES_PER_SECOND, 0)
  world:press(WALK_SECONDS, "fwd")
  world:turn_rate(0, 0)
  world:wait(walk.SETTLE_SECONDS)
  walk.check_speed_limit(motion)
  assert(world:is_on_ground(), "on ground at the end")
end
