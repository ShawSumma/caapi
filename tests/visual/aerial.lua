local world = ...
local player = world.player

player:mode("fly")
player:press(1.5, "up")
player:look(0, 60)
world:frames(1)
