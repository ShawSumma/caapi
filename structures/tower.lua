local box = require("box")

local EDGES = 3

return function(site)
  local tower = site:pitch_up()
  local palette = box.palette(tower)
  local top = box.top(tower, EDGES)
  box.tower(tower, top, palette)
  box.door(tower)
  box.stair_route(tower, 0, top)
  tower:entrance(-box.HALF, 0, 1)
end
