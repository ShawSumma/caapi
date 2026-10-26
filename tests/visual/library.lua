local LOOK_UP_DEGREES = -5

return function(world)
  world:worldgen("structure", "library")
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
