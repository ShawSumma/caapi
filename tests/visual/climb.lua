local climb = require("lib.climb")

return function(world)
  world:worldgen("structure", "tower")
  pcall(climb.stairs, world)
end
