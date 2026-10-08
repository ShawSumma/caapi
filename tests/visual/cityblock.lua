local NOCLIP_SPEED = 0.6
local BACK = 0.3
local RISE = 0.3
local TURN_DEGREES = 90
local LOOK_DOWN_DEGREES = 20

return function(world)
  world:worldgen("structure", "city")
  world:mode("noclip")
  world:look(TURN_DEGREES, 0)
  world:press(BACK / NOCLIP_SPEED, "back")
  world:press(RISE / NOCLIP_SPEED, "up")
  world:look(0, LOOK_DOWN_DEGREES)
  world:step()
end
