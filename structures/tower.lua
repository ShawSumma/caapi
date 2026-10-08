local box = require("box")

local EDGES = 3

return function(site)
  local palette = box.palette(site)
  local top = box.top(site, EDGES)
  box.tower(site, top, palette)
  box.door(site)
  box.stair_route(site, 0, top)
  site:entrance(-box.HALF, 0, 1)
end
