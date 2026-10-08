local HEIGHT = 1.4
local YAW_DEGREES = 45
local LOOK_DOWN_DEGREES = 60

return function(world)
  world:worldgen("structure", "tests/lib/showcase.lua")
  world:mode("noclip")
  world:enter_structure(HEIGHT)
  world:look(YAW_DEGREES, LOOK_DOWN_DEGREES)
  world:step()
end
