local walk = require("lib.walk")

local LEG_SECONDS = 3
local MIN_WALKED_FRACTION = 0.9

worldgen("flat")
walk.spawn()

for _, heading in ipairs({ 0, 90, 180, 270 }) do
  local start = traveled()
  press(LEG_SECONDS, "fwd")
  wait(0.5)
  local walked = traveled() - start
  local free = walk.SPEED * LEG_SECONDS
  check(walked >= MIN_WALKED_FRACTION * free, string.format("heading %d: walked %.1f m of %.1f m", heading, walked, free))
  turn(90, 0, 0.5)
end

local motion = walk.track_motion()
press(LEG_SECONDS, "fwd", "jump")
wait(1)
walk.check_hop_speed(motion)
check(on_ground(), "on ground at the end")
