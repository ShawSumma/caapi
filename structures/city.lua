local blocks = require("city.blocks")

local SPAWN_SPOT = { 6, 0, -0.5 }

return function(site)
  site:tile(blocks.tile, blocks.root(site, nil, false))
  site:right():entrance(SPAWN_SPOT[1], SPAWN_SPOT[2], SPAWN_SPOT[3])
end
