local layout = require("backrooms.layout")

local HOUSE_UPSTAIRS = 2

-- The backrooms with a routed flight between the house's two stories in the quarter of the root's face at the far
-- end of its first edge.
return function(site)
  local stairs = site:forward(1):right()
  site:tile(layout.tile, {
    vertex = site:hash("vertex"),
    has_shaft = false,
    is_routed = true,
    forced_stair = { vertex = stairs:hash("vertex"), face = stairs:hash("face"), upper = HOUSE_UPSTAIRS },
  })
end
