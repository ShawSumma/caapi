local blocks = require("city.blocks")
local layout = require("backrooms.layout")

local SPAWN = { 14, 4.5, layout.GROUND }

return function(site)
  site:tile(layout.tile, { vertex = site:hash("vertex"), has_shaft = false, is_routed = false })
  blocks.upright(site):entrance(SPAWN[1], SPAWN[2], SPAWN[3])
end
