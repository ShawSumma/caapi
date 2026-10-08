local EYE = 0.12
local YAW_DEGREES = 225
local LOOK_UP_DEGREES = -20

return function(world)
  world:worldgen("structure", "tests/lib/showcase.lua")
  world:mode("noclip")
  world:enter_structure(EYE)
  world:look(YAW_DEGREES, LOOK_UP_DEGREES)
  world:step()
end
