local world = ...
local walk = require("lib.walk")

local player = world.player
walk.spawn(world)
local peak = walk.track_horizontal_speed(world)
player:turn_rate(25, 0)
player:press(14.4, "fwd")
player:turn_rate(0, 0)
world:wait(0.96)
walk.check_speed_limit(world, peak)
world:check(player:on_ground(), "on ground at the end")
