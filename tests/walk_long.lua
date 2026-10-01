local world = ...
local walk = require("lib.walk")

local player = world.player
walk.spawn(world)
local peak = walk.track_horizontal_speed(world)
player:hold("fwd")
for _ = 1, 18 do
  world:wait(0.544)
  player:press(0.096, "jump")
end
player:release("fwd")
world:wait(0.96)
walk.check_speed_limit(world, peak)
world:check(player:on_ground(), "on ground at the end")
