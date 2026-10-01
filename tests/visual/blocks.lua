local world = ...
local player = world.player

local AIM_DOWN_DEGREES = 20
local YAW_STEP_DEGREES = 15
local MATERIALS = 9

world:worldgen("flat")
world:frames(1)
player:look(0, AIM_DOWN_DEGREES)
local yaw = -YAW_STEP_DEGREES * (MATERIALS - 1) / 2
player:look(yaw, 0)
for slot = 1, MATERIALS do
  player:material(slot)
  world:check(player:place_block(), string.format("placed material %d", slot))
  player:look(YAW_STEP_DEGREES, 0)
end
player:look(-YAW_STEP_DEGREES * (MATERIALS + 1) / 2, -10)
world:frames(1)
