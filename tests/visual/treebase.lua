local LOOK_UP_DEGREES = -10

-- The foot of the tree by the terrain world's spawn, which the spawn faces.
return function(world)
  world:look(0, LOOK_UP_DEGREES)
  world:step()
end
