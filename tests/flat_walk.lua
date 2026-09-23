-- On the flat debug floor nothing can block a walk, so every heading must
-- reach full walking speed and hopping must not outrun it.
local walk = require("lib.walk")

worldgen("flat")
walk.spawn()

for _, heading in ipairs({ 0, 90, 180, 270 }) do
  local start = traveled()
  press(3, "fwd")
  wait(0.5)
  local walked = traveled() - start
  -- Reaching 4 m/s at 50 m/s^2 ground acceleration takes 0.08 s.
  check(walked >= 0.9 * walk.SPEED * 3,
    string.format("heading %d: walked %.1f m of %.1f m", heading, walked, walk.SPEED * 3))
  turn(90, 0, 0.5)
end

local motion = walk.track_motion()
press(3, "fwd", "jump")
wait(1)
walk.check_hop_speed(motion)
check(on_ground(), "on ground at the end")
