local NOCLIP_SPEED = 0.6
local RISE = 0.6
local LOOK_UP_DEGREES = -12

return function(world)
  world:worldgen("structure", "crown")
  world:mode("noclip")
  world:press(RISE / NOCLIP_SPEED, "up")
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
