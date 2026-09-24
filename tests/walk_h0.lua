local walk = require("lib.walk")

walk.spawn()
walk.forward(11.2)
wait(0.48)
check(on_ground(), "on ground at the end")
