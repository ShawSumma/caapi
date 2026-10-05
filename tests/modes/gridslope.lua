local walk = require("lib.walk")

local TILT_DEGREES = 25
local WALK_SECONDS = 8
local MIN_CLIMB_METERS = 10

return function(world)
  walk.on_slope(world, TILT_DEGREES, 0)
  world:up("grid")
  world:wait(walk.SETTLE_SECONDS)
  local motion = walk.track_motion(world)
  local start = world:altitude()
  world:press(WALK_SECONDS, "fwd")
  world:wait(walk.SETTLE_SECONDS)
  walk.check_speed_limit(motion)
  assert(world:altitude() - start >= MIN_CLIMB_METERS, string.format("climbed %.1f m of a %d degree slope with grid gravity", world:altitude() - start, TILT_DEGREES))
  assert(world:is_on_ground(), "on ground at the end")
end
