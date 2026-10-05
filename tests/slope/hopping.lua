local walk = require("lib.walk")

local TILT_DEGREES = 25
local HEADINGS = { 0, 90, 180 }
local HOPS = 6
local SECONDS_BETWEEN_HOPS = 0.544
local JUMP_PRESS_SECONDS = 0.096
local LANDING_SECONDS = 0.96

return function(world)
  walk.on_slope(world, TILT_DEGREES, 0)
  local motion = walk.track_motion(world)
  for _, heading in ipairs(HEADINGS) do
    world:hold("fwd")
    for _ = 1, HOPS do
      world:wait(SECONDS_BETWEEN_HOPS)
      world:press(JUMP_PRESS_SECONDS, "up")
    end
    world:release("fwd")
    world:wait(LANDING_SECONDS)
    world:turn(90, 0, walk.TURN_SECONDS)
  end
  walk.check_speed_limit(motion)
  assert(world:is_on_ground(), "on ground at the end")
end
