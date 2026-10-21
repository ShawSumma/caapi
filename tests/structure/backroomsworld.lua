local walk = require("lib.walk")

return function(world)
  world:worldgen("structure", "backrooms")
  walk.spawn(world)
  world:look(0, walk.STRAIGHT_DOWN_DEGREES)
  local below = world:target_material()
  world:look(0, -2 * walk.STRAIGHT_DOWN_DEGREES)
  local above = world:target_material()
  assert(walk.BACKROOMS_FLOORS[below] ~= nil, string.format("standing on %s instead of the backrooms' floor", tostring(below)))
  assert(walk.BACKROOMS_CEILINGS[above] ~= nil, string.format("under %s instead of the backrooms' ceiling", tostring(above)))
end
