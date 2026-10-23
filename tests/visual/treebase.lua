local LOOK_UP_DEGREES = -10

return function(world)
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
