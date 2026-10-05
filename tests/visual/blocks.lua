local AIM_DOWN_DEGREES = 20
local YAW_STEP_DEGREES = 15
local MATERIALS = 9

return function(world)
  world:worldgen("plane")
  world:step()
  world:look(0, AIM_DOWN_DEGREES)
  world:look(-YAW_STEP_DEGREES * (MATERIALS - 1) / 2, 0)
  for slot = 1, MATERIALS do
    world:material(slot)
    world:place_block()
    world:look(YAW_STEP_DEGREES, 0)
  end
  world:look(-YAW_STEP_DEGREES * (MATERIALS + 1) / 2, -10)
  world:step()
end
