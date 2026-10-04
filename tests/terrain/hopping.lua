local walk = require("lib.walk")

local HOPS = 18
local SECONDS_BETWEEN_HOPS = 0.544
local JUMP_PRESS_SECONDS = 0.096
local LANDING_SECONDS = 0.96

return function(world)
  walk.spawn(world)
  local peak = walk.track_horizontal_speed(world)
  world:hold("fwd")
  for _ = 1, HOPS do
    world:wait(SECONDS_BETWEEN_HOPS)
    world:press(JUMP_PRESS_SECONDS, "jump")
  end
  world:release("fwd")
  world:wait(LANDING_SECONDS)
  walk.check_speed_limit(peak)
  assert(world:is_on_ground(), "on ground at the end")
end
