local LOOK_UP_DEGREES = -12

return function(world)
  world:worldgen("structure", "city")
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
