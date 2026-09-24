local walk = require("lib.walk")

walk.spawn()
walk.forward(4.8)
wait(1.92)
check(on_ground(), "on ground at the end")
