-- Walk forward while continuously turning, tracing a wide arc.
local walk = require("lib.walk")

walk.spawn()
turn_rate(25)
press(14.4, "fwd")
turn_rate(0)
wait(0.96)
check(on_ground(), "on ground at the end")
