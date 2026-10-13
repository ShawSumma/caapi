local box = require("tower.box")

local HEIGHT_EDGES = 3

return function(site)
  local tower = site:pitch_up()
  local palette = box.palette(tower)
  local top = box.top(tower, HEIGHT_EDGES)
  box.tower(tower, top, palette)
  box.door(tower)
  box.stair_route(tower, 0, top)
  tower:entrance(-box.HALF_WIDTH, 0, 1)
end
