-- Walk forward for a long stretch, tapping jump every 0.64 s.
local walk = require("lib.walk")

walk.spawn()
local motion = walk.track_motion()
hold("fwd")
for _ = 1, 18 do
  wait(0.544)
  press(0.096, "jump")
end
release("fwd")
wait(0.96)
walk.check_hop_speed(motion)
check(on_ground(), "on ground at the end")
