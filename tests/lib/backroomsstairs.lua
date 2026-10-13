local layout = require("backrooms.layout")

local TOP_FLOOR = 1

return function(site)
  local stairs = site:forward(1):right()
  site:tile(layout.tile, {
    vertex = site:hash("vertex"),
    has_shaft = false,
    is_routed = true,
    forced_stair = { vertex = stairs:hash("vertex"), face = stairs:hash("face"), upper = TOP_FLOOR },
  })
end
