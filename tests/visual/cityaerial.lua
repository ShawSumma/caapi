local NOCLIP_SPEED = 0.6
local RISE = 2.0
local LOOK_DOWN_DEGREES = 89

return function(world)
  world:worldgen("structure", "city")
  world:mode("noclip")
  world:look(0, -LOOK_DOWN_DEGREES)
  world:press(RISE / NOCLIP_SPEED, "fwd")
  world:look(0, 2 * LOOK_DOWN_DEGREES)
  world:step()
end
