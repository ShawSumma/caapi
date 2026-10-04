local walk = require("lib.walk")

local TURN_DEGREES_PER_SECOND = 25
local WALK_SECONDS = 14.4
local SETTLE_SECONDS = 0.96

return function(world)
  walk.spawn(world)
  local peak = walk.track_horizontal_speed(world)
  world:turn_rate(TURN_DEGREES_PER_SECOND, 0)
  world:press(WALK_SECONDS, "fwd")
  world:turn_rate(0, 0)
  world:wait(SETTLE_SECONDS)
  walk.check_speed_limit(peak)
  assert(world:is_on_ground(), "on ground at the end")
end
