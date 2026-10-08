local NOCLIP_SPEED = 0.6
local AHEAD = 4
local RISE = 0.15
local LOOK_UP_DEGREES = -10

return function(world)
  world:worldgen("structure", "city")
  world:mode("noclip")
  world:press(AHEAD / NOCLIP_SPEED, "fwd")
  world:press(RISE / NOCLIP_SPEED, "up")
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
