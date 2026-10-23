local CLIMB_SECONDS = 3
local FLY_SECONDS = 8
local AWAY_FROM_TREE_DEGREES = 180

return function(world)
  world:live()
  world:look(AWAY_FROM_TREE_DEGREES, 0)
  world:mode("fly")
  world:press(CLIMB_SECONDS, "up")
  world:press(FLY_SECONDS, "fwd")
  world:step()
end
