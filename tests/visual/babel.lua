local LOOK_UP_DEGREES = -30

return function(world)
  world:worldgen("structure", "babel")
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
