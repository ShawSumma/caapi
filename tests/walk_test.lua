local world = ...
local walk = require("lib.walk")

walk.spawn(world)
local peak = walk.track_horizontal_speed(world)
walk.forward(world, 4.8, 0.75)
world:wait(1.92)
walk.check_speed_limit(world, peak)
world:check(world.player:on_ground(), "on ground at the end")
