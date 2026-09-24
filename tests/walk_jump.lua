local walk = require("lib.walk")

walk.spawn()
local motion = walk.track_motion()
press(4.8, "fwd", "jump")
wait(1.92)
walk.check_hop_speed(motion)
check(on_ground(), "on ground at the end")
