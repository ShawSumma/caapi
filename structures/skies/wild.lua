local blocks = require("city.blocks")
local connector = require("connector")

return function(face, sky, is_routed)
  if blocks.owns_foot(face, sky) then
    connector(sky.foot, sky, sky.ground, is_routed)
  end
end
