local town = require("town")

local SPAWN_SPOT = { 6, 0, -0.5 }

return function(site)
  site:tile(town.tile, town.root(site))
  site:right():entrance(SPAWN_SPOT[1], SPAWN_SPOT[2], SPAWN_SPOT[3])
end
