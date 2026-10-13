local blocks = require("city.blocks")
local connector = require("connector")
local layout = require("backrooms.layout")

return function(face, sky, is_routed)
  layout.tile(face, { vertex = sky.foot:hash("vertex"), has_shaft = true, is_routed = false })
  if blocks.owns_foot(face, sky) then
    connector(sky.foot, sky, layout.GROUND, is_routed)
  end
end
