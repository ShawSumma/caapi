local SKIES = "tests/lib/skies.lua"
local NOCLIP_SPEED = 0.6
local BACK = 1.2
local LOOK_UP_DEGREES = -40

return function(world)
  world:worldgen("structure", SKIES)
  world:enter_route()
  world:mode("noclip")
  world:press(BACK / NOCLIP_SPEED, "back")
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
