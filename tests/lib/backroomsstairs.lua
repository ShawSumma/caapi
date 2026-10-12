local layout = require("backrooms.layout")

local TOP_FLOOR = 1

-- The backrooms with a routed stairwell from the top floor down to the next in the quarter of the root's face at the
-- far end of its first edge.
return function(site)
  local stairs = site:forward(1):right()
  site:tile(layout.tile, {
    vertex = site:hash("vertex"),
    has_shaft = false,
    is_routed = true,
    forced_stair = { vertex = stairs:hash("vertex"), face = stairs:hash("face"), upper = TOP_FLOOR },
  })
end
