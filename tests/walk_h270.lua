local world = ...
local walk = require("lib.walk")

walk.spawn(world)
world.player:turn(270, 0, 0.96)
local peak = walk.track_horizontal_speed(world)
walk.forward(world, 11.2, 0.75)
world:wait(0.48)
walk.check_speed_limit(world, peak)
world:check(world.player:on_ground(), "on ground at the end")
