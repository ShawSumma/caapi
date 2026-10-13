local LOOK_DEGREES = 0

return function(world)
  world:worldgen("structure", "backrooms")
  world:look(LOOK_DEGREES, 0)
  world:step()
end
