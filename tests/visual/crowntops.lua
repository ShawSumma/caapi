local NOCLIP_SPEED = 0.6
local TO_HALL_CENTER = 1.45
local ABOVE_ROOF = 0.45
local LOOK_UP_DEGREES = -35

return function(world)
  world:worldgen("structure", "crown")
  world:mode("noclip")
  world:press(TO_HALL_CENTER / NOCLIP_SPEED, "fwd")
  world:press(ABOVE_ROOF / NOCLIP_SPEED, "up")
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
