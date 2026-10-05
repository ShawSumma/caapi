local blocks = require("blocks")

return function(world)
  world:grid("uniform")
  blocks(world)
end
