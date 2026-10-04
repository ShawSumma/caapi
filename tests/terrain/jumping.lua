local walk = require("lib.walk")

local WALK_SECONDS = 4.8
local LANDING_SECONDS = 1.92

return function(world)
  walk.spawn(world)
  local peak = walk.track_horizontal_speed(world)
  world:press(WALK_SECONDS, "fwd", "jump")
  world:wait(LANDING_SECONDS)
  walk.check_speed_limit(peak)
  assert(world:is_on_ground(), "on ground at the end")
end
