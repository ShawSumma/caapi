local NOCLIP_SPEED = 0.6
local RISE = 0.5
local LOOK_DOWN_DEGREES = 20

return function(world)
  world:worldgen("structure", "tests/lib/hamlet.lua")
  world:mode("noclip")
  world:press(RISE / NOCLIP_SPEED, "up")
  world:look(0, LOOK_DOWN_DEGREES)
  world:step()
end
