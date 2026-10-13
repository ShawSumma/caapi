local blocks = require("city.blocks")

return function(face, sky, is_routed)
  blocks.tile(face, blocks.root(sky.foot, sky, is_routed))
end
