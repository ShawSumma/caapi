local TURN_DEGREES = 100
local LOOK_UP_DEGREES = -10

return function(world)
  world:worldgen("structure", "library")
  world:look(TURN_DEGREES, LOOK_UP_DEGREES)
  world:step()
end
