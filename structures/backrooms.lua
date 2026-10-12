local layout = require("backrooms.layout")
local town = require("town")

-- A world of nothing but the backrooms, starting in the lobby where the hallways around the root meet.
local SPAWN = { 4.5, 4.5, layout.GROUND }

return function(site)
  site:tile(layout.tile, { vertex = site:hash("vertex"), has_shaft = false })
  town.upright(site):entrance(SPAWN[1], SPAWN[2], SPAWN[3])
end
