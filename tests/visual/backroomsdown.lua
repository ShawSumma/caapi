local NOCLIP_SPEED = 0.6
local DROP = 0.55
local LOOK_DEGREES = 45
local LOOK_UP_DEGREES = 0

-- From the backrooms world's lobby straight down through the ground into the layer below.
return function(world)
  world:worldgen("structure", "backrooms")
  world:live()
  world:mode("noclip")
  world:press(DROP / NOCLIP_SPEED, "down")
  world:look(LOOK_DEGREES, LOOK_UP_DEGREES)
  world:step()
end
