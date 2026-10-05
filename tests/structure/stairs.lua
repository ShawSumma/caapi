local climb = require("lib.climb")

return function(world)
  world:worldgen("structure", "tower")
  climb.stairs(world)
end
