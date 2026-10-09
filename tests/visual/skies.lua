local NOCLIP_SPEED = 0.6
local TOWARD_DEGREES = -15
local FLIGHT = 1.6
local LOOK_UP_DEGREES = -85

return function(world)
  world:worldgen("terrain")
  world:mode("noclip")
  world:look(TOWARD_DEGREES, 0)
  world:press(FLIGHT / NOCLIP_SPEED, "fwd")
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
