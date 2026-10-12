local LOOK_DEGREES = 0

-- Standing in the lobby of a world of nothing but the backrooms.
return function(world)
  world:worldgen("structure", "backrooms")
  world:look(LOOK_DEGREES, 0)
  world:step()
end
