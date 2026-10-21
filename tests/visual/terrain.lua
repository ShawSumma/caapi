local LOOK_DOWN_DEGREES = 10

return function(world)
  world:look(0, LOOK_DOWN_DEGREES)
  world:step()
end
