local TILT_DEGREES = 40
local SIDE_DEGREES = 60
local WALK_SECONDS = 3

return function(world)
  world:worldgen("plane", TILT_DEGREES)
  world:press(WALK_SECONDS, "fwd")
  world:look(SIDE_DEGREES, 0)
  world:step()
end
