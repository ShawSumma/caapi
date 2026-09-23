-- Turn 180 degrees, then walk straight ahead over generated terrain.
local walk = require("lib.walk")

walk.spawn()
turn(180, 0, 0.96)
walk.forward(11.2)
wait(0.48)
check(on_ground(), "on ground at the end")
