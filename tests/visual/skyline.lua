local NOCLIP_SPEED = 0.6
local RISE = 0.45
local TURN_DEGREES = 150
local LOOK_DOWN_DEGREES = 5

return function(world)
  world:worldgen("structure", "city")
  world:mode("noclip")
  world:press(RISE / NOCLIP_SPEED, "up")
  world:look(TURN_DEGREES, LOOK_DOWN_DEGREES)
  world:step()
end
